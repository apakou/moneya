-- ============================================================================
-- MoneyA — 0003: Stellar settlement chain (pooled custody)
-- ============================================================================
-- Applies on top of 0001_init.sql (0002_state_machine.sql is independent).
-- Append-only policy: 0001 is never edited.
--
-- Design: docs/backend/stellar-mvp-plan.md (§3, §4, §5).
--   * Pooled custody (decision D1): users have LEDGER balances only; there is
--     no per-user on-chain account. `app.wallets` therefore no longer requires
--     a custodian wallet id or an address.
--   * Chain details live ONLY in these internal tables. They are never exposed
--     by the public API (plan §1.1: users must never learn stablecoins exist).
--
-- Transaction note: `ALTER TYPE ... ADD VALUE` cannot be USED inside the same
-- transaction that adds it. This file therefore adds the value but never
-- references the 'STELLAR' literal; the backend writes it explicitly.
-- ============================================================================

-- ----- Chain enum ----------------------------------------------------------

ALTER TYPE app.chain ADD VALUE IF NOT EXISTS 'STELLAR';

-- ----- wallets: no per-user on-chain account under pooled custody -----------

ALTER TABLE app.wallets ALTER COLUMN privy_wallet_id DROP NOT NULL;
ALTER TABLE app.wallets ALTER COLUMN address         DROP NOT NULL;
ALTER TABLE app.wallets ALTER COLUMN chain           DROP NOT NULL;
ALTER TABLE app.wallets ALTER COLUMN chain           DROP DEFAULT;

COMMENT ON TABLE app.wallets IS
    'One row per provisioned user account. Under pooled custody (D1) privy_wallet_id/address/chain are NULL; the balance of record is the ledger.';

-- ----- Chain transaction hash (internal only) ------------------------------
-- solana_signature columns are kept until launch for rollback safety and then
-- dropped in a later migration. Never exposed by the API.

ALTER TABLE app.transfers      ADD COLUMN IF NOT EXISTS chain_tx_hash TEXT;
ALTER TABLE app.offramp_orders ADD COLUMN IF NOT EXISTS chain_tx_hash TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS transfers_chain_tx_hash_uidx
    ON app.transfers (chain_tx_hash) WHERE chain_tx_hash IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS offramp_orders_chain_tx_hash_uidx
    ON app.offramp_orders (chain_tx_hash) WHERE chain_tx_hash IS NOT NULL;

COMMENT ON COLUMN app.transfers.solana_signature      IS 'DEPRECATED (Solana). Use chain_tx_hash. Drop after launch.';
COMMENT ON COLUMN app.offramp_orders.solana_signature IS 'DEPRECATED (Solana). Use chain_tx_hash. Drop after launch.';

-- ----- Onramp: per-order deposit memo --------------------------------------
-- Inbound USDC to the deposit account is attributed to an order by memo.

ALTER TABLE app.onramp_orders ADD COLUMN IF NOT EXISTS deposit_memo TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS onramp_orders_deposit_memo_uidx
    ON app.onramp_orders (deposit_memo) WHERE deposit_memo IS NOT NULL;

-- ----- Enums ---------------------------------------------------------------

DO $$ BEGIN
    CREATE TYPE app.chain_account_role AS ENUM (
        'TREASURY_COLD',   -- bulk reserves, multisig, rarely used
        'HOT',             -- signs payouts, funds channels
        'DEPOSIT',         -- receives onramp deposits (memo-attributed)
        'CHANNEL',         -- sequence-number holder for parallel submits
        'FEE_SOURCE'       -- fee-bump source
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.chain_tx_status AS ENUM (
        'BUILT',       -- XDR persisted, not yet submitted
        'SUBMITTED',   -- sent to the network, result unknown/pending
        'CONFIRMED',   -- included in a ledger, successful
        'FAILED',      -- included in a ledger, failed
        'EXPIRED'      -- timebounds passed without inclusion (safe to rebuild)
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.chain_inbound_status AS ENUM (
        'MATCHED',     -- attributed to an order and credited
        'SUSPENSE',    -- wrong asset / no memo / short amount: needs ops
        'IGNORED'      -- not ours (e.g. dust) after review
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ----- chain_accounts ------------------------------------------------------

CREATE TABLE IF NOT EXISTS app.chain_accounts (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role             app.chain_account_role NOT NULL,
    public_key       TEXT NOT NULL UNIQUE,
    network          TEXT NOT NULL CHECK (network IN ('TESTNET', 'PUBLIC')),
    label            TEXT NOT NULL,
    -- Alert when native balance (for reserves + fees) falls below this.
    xlm_low_water    NUMERIC(20, 7) NOT NULL DEFAULT 0 CHECK (xlm_low_water >= 0),
    active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS chain_accounts_role_idx ON app.chain_accounts (role) WHERE active;
DROP TRIGGER IF EXISTS chain_accounts_touch ON app.chain_accounts;
CREATE TRIGGER chain_accounts_touch BEFORE UPDATE ON app.chain_accounts
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- ----- chain_txs: persist hash + signed XDR BEFORE submit ------------------

CREATE TABLE IF NOT EXISTS app.chain_txs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tx_hash          TEXT NOT NULL UNIQUE,            -- known before submit
    xdr              TEXT NOT NULL,                   -- signed envelope; resubmit as-is
    source_account   TEXT NOT NULL,                   -- channel/hot account public key
    purpose          TEXT NOT NULL CHECK (purpose IN ('ONRAMP_SWEEP', 'OFFRAMP_PAYOUT', 'REFUND', 'TREASURY_SWEEP', 'FUNDING')),
    ref_type         TEXT,                            -- 'OFFRAMP_ORDER' | 'TRANSFER' | ...
    ref_id           UUID,
    status           app.chain_tx_status NOT NULL DEFAULT 'BUILT',
    max_time         TIMESTAMPTZ NOT NULL,            -- timebounds upper bound
    attempts         INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    last_error       TEXT,                            -- internal only, never returned by the API
    ledger_sequence  BIGINT,
    submitted_at     TIMESTAMPTZ,
    confirmed_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (status <> 'CONFIRMED' OR confirmed_at IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS chain_txs_ref_idx    ON app.chain_txs (ref_type, ref_id);
CREATE INDEX IF NOT EXISTS chain_txs_open_idx   ON app.chain_txs (max_time) WHERE status IN ('BUILT', 'SUBMITTED');
DROP TRIGGER IF EXISTS chain_txs_touch ON app.chain_txs;
CREATE TRIGGER chain_txs_touch BEFORE UPDATE ON app.chain_txs
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- ----- chain_cursors: payments-stream resume point -------------------------

CREATE TABLE IF NOT EXISTS app.chain_cursors (
    stream_name   TEXT PRIMARY KEY,
    paging_token  TEXT NOT NULL,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ----- chain_inbound_payments: dedupe + matching of deposits ---------------
-- UNIQUE (operation_id) and UNIQUE (tx_hash, op_index) make replaying the stream
-- safe: no double credit.

CREATE TABLE IF NOT EXISTS app.chain_inbound_payments (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tx_hash          TEXT NOT NULL,
    -- Network operation id: globally unique, the primary dedupe key.
    operation_id     TEXT NOT NULL UNIQUE,
    op_index         INTEGER NOT NULL CHECK (op_index >= 0),
    to_account       TEXT NOT NULL,
    from_account     TEXT,
    asset_code       TEXT NOT NULL,
    asset_issuer     TEXT,
    amount           NUMERIC(20, 7) NOT NULL CHECK (amount > 0),
    memo             TEXT,
    status           app.chain_inbound_status NOT NULL,
    suspense_reason  TEXT,
    onramp_order_id  UUID REFERENCES app.onramp_orders(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tx_hash, op_index),
    CHECK (status <> 'SUSPENSE' OR suspense_reason IS NOT NULL),
    CHECK (status <> 'MATCHED'  OR onramp_order_id IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS chain_inbound_status_idx
    ON app.chain_inbound_payments (status) WHERE status = 'SUSPENSE';

-- ----- RLS: internal tables are service-role only --------------------------
-- RLS ON with NO policy = no access for anon/authenticated roles.

ALTER TABLE app.chain_accounts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.chain_txs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.chain_cursors          ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.chain_inbound_payments ENABLE ROW LEVEL SECURITY;

-- ----- Ledger seed wording -------------------------------------------------

UPDATE app.ledger_accounts
   SET name = 'MoneyA hot wallet (Stellar)'
 WHERE kind = 'MONEYA_HOT_WALLET' AND user_id IS NULL;
