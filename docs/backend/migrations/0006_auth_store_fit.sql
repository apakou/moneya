-- 0006_auth_store_fit.sql — fits the 0001/0004 auth tables to the Postgres AuthStore. Idempotent.

-- OTP verify only knows the device id; the kind (IOS/ANDROID) arrives with POST /v1/devices (AUTH-06).
ALTER TABLE app.auth_devices ALTER COLUMN kind DROP NOT NULL;

-- Rotation revokes the old refresh row (pointing at the successor) before the successor
-- row is inserted, so this informational pointer cannot be an enforced FK.
ALTER TABLE app.refresh_tokens DROP CONSTRAINT IF EXISTS refresh_tokens_replaced_by_fkey;
