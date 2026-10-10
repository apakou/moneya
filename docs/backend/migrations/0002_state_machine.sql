-- ============================================================================
-- 0002_state_machine.sql — LDG-01 (M2). Append-only; applies on top of 0001.
-- Idempotent: safe to re-apply.
--
--   1. Transfer transition allowlist + trigger        (state-machine §10.1)
--   2. app.posted_journals dedupe + enforcement       (ledger §5.3)
--   3. Per-currency journal balance (L1/L6, ADR 0001 D7)
--   4. Entry currency must equal account currency
--   5. Ledger account identity immutable              (L4)
--   6. escrow_holds.currency + user_available_balance (ledger §6.2)
--   7. transfers.parent_transfer_id (mirror RECEIVED rows)
--   8. app.v_ledger_imbalance monitoring view         (ledger §10.4)
--
-- D7 (fiat-denominated user balances): user ledger accounts are in the user's
-- fiat currency; a conversion journal posts legs in two currencies through FX
-- accounts and must balance PER CURRENCY. The column name `amount_usdc` is
-- historical: it holds an amount in the row's `currency`. Internal only —
-- never exposed by the API (plan §1.1).
--
-- Like 0003, this file adds an enum value (FX_POSITION) but does not USE it in
-- the same transaction; the backend provisions FX accounts at runtime.
-- ============================================================================


ALTER TYPE app.ledger_account_kind ADD VALUE IF NOT EXISTS 'FX_POSITION';

-- ----- 1. Transfer transition allowlist -------------------------------------

CREATE TABLE IF NOT EXISTS app._allowed_transfer_transitions (
    from_status app.transfer_status,   -- NULL = initial insert
    to_status   app.transfer_status NOT NULL
);
-- Two partial unique indexes instead of a PK: PK columns cannot be NULL.
CREATE UNIQUE INDEX IF NOT EXISTS allowed_transfer_transitions_initial_uq
    ON app._allowed_transfer_transitions (to_status) WHERE from_status IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS allowed_transfer_transitions_uq
    ON app._allowed_transfer_transitions (from_status, to_status) WHERE from_status IS NOT NULL;

INSERT INTO app._allowed_transfer_transitions (from_status, to_status)
SELECT v.f::app.transfer_status, v.t::app.transfer_status
  FROM (VALUES
    (NULL,             'DRAFT'),
    ('DRAFT',          'PROCESSING'),
    ('DRAFT',          'FAILED'),
    ('DRAFT',          'CANCELLED'),
    ('PROCESSING',     'COMPLETED'),
    ('PROCESSING',     'AWAITING_CLAIM'),
    ('PROCESSING',     'FAILED'),
    ('AWAITING_CLAIM', 'COMPLETED'),
    ('AWAITING_CLAIM', 'EXPIRED_REFUNDED'),
    ('AWAITING_CLAIM', 'CANCELLED')
  ) AS v(f, t)
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION app.check_transfer_transition()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM app._allowed_transfer_transitions
         WHERE from_status IS NOT DISTINCT FROM NEW.from_status
           AND to_status   = NEW.to_status
    ) THEN
        RAISE EXCEPTION 'Forbidden transfer transition: % -> %',
            COALESCE(NEW.from_status::text, '(none)'), NEW.to_status;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS transfer_events_validate_transition ON app.transfer_events;
CREATE TRIGGER transfer_events_validate_transition
    BEFORE INSERT ON app.transfer_events
    FOR EACH ROW EXECUTE FUNCTION app.check_transfer_transition();

-- ----- 2. Journal dedupe ----------------------------------------------------

CREATE TABLE IF NOT EXISTS app.posted_journals (
    journal_id UUID PRIMARY KEY,
    ref_type   TEXT NOT NULL,
    ref_id     UUID NOT NULL,
    posted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS posted_journals_ref_idx ON app.posted_journals (ref_type, ref_id);

DROP TRIGGER IF EXISTS posted_journals_no_update ON app.posted_journals;
CREATE TRIGGER posted_journals_no_update BEFORE UPDATE OR DELETE ON app.posted_journals
    FOR EACH ROW EXECUTE FUNCTION app.deny_modification();

-- Every entry's journal must be registered (deferred: order within the tx is
-- free). A second post with the same journal_id fails on the PK instead of
-- silently double-posting; entries cannot bypass the dedupe table.
CREATE OR REPLACE FUNCTION app.ledger_journal_registered_check()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM app.posted_journals WHERE journal_id = NEW.journal_id) THEN
        RAISE EXCEPTION 'Ledger journal % is not registered in app.posted_journals', NEW.journal_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ledger_journal_registered ON app.ledger_entries;
CREATE CONSTRAINT TRIGGER ledger_journal_registered
    AFTER INSERT ON app.ledger_entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW
    EXECUTE FUNCTION app.ledger_journal_registered_check();

-- ----- 3. Balance per currency (replaces the single-sum check from 0001) ----

CREATE OR REPLACE FUNCTION app.ledger_journal_balance_check()
RETURNS TRIGGER AS $$
DECLARE
    bad RECORD;
BEGIN
    SELECT currency, SUM(amount_usdc) AS total INTO bad
      FROM app.ledger_entries
     WHERE journal_id = NEW.journal_id
     GROUP BY currency
    HAVING SUM(amount_usdc) <> 0
     LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'Ledger journal % does not balance in %: sum=%',
            NEW.journal_id, bad.currency, bad.total;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ----- 4. Entry currency = account currency ----------------------------------

CREATE OR REPLACE FUNCTION app.ledger_entry_currency_check()
RETURNS TRIGGER AS $$
DECLARE
    acct_currency TEXT;
BEGIN
    SELECT currency INTO acct_currency FROM app.ledger_accounts WHERE id = NEW.account_id;
    IF acct_currency IS DISTINCT FROM NEW.currency THEN
        RAISE EXCEPTION 'Ledger entry currency % does not match account % currency %',
            NEW.currency, NEW.account_id, acct_currency;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ledger_entries_currency ON app.ledger_entries;
CREATE TRIGGER ledger_entries_currency BEFORE INSERT ON app.ledger_entries
    FOR EACH ROW EXECUTE FUNCTION app.ledger_entry_currency_check();

-- Callers must state the currency explicitly (the old 'USDC' default is gone
-- with D7). NOT VALID: legacy USDC-denominated user accounts, if any, stay.
ALTER TABLE app.ledger_accounts ALTER COLUMN currency DROP DEFAULT;
ALTER TABLE app.ledger_entries  ALTER COLUMN currency DROP DEFAULT;

DO $$ BEGIN
    ALTER TABLE app.ledger_accounts ADD CONSTRAINT ledger_accounts_user_wallet_fiat
        CHECK (kind <> 'USER_WALLET' OR currency IN ('XOF', 'XAF', 'NGN', 'GHS', 'KES', 'USDC')) NOT VALID;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ----- 5. Account identity is immutable (L4) --------------------------------

CREATE OR REPLACE FUNCTION app.ledger_account_immutable()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.kind <> OLD.kind
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.currency <> OLD.currency THEN
        RAISE EXCEPTION 'Ledger account % identity (kind, user, currency) is immutable', OLD.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ledger_accounts_immutable ON app.ledger_accounts;
CREATE TRIGGER ledger_accounts_immutable BEFORE UPDATE ON app.ledger_accounts
    FOR EACH ROW EXECUTE FUNCTION app.ledger_account_immutable();

-- ----- 6. Escrow currency + available balance -------------------------------

ALTER TABLE app.escrow_holds ADD COLUMN IF NOT EXISTS currency TEXT;
UPDATE app.escrow_holds SET currency = 'USDC' WHERE currency IS NULL;  -- legacy rows
ALTER TABLE app.escrow_holds ALTER COLUMN currency SET NOT NULL;

CREATE OR REPLACE FUNCTION app.user_available_balance(
    p_user_id  UUID,
    p_currency TEXT
) RETURNS NUMERIC(20, 6)
LANGUAGE SQL STABLE AS $$
    SELECT
        COALESCE((SELECT b.balance FROM app.v_user_balances b
                   WHERE b.user_id = p_user_id AND b.currency = p_currency), 0)
      - COALESCE((SELECT SUM(h.amount_usdc) FROM app.escrow_holds h
                   WHERE h.user_id = p_user_id
                     AND h.currency = p_currency
                     AND h.released_at IS NULL), 0);
$$;

-- ----- 7. Mirror rows -------------------------------------------------------

ALTER TABLE app.transfers
    ADD COLUMN IF NOT EXISTS parent_transfer_id UUID REFERENCES app.transfers(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS transfers_parent_idx
    ON app.transfers (parent_transfer_id) WHERE parent_transfer_id IS NOT NULL;

-- ----- 8. Monitoring --------------------------------------------------------

CREATE OR REPLACE VIEW app.v_ledger_imbalance AS
SELECT journal_id,
       currency,
       SUM(amount_usdc) AS imbalance
  FROM app.ledger_entries
 GROUP BY journal_id, currency
HAVING SUM(amount_usdc) <> 0;

COMMENT ON VIEW app.v_ledger_imbalance IS 'Must always be empty. Non-empty = P0 alert.';

