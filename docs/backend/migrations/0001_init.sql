-- ============================================================================
-- MoneyA — Initial schema (v1)
-- ============================================================================
-- Target: Supabase (Postgres 15)
-- Convention: snake_case; UUIDv4 PKs; `created_at`/`updated_at` on all rows;
--             RLS ON for every user-owned table; service role bypasses.
--
-- Idempotency: this script is intended to be run by `supabase db push` and
--              re-runnable in dev (every CREATE uses IF NOT EXISTS where
--              possible; ENUMs guarded by DO blocks).
--
-- See `docs/backend/architecture.md` §5 for the ERD this implements.
-- See `docs/backend/openapi.yaml` for the API surface.
-- ============================================================================

-- ----- Extensions ----------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "citext";     -- case-insensitive text
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- search on phone/name
CREATE EXTENSION IF NOT EXISTS "btree_gist"; -- exclusion constraints

-- ----- Schemas -------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS app;
CREATE SCHEMA IF NOT EXISTS audit;
COMMENT ON SCHEMA app IS 'Domain tables (users, transfers, ledger, ...)';
COMMENT ON SCHEMA audit IS 'Append-only audit + webhook event log';

-- ============================================================================
-- ENUMS
-- ============================================================================

DO $$ BEGIN
    CREATE TYPE app.kyc_tier AS ENUM ('TIER_0', 'TIER_1', 'TIER_2');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.kyc_status AS ENUM ('PENDING', 'IN_REVIEW', 'APPROVED', 'REJECTED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.kyc_doc_type AS ENUM (
        'NATIONAL_ID', 'PASSPORT', 'DRIVERS_LICENSE', 'VOTER_CARD'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.kyc_rejection_reason AS ENUM (
        'DOC_BLURRY', 'DOC_EXPIRED', 'SELFIE_MISMATCH',
        'LIVENESS_FAILED', 'DOC_TYPE_UNSUPPORTED', 'MANUAL_REVIEW'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.chain AS ENUM ('SOLANA');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.device_kind AS ENUM ('IOS', 'ANDROID');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.transfer_kind AS ENUM ('SENT', 'RECEIVED', 'ONRAMP', 'OFFRAMP');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.transfer_status AS ENUM (
        'DRAFT', 'PROCESSING', 'COMPLETED', 'FAILED',
        'AWAITING_CLAIM', 'EXPIRED_REFUNDED', 'CANCELLED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.transfer_failure_reason AS ENUM (
        'INSUFFICIENT_FUNDS', 'COMPLIANCE_BLOCK', 'SIGNING_FAILED',
        'RPC_FAILED', 'PROVIDER_REJECTED', 'QUOTE_EXPIRED', 'VELOCITY_LIMIT'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.onramp_status AS ENUM (
        'AWAITING_PAYMENT', 'COLLECTED', 'CREDITING_WALLET',
        'COMPLETED', 'FAILED', 'EXPIRED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.offramp_status AS ENUM (
        'PROCESSING', 'SETTLED', 'FAILED', 'REFUNDED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.payment_method AS ENUM (
        'WAVE', 'MTN_MOMO', 'ORANGE_MONEY', 'MOOV_MONEY',
        'AIRTEL_MONEY', 'MPESA', 'BANK_TRANSFER'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.fiat_currency AS ENUM ('XOF', 'XAF', 'NGN', 'GHS', 'KES');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.payment_request_status AS ENUM (
        'PENDING', 'PAID', 'DECLINED', 'CANCELLED', 'EXPIRED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.claim_status AS ENUM (
        'PENDING', 'REDEEMED', 'EXPIRED', 'CANCELLED'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.notification_kind AS ENUM (
        'TRANSFER_RECEIVED', 'TRANSFER_SENT', 'TRANSFER_FAILED',
        'TRANSFER_EXPIRED_REFUNDED',
        'ONRAMP_COMPLETED', 'OFFRAMP_COMPLETED', 'OFFRAMP_FAILED',
        'PAYMENT_REQUEST_RECEIVED', 'PAYMENT_REQUEST_PAID',
        'KYC_APPROVED', 'KYC_REJECTED',
        'SECURITY_NEW_DEVICE'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.compliance_decision AS ENUM ('ALLOW', 'REVIEW', 'BLOCK');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE app.ledger_account_kind AS ENUM (
        'USER_WALLET',         -- per-user USDC wallet
        'MONEYA_HOT_WALLET',   -- aggregate hot wallet
        'MONEYA_ESCROW',       -- unclaimed transfers
        'YC_RECEIVABLE',       -- Yellow Card owes us (post-collection, pre-mint)
        'YC_PAYABLE',          -- We owe Yellow Card (post-payout, pre-settlement)
        'FEE_REVENUE',         -- MoneyA fee revenue
        'SUSPENSE'             -- in-flight, pending settlement
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- HELPERS
-- ============================================================================

CREATE OR REPLACE FUNCTION app.touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Money: numeric(20, 6). 14 integer digits + 6 decimals = enough for any
-- conceivable USDC amount, with exact decimal arithmetic.
CREATE DOMAIN app.money_amount AS NUMERIC(20, 6)
    CHECK (VALUE >= 0);

-- E.164 phone (server canonicalisation: leading '+', digits only, 7-15 digits).
CREATE DOMAIN app.phone_e164 AS TEXT
    CHECK (VALUE ~ '^\+[1-9][0-9]{6,14}$');

-- ISO 3166-1 alpha-2.
CREATE DOMAIN app.country_iso2 AS TEXT
    CHECK (VALUE ~ '^[A-Z]{2}$');

-- ============================================================================
-- USERS / AUTH
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           app.phone_e164 NOT NULL UNIQUE,
    country         app.country_iso2 NOT NULL,
    full_name       TEXT,
    photo_url       TEXT,
    kyc_tier        app.kyc_tier NOT NULL DEFAULT 'TIER_0',
    deleted_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS users_phone_idx ON app.users (phone);
CREATE INDEX IF NOT EXISTS users_country_idx ON app.users (country);
CREATE INDEX IF NOT EXISTS users_active_idx ON app.users (id) WHERE deleted_at IS NULL;
DROP TRIGGER IF EXISTS users_touch ON app.users;
CREATE TRIGGER users_touch BEFORE UPDATE ON app.users
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE IF NOT EXISTS app.passcode_hashes (
    user_id         UUID PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
    -- Argon2id PHC string (`$argon2id$v=19$m=65536,t=3,p=1$...`)
    hash            TEXT NOT NULL,
    failed_attempts INT  NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
    locked_until    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
DROP TRIGGER IF EXISTS passcode_hashes_touch ON app.passcode_hashes;
CREATE TRIGGER passcode_hashes_touch BEFORE UPDATE ON app.passcode_hashes
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE IF NOT EXISTS app.auth_devices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    device_id       UUID NOT NULL,
    kind            app.device_kind NOT NULL,
    name            TEXT,
    os_version      TEXT,
    app_version     TEXT,
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_id)
);
CREATE INDEX IF NOT EXISTS auth_devices_user_idx ON app.auth_devices (user_id);

CREATE TABLE IF NOT EXISTS app.otp_attempts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone           app.phone_e164 NOT NULL,
    code_hash       TEXT NOT NULL,           -- HMAC-SHA256(code), never plaintext
    expires_at      TIMESTAMPTZ NOT NULL,
    consumed_at     TIMESTAMPTZ,
    failed_attempts INT NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS otp_phone_active_idx
    ON app.otp_attempts (phone, expires_at) WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS app.refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    device_id       UUID NOT NULL,
    token_hash      TEXT NOT NULL UNIQUE,    -- SHA-256 of the refresh JWT
    revoked_at      TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS refresh_tokens_user_active_idx
    ON app.refresh_tokens (user_id) WHERE revoked_at IS NULL;

-- Single-use, 60-second step-up tokens. Stored to enforce single-use semantics
-- across replicas without relying on JWT-only state.
CREATE TABLE IF NOT EXISTS app.txn_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    device_id       UUID NOT NULL,
    token_hash      TEXT NOT NULL UNIQUE,
    consumed_at     TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS txn_tokens_active_idx
    ON app.txn_tokens (user_id, expires_at) WHERE consumed_at IS NULL;

-- ============================================================================
-- KYC
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.kyc_submissions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    document_type       app.kyc_doc_type NOT NULL,
    id_country          app.country_iso2,
    status              app.kyc_status NOT NULL DEFAULT 'PENDING',
    rejection_reason    app.kyc_rejection_reason,
    smile_id_job_id     TEXT UNIQUE,
    raw_smile_response  JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS kyc_submissions_user_idx ON app.kyc_submissions (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS kyc_submissions_status_idx ON app.kyc_submissions (status);
DROP TRIGGER IF EXISTS kyc_submissions_touch ON app.kyc_submissions;
CREATE TRIGGER kyc_submissions_touch BEFORE UPDATE ON app.kyc_submissions
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Document blobs live in Supabase Storage; this row holds metadata + path.
CREATE TABLE IF NOT EXISTS app.kyc_documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id   UUID NOT NULL REFERENCES app.kyc_submissions(id) ON DELETE CASCADE,
    role            TEXT NOT NULL CHECK (role IN ('id_front', 'id_back', 'selfie')),
    storage_path    TEXT NOT NULL,
    mime_type       TEXT NOT NULL,
    size_bytes      INT NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 10 * 1024 * 1024),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (submission_id, role)
);

-- ============================================================================
-- WALLET / RECIPIENTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.wallets (
    user_id             UUID PRIMARY KEY REFERENCES app.users(id) ON DELETE RESTRICT,
    chain               app.chain NOT NULL DEFAULT 'SOLANA',
    privy_wallet_id     TEXT NOT NULL UNIQUE,
    address             TEXT NOT NULL UNIQUE,   -- Solana base58 pubkey
    balance_usdc_cached app.money_amount NOT NULL DEFAULT 0,
    balance_cached_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS wallets_address_idx ON app.wallets (address);

CREATE TABLE IF NOT EXISTS app.address_book (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    phone       app.phone_e164 NOT NULL,
    nickname    TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, phone)
);
CREATE INDEX IF NOT EXISTS address_book_user_idx ON app.address_book (user_id);

-- ============================================================================
-- IDEMPOTENCY
-- ============================================================================
-- One row per (user, route, key). Stored 24h. Replays return the stored
-- response with the same status. The `request_hash` guards against a client
-- reusing a key for a different payload (returns 409 in that case).
CREATE TABLE IF NOT EXISTS app.idempotency_keys (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    route           TEXT NOT NULL,
    key             TEXT NOT NULL,           -- raw client-supplied key (UUIDv4)
    request_hash    TEXT NOT NULL,           -- SHA-256 of canonicalised body
    response_status INT  NOT NULL,
    response_body   JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '24 hours',
    UNIQUE (user_id, route, key)
);
CREATE INDEX IF NOT EXISTS idempotency_expiry_idx ON app.idempotency_keys (expires_at);

-- ============================================================================
-- QUOTES / ONRAMP / OFFRAMP
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.quotes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    kind                TEXT NOT NULL CHECK (kind IN ('ONRAMP', 'OFFRAMP')),
    fiat_currency       app.fiat_currency NOT NULL,
    fiat_amount         app.money_amount NOT NULL,
    usdc_amount         app.money_amount NOT NULL,
    rate                NUMERIC(20, 8) NOT NULL,
    fee_usdc            app.money_amount NOT NULL DEFAULT 0,
    yc_quote_id         TEXT,                -- Yellow Card-side quote reference
    expires_at          TIMESTAMPTZ NOT NULL,
    consumed_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS quotes_user_idx ON app.quotes (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS quotes_active_idx ON app.quotes (id) WHERE consumed_at IS NULL;

CREATE TABLE IF NOT EXISTS app.onramp_orders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
    quote_id            UUID NOT NULL REFERENCES app.quotes(id) ON DELETE RESTRICT,
    status              app.onramp_status NOT NULL DEFAULT 'AWAITING_PAYMENT',
    payment_method      app.payment_method NOT NULL,
    payer_msisdn        app.phone_e164 NOT NULL,
    yc_order_id         TEXT UNIQUE,
    checkout_url        TEXT,
    ussd_instructions   TEXT,
    failure_reason      TEXT,
    next_action_at      TIMESTAMPTZ,         -- resumer worker target
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS onramp_orders_user_idx ON app.onramp_orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS onramp_orders_status_idx ON app.onramp_orders (status);
CREATE INDEX IF NOT EXISTS onramp_orders_resumer_idx
    ON app.onramp_orders (next_action_at)
    WHERE status IN ('AWAITING_PAYMENT', 'COLLECTED', 'CREDITING_WALLET');
DROP TRIGGER IF EXISTS onramp_orders_touch ON app.onramp_orders;
CREATE TRIGGER onramp_orders_touch BEFORE UPDATE ON app.onramp_orders
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

CREATE TABLE IF NOT EXISTS app.offramp_orders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
    quote_id            UUID NOT NULL REFERENCES app.quotes(id) ON DELETE RESTRICT,
    status              app.offramp_status NOT NULL DEFAULT 'PROCESSING',
    payout_method       app.payment_method NOT NULL,
    payee_msisdn        app.phone_e164 NOT NULL,
    payee_name          TEXT,
    yc_order_id         TEXT UNIQUE,
    solana_signature    TEXT,                -- user → hot wallet leg
    failure_reason      TEXT,
    next_action_at      TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    settled_at          TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS offramp_orders_user_idx ON app.offramp_orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS offramp_orders_status_idx ON app.offramp_orders (status);
CREATE INDEX IF NOT EXISTS offramp_orders_resumer_idx
    ON app.offramp_orders (next_action_at)
    WHERE status = 'PROCESSING';
DROP TRIGGER IF EXISTS offramp_orders_touch ON app.offramp_orders;
CREATE TRIGGER offramp_orders_touch BEFORE UPDATE ON app.offramp_orders
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- ============================================================================
-- TRANSFERS
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.transfers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sender_id           UUID REFERENCES app.users(id) ON DELETE RESTRICT,
    recipient_id        UUID REFERENCES app.users(id) ON DELETE RESTRICT,
    recipient_phone     app.phone_e164 NOT NULL,
    kind                app.transfer_kind NOT NULL,
    status              app.transfer_status NOT NULL DEFAULT 'DRAFT',
    amount_usdc         app.money_amount NOT NULL,
    fee_usdc            app.money_amount NOT NULL DEFAULT 0,
    note                TEXT CHECK (char_length(note) <= 140),
    solana_signature    TEXT UNIQUE,
    failure_reason      app.transfer_failure_reason,
    -- Cross-references for linked flows (a single transfer row may back an
    -- onramp credit or an offramp debit).
    onramp_order_id     UUID REFERENCES app.onramp_orders(id) ON DELETE SET NULL,
    offramp_order_id    UUID REFERENCES app.offramp_orders(id) ON DELETE SET NULL,
    next_action_at      TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    completed_at        TIMESTAMPTZ,

    -- Sanity invariants enforced at write time:
    CHECK (
        (kind = 'SENT'     AND sender_id IS NOT NULL) OR
        (kind = 'RECEIVED' AND recipient_id IS NOT NULL) OR
        (kind IN ('ONRAMP', 'OFFRAMP'))
    ),
    CHECK (status <> 'COMPLETED' OR completed_at IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS transfers_sender_idx
    ON app.transfers (sender_id, created_at DESC) WHERE sender_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS transfers_recipient_idx
    ON app.transfers (recipient_id, created_at DESC) WHERE recipient_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS transfers_status_idx ON app.transfers (status);
CREATE INDEX IF NOT EXISTS transfers_resumer_idx
    ON app.transfers (next_action_at)
    WHERE status IN ('PROCESSING', 'AWAITING_CLAIM');
DROP TRIGGER IF EXISTS transfers_touch ON app.transfers;
CREATE TRIGGER transfers_touch BEFORE UPDATE ON app.transfers
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- Transfer state-machine event log (append-only).
CREATE TABLE IF NOT EXISTS app.transfer_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transfer_id     UUID NOT NULL REFERENCES app.transfers(id) ON DELETE CASCADE,
    from_status     app.transfer_status,
    to_status       app.transfer_status NOT NULL,
    reason          TEXT,
    metadata        JSONB,
    at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS transfer_events_transfer_idx
    ON app.transfer_events (transfer_id, at);

-- Forbid UPDATE / DELETE on transfer_events.
CREATE OR REPLACE FUNCTION app.deny_modification()
RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Modification of % rows is forbidden', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS transfer_events_no_update ON app.transfer_events;
CREATE TRIGGER transfer_events_no_update BEFORE UPDATE OR DELETE ON app.transfer_events
    FOR EACH ROW EXECUTE FUNCTION app.deny_modification();

-- Sender-side hold while a transfer is in flight (accounting, not on-chain).
CREATE TABLE IF NOT EXISTS app.escrow_holds (
    transfer_id     UUID PRIMARY KEY REFERENCES app.transfers(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE RESTRICT,
    amount_usdc     app.money_amount NOT NULL,
    released_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS escrow_holds_user_active_idx
    ON app.escrow_holds (user_id) WHERE released_at IS NULL;

-- ============================================================================
-- PAYMENT REQUESTS
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.payment_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id    UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    payer_phone     app.phone_e164 NOT NULL,
    payer_id        UUID REFERENCES app.users(id) ON DELETE SET NULL,
    amount_usdc     app.money_amount NOT NULL,
    note            TEXT CHECK (char_length(note) <= 140),
    status          app.payment_request_status NOT NULL DEFAULT 'PENDING',
    transfer_id     UUID REFERENCES app.transfers(id) ON DELETE SET NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS payment_requests_requester_idx
    ON app.payment_requests (requester_id, created_at DESC);
CREATE INDEX IF NOT EXISTS payment_requests_payer_idx
    ON app.payment_requests (payer_id, created_at DESC) WHERE payer_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS payment_requests_payer_phone_idx
    ON app.payment_requests (payer_phone) WHERE status = 'PENDING';
DROP TRIGGER IF EXISTS payment_requests_touch ON app.payment_requests;
CREATE TRIGGER payment_requests_touch BEFORE UPDATE ON app.payment_requests
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- ============================================================================
-- CLAIM LINKS (unclaimed transfers)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.claim_links (
    transfer_id     UUID PRIMARY KEY REFERENCES app.transfers(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL UNIQUE,    -- SHA-256(token); raw token only in SMS
    status          app.claim_status NOT NULL DEFAULT 'PENDING',
    redeemed_by     UUID REFERENCES app.users(id) ON DELETE SET NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS claim_links_status_expiry_idx
    ON app.claim_links (status, expires_at) WHERE status = 'PENDING';
DROP TRIGGER IF EXISTS claim_links_touch ON app.claim_links;
CREATE TRIGGER claim_links_touch BEFORE UPDATE ON app.claim_links
    FOR EACH ROW EXECUTE FUNCTION app.touch_updated_at();

-- ============================================================================
-- LEDGER (double-entry, append-only)
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.ledger_accounts (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    kind        app.ledger_account_kind NOT NULL,
    -- Owner (NULL for global accounts like FEE_REVENUE / SUSPENSE / hot wallet).
    user_id     UUID REFERENCES app.users(id) ON DELETE RESTRICT,
    currency    TEXT NOT NULL DEFAULT 'USDC',
    -- Mostly informational; the ledger is denominated in USDC at v1.
    name        TEXT NOT NULL,
    metadata    JSONB,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (kind, user_id, currency)
);
CREATE INDEX IF NOT EXISTS ledger_accounts_user_idx ON app.ledger_accounts (user_id);

-- One row per leg of a journal entry. Sum of `amount_usdc` per
-- `journal_id` MUST equal zero (enforced by trigger below).
CREATE TABLE IF NOT EXISTS app.ledger_entries (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_id      UUID NOT NULL,
    account_id      UUID NOT NULL REFERENCES app.ledger_accounts(id) ON DELETE RESTRICT,
    amount_usdc     NUMERIC(20, 6) NOT NULL,  -- signed: +credit, -debit
    currency        TEXT NOT NULL DEFAULT 'USDC',
    ref_type        TEXT NOT NULL,            -- 'TRANSFER' | 'ONRAMP_ORDER' | 'OFFRAMP_ORDER' | 'CLAIM_REFUND'
    ref_id          UUID NOT NULL,
    memo            TEXT,
    posted_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ledger_entries_journal_idx ON app.ledger_entries (journal_id);
CREATE INDEX IF NOT EXISTS ledger_entries_account_idx ON app.ledger_entries (account_id, posted_at DESC);
CREATE INDEX IF NOT EXISTS ledger_entries_ref_idx ON app.ledger_entries (ref_type, ref_id);

DROP TRIGGER IF EXISTS ledger_entries_no_update ON app.ledger_entries;
CREATE TRIGGER ledger_entries_no_update BEFORE UPDATE OR DELETE ON app.ledger_entries
    FOR EACH ROW EXECUTE FUNCTION app.deny_modification();

-- Deferred constraint: every journal must balance to zero. Application code
-- must wrap the inserts in a single transaction; this trigger fires at COMMIT.
CREATE OR REPLACE FUNCTION app.ledger_journal_balance_check()
RETURNS TRIGGER AS $$
DECLARE
    total NUMERIC(20, 6);
BEGIN
    SELECT COALESCE(SUM(amount_usdc), 0) INTO total
    FROM app.ledger_entries
    WHERE journal_id = NEW.journal_id;

    IF total <> 0 THEN
        RAISE EXCEPTION
            'Ledger journal % does not balance: sum=%', NEW.journal_id, total;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ledger_journal_balance ON app.ledger_entries;
CREATE CONSTRAINT TRIGGER ledger_journal_balance
    AFTER INSERT ON app.ledger_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION app.ledger_journal_balance_check();

-- ============================================================================
-- DEVICES / NOTIFICATIONS
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.device_tokens (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    device_id       UUID NOT NULL,
    kind            app.device_kind NOT NULL,
    push_token      TEXT NOT NULL,
    revoked_at      TIMESTAMPTZ,
    last_seen_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, device_id)
);
CREATE INDEX IF NOT EXISTS device_tokens_user_active_idx
    ON app.device_tokens (user_id) WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS app.notifications (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    kind            app.notification_kind NOT NULL,
    title           TEXT NOT NULL,
    body            TEXT NOT NULL,
    deep_link       TEXT,
    ref_type        TEXT,
    ref_id          UUID,
    read_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS notifications_user_idx
    ON app.notifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS notifications_user_unread_idx
    ON app.notifications (user_id, created_at DESC) WHERE read_at IS NULL;

-- ============================================================================
-- COMPLIANCE
-- ============================================================================

CREATE TABLE IF NOT EXISTS app.compliance_alerts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
    rule_code       TEXT NOT NULL,
    decision        app.compliance_decision NOT NULL,
    ref_type        TEXT,
    ref_id          UUID,
    metadata        JSONB,
    reviewed_by     TEXT,                    -- ops user id (admin console)
    reviewed_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS compliance_alerts_user_idx
    ON app.compliance_alerts (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS compliance_alerts_open_idx
    ON app.compliance_alerts (created_at DESC) WHERE reviewed_at IS NULL;

CREATE TABLE IF NOT EXISTS app.sanctioned_entities (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    list_source     TEXT NOT NULL,           -- 'OFAC', 'UN', 'EU'
    full_name       TEXT NOT NULL,
    aliases         TEXT[],
    countries       app.country_iso2[],
    raw             JSONB,
    fetched_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS sanctioned_entities_name_trgm_idx
    ON app.sanctioned_entities USING gin (full_name gin_trgm_ops);

-- ============================================================================
-- WEBHOOKS / AUDIT (in `audit` schema)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit.webhook_events (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider        TEXT NOT NULL,           -- 'YELLOW_CARD' | 'SMILE_ID' | 'PRIVY' | 'TWILIO'
    event_id        TEXT NOT NULL,
    event_type      TEXT NOT NULL,
    raw_payload     JSONB NOT NULL,
    signature_ok    BOOLEAN NOT NULL,
    processed_at    TIMESTAMPTZ,
    error           TEXT,
    received_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, event_id)
);
CREATE INDEX IF NOT EXISTS webhook_events_unprocessed_idx
    ON audit.webhook_events (received_at) WHERE processed_at IS NULL;

CREATE TABLE IF NOT EXISTS audit.audit_log (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_kind      TEXT NOT NULL CHECK (actor_kind IN ('USER', 'OPS', 'SYSTEM')),
    actor_id        TEXT,
    action          TEXT NOT NULL,
    target_type     TEXT,
    target_id       TEXT,
    metadata        JSONB,
    ip_address      INET,
    at              TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_log_actor_idx ON audit.audit_log (actor_id, at DESC);
CREATE INDEX IF NOT EXISTS audit_log_target_idx ON audit.audit_log (target_type, target_id, at DESC);

DROP TRIGGER IF EXISTS audit_log_no_update ON audit.audit_log;
CREATE TRIGGER audit_log_no_update BEFORE UPDATE OR DELETE ON audit.audit_log
    FOR EACH ROW EXECUTE FUNCTION app.deny_modification();

-- ============================================================================
-- ROW-LEVEL SECURITY
-- ============================================================================
-- Convention: every user-owned table has RLS ON. Policies match `auth.uid()`
-- against `user_id` for SELECT and DELETE. Writes go through the service role
-- (bypass RLS) so the backend can enforce business rules. The Flutter client
-- uses the user JWT (anon role) only for read paths that need it; everything
-- transactional is service-role.
--
-- Supabase auto-creates `auth.users`; our `app.users(id)` MUST equal
-- `auth.users(id)` (set in the Auth Service when minting JWTs).

ALTER TABLE app.users               ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.passcode_hashes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.auth_devices        ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.kyc_submissions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.kyc_documents       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.wallets             ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.address_book        ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.idempotency_keys    ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.quotes              ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.onramp_orders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.offramp_orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.transfers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.transfer_events     ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.escrow_holds        ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.payment_requests    ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.claim_links         ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.ledger_entries      ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.ledger_accounts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.device_tokens       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.notifications       ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.compliance_alerts   ENABLE ROW LEVEL SECURITY;

-- Helper: own row policy (SELECT only; service role bypasses).
DO $$ BEGIN
    CREATE POLICY users_self_read ON app.users
        FOR SELECT USING (auth.uid() = id);

    CREATE POLICY auth_devices_self_read ON app.auth_devices
        FOR SELECT USING (auth.uid() = user_id);

    CREATE POLICY kyc_submissions_self_read ON app.kyc_submissions
        FOR SELECT USING (auth.uid() = user_id);

    CREATE POLICY kyc_documents_self_read ON app.kyc_documents
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM app.kyc_submissions s
                WHERE s.id = kyc_documents.submission_id
                  AND s.user_id = auth.uid()
            )
        );

    CREATE POLICY wallets_self_read ON app.wallets
        FOR SELECT USING (auth.uid() = user_id);

    CREATE POLICY address_book_self ON app.address_book
        FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

    CREATE POLICY quotes_self_read ON app.quotes
        FOR SELECT USING (auth.uid() = user_id);

    CREATE POLICY onramp_orders_self_read ON app.onramp_orders
        FOR SELECT USING (auth.uid() = user_id);

    CREATE POLICY offramp_orders_self_read ON app.offramp_orders
        FOR SELECT USING (auth.uid() = user_id);

    -- Transfers: caller must be either sender or recipient.
    CREATE POLICY transfers_party_read ON app.transfers
        FOR SELECT USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

    CREATE POLICY transfer_events_party_read ON app.transfer_events
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM app.transfers t
                WHERE t.id = transfer_events.transfer_id
                  AND (t.sender_id = auth.uid() OR t.recipient_id = auth.uid())
            )
        );

    CREATE POLICY payment_requests_party_read ON app.payment_requests
        FOR SELECT USING (auth.uid() = requester_id OR auth.uid() = payer_id);

    CREATE POLICY notifications_self ON app.notifications
        FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

    CREATE POLICY device_tokens_self ON app.device_tokens
        FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

    -- Ledger: users can read entries on their own accounts only.
    CREATE POLICY ledger_accounts_self_read ON app.ledger_accounts
        FOR SELECT USING (user_id IS NOT NULL AND auth.uid() = user_id);

    CREATE POLICY ledger_entries_self_read ON app.ledger_entries
        FOR SELECT USING (
            EXISTS (
                SELECT 1 FROM app.ledger_accounts a
                WHERE a.id = ledger_entries.account_id
                  AND a.user_id = auth.uid()
            )
        );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- SEED: global ledger accounts
-- ============================================================================

INSERT INTO app.ledger_accounts (kind, user_id, currency, name)
VALUES
    ('MONEYA_HOT_WALLET', NULL, 'USDC', 'MoneyA hot wallet (Solana)'),
    ('MONEYA_ESCROW',     NULL, 'USDC', 'Unclaimed-transfer escrow'),
    ('YC_RECEIVABLE',     NULL, 'USDC', 'Yellow Card receivable'),
    ('YC_PAYABLE',        NULL, 'USDC', 'Yellow Card payable'),
    ('FEE_REVENUE',       NULL, 'USDC', 'MoneyA fee revenue'),
    ('SUSPENSE',          NULL, 'USDC', 'Suspense (in-flight)')
ON CONFLICT (kind, user_id, currency) DO NOTHING;

-- ============================================================================
-- VIEWS (convenience for backend code)
-- ============================================================================

CREATE OR REPLACE VIEW app.v_user_balances AS
SELECT
    a.user_id,
    a.currency,
    COALESCE(SUM(e.amount_usdc), 0) AS balance
FROM app.ledger_accounts a
LEFT JOIN app.ledger_entries e ON e.account_id = a.id
WHERE a.kind = 'USER_WALLET' AND a.user_id IS NOT NULL
GROUP BY a.user_id, a.currency;

COMMENT ON VIEW app.v_user_balances IS
    'Authoritative ledger balance per user. Should match on-chain wallet ± in-flight escrow holds.';

-- ============================================================================
-- DONE
-- ============================================================================

COMMENT ON SCHEMA app IS
    'MoneyA v1 schema. See docs/backend/architecture.md and docs/backend/openapi.yaml.';
