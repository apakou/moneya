-- Behavioural tests for 0002 (run after all migrations; leaves no data: everything rolls back).
-- psql -v ON_ERROR_STOP=1 -f tests/0002_ledger.test.sql
BEGIN;

CREATE FUNCTION pg_temp.expect_fail(sql TEXT, needle TEXT) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
    EXECUTE sql;
    -- deferred constraint triggers fire at COMMIT; force them now
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE EXCEPTION 'expected failure containing "%" but statement succeeded: %', needle, sql;
EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%' || needle || '%' THEN
        RAISE EXCEPTION 'wrong error for [%]: got "%", wanted "%"', sql, SQLERRM, needle;
    END IF;
END $f$;

INSERT INTO app.users (id, phone, country) VALUES
    ('00000000-0000-0000-0000-0000000000a1', '+233201234567', 'GH');
INSERT INTO app.ledger_accounts (id, kind, user_id, currency, name) VALUES
    ('00000000-0000-0000-0000-0000000000b1', 'USER_WALLET', '00000000-0000-0000-0000-0000000000a1', 'GHS', 'u1 GHS'),
    ('00000000-0000-0000-0000-0000000000b2', 'FEE_REVENUE', NULL, 'GHS', 'fee GHS'),
    ('00000000-0000-0000-0000-0000000000b3', 'SUSPENSE',    NULL, 'GHS', 'susp GHS');

-- Balanced journal registered in posted_journals: ok
INSERT INTO app.posted_journals (journal_id, ref_type, ref_id) VALUES
    ('00000000-0000-0000-0000-0000000000c1', 'TEST', gen_random_uuid());
INSERT INTO app.ledger_entries (journal_id, account_id, amount_usdc, currency, ref_type, ref_id) VALUES
    ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b3', -100, 'GHS', 'TEST', gen_random_uuid()),
    ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1',  100, 'GHS', 'TEST', gen_random_uuid());
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

DO $$ BEGIN
    IF app.user_available_balance('00000000-0000-0000-0000-0000000000a1', 'GHS') <> 100 THEN
        RAISE EXCEPTION 'available balance should be 100';
    END IF;
    INSERT INTO app.transfers (id, sender_id, recipient_phone, kind, amount_usdc)
        VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', '+233207654321', 'SENT', 30);
    INSERT INTO app.escrow_holds (transfer_id, user_id, amount_usdc, currency)
        VALUES ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', 30, 'GHS');
    IF app.user_available_balance('00000000-0000-0000-0000-0000000000a1', 'GHS') <> 70 THEN
        RAISE EXCEPTION 'available balance should be 70 after a 30 hold';
    END IF;
    IF app.user_available_balance('00000000-0000-0000-0000-0000000000a1', 'XOF') <> 0 THEN
        RAISE EXCEPTION 'other currency should be 0';
    END IF;
END $$;

-- Unbalanced journal
SELECT pg_temp.expect_fail($q$
    WITH p AS (INSERT INTO app.posted_journals (journal_id, ref_type, ref_id)
               VALUES ('00000000-0000-0000-0000-0000000000c2', 'TEST', gen_random_uuid()))
    INSERT INTO app.ledger_entries (journal_id, account_id, amount_usdc, currency, ref_type, ref_id)
    VALUES ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1', 5, 'GHS', 'TEST', gen_random_uuid())
$q$, 'does not balance');

-- Unregistered journal (bypasses dedupe table)
SELECT pg_temp.expect_fail($q$
    INSERT INTO app.ledger_entries (journal_id, account_id, amount_usdc, currency, ref_type, ref_id) VALUES
      ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b3', -1, 'GHS', 'TEST', gen_random_uuid()),
      ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1',  1, 'GHS', 'TEST', gen_random_uuid())
$q$, 'not registered');

-- Duplicate journal id
SELECT pg_temp.expect_fail(
    $q$INSERT INTO app.posted_journals (journal_id, ref_type, ref_id)
       VALUES ('00000000-0000-0000-0000-0000000000c1', 'TEST', gen_random_uuid())$q$, 'duplicate key');

-- Currency mismatch between entry and account
SELECT pg_temp.expect_fail($q$
    INSERT INTO app.ledger_entries (journal_id, account_id, amount_usdc, currency, ref_type, ref_id)
    VALUES ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', 1, 'XOF', 'TEST', gen_random_uuid())
$q$, 'does not match account');

-- Account identity immutable
SELECT pg_temp.expect_fail(
    $q$UPDATE app.ledger_accounts SET currency = 'XOF' WHERE id = '00000000-0000-0000-0000-0000000000b1'$q$, 'immutable');

-- Cross-currency: sum is zero overall but not per currency -> must fail
INSERT INTO app.ledger_accounts (id, kind, user_id, currency, name) VALUES
    ('00000000-0000-0000-0000-0000000000b4', 'SUSPENSE',    NULL, 'XOF', 'susp XOF'),
    ('00000000-0000-0000-0000-0000000000b6', 'FX_POSITION', NULL, 'GHS', 'fx GHS'),
    ('00000000-0000-0000-0000-0000000000b7', 'FX_POSITION', NULL, 'XOF', 'fx XOF');
SELECT pg_temp.expect_fail($q$
    WITH p AS (INSERT INTO app.posted_journals (journal_id, ref_type, ref_id)
               VALUES ('00000000-0000-0000-0000-0000000000c5', 'TEST', gen_random_uuid()))
    INSERT INTO app.ledger_entries (journal_id, account_id, amount_usdc, currency, ref_type, ref_id) VALUES
      ('00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000b1', -10, 'GHS', 'TEST', gen_random_uuid()),
      ('00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000b4',  10, 'XOF', 'TEST', gen_random_uuid())
$q$, 'does not balance in');

-- A proper conversion balances per currency through the FX accounts: ok
INSERT INTO app.posted_journals (journal_id, ref_type, ref_id) VALUES
    ('00000000-0000-0000-0000-0000000000c4', 'TEST', gen_random_uuid());
INSERT INTO app.ledger_entries (journal_id, account_id, amount_usdc, currency, ref_type, ref_id) VALUES
    ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000b1', -10,  'GHS', 'TEST', gen_random_uuid()),
    ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000b6',  10,  'GHS', 'TEST', gen_random_uuid()),
    ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000b7', -700, 'XOF', 'TEST', gen_random_uuid()),
    ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000b4',  700, 'XOF', 'TEST', gen_random_uuid());
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

-- Monitoring view is empty
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM app.v_ledger_imbalance) THEN RAISE EXCEPTION 'imbalance view not empty'; END IF;
END $$;

-- Transition allowlist
INSERT INTO app.transfer_events (transfer_id, from_status, to_status)
    VALUES ('00000000-0000-0000-0000-0000000000d1', NULL, 'DRAFT'),
           ('00000000-0000-0000-0000-0000000000d1', 'DRAFT', 'PROCESSING');
SELECT pg_temp.expect_fail(
    $q$INSERT INTO app.transfer_events (transfer_id, from_status, to_status)
       VALUES ('00000000-0000-0000-0000-0000000000d1', 'COMPLETED', 'PROCESSING')$q$, 'Forbidden transfer transition');
SELECT pg_temp.expect_fail(
    $q$INSERT INTO app.transfer_events (transfer_id, from_status, to_status)
       VALUES ('00000000-0000-0000-0000-0000000000d1', NULL, 'COMPLETED')$q$, 'Forbidden transfer transition');

ROLLBACK;
\echo 0002 ledger tests passed
