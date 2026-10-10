-- 0004_auth_sessions.sql — M1 auth: refresh-token families + OTP failure log.
-- Append-only; applies on top of 0001. Idempotent.
BEGIN;

-- Refresh rotation with reuse detection (backlog AUTH-05): every token belongs
-- to a family; presenting a rotated (revoked) token revokes the whole family.
ALTER TABLE app.refresh_tokens
    ADD COLUMN IF NOT EXISTS family_id   UUID,
    ADD COLUMN IF NOT EXISTS replaced_by UUID REFERENCES app.refresh_tokens(id) ON DELETE SET NULL;
UPDATE app.refresh_tokens SET family_id = id WHERE family_id IS NULL;
ALTER TABLE app.refresh_tokens ALTER COLUMN family_id SET NOT NULL;
CREATE INDEX IF NOT EXISTS refresh_tokens_family_idx ON app.refresh_tokens (family_id);

-- Per-phone OTP failure log driving the "5 failures / 1h → 15 min lockout" rule.
CREATE TABLE IF NOT EXISTS app.otp_failures (
    id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    phone      app.phone_e164 NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS otp_failures_phone_idx ON app.otp_failures (phone, created_at DESC);

COMMIT;
