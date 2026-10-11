-- 0005_ledger_global_accounts.sql — LDG-02 prerequisite. Append-only, idempotent.
--
-- UNIQUE (kind, user_id, currency) from 0001 does not constrain global accounts
-- (user_id IS NULL): NULLs are distinct, so two FEE_REVENUE/GHS rows were
-- allowed and "get or create" could not be made race-free. This partial index
-- gives global accounts the same one-per-(kind, currency) guarantee.
-- If this fails with a duplicate key error, merge the duplicate accounts first.
CREATE UNIQUE INDEX IF NOT EXISTS ledger_accounts_global_uq
    ON app.ledger_accounts (kind, currency) WHERE user_id IS NULL;
