-- 0007_quotes_fiat.sql — quotes carry the fiat-only view the API returns (ADR 0001 D7). Idempotent.
--   fiat_currency / fiat_amount  = from_currency / from_amount (what the user pays or is debited)
--   to_currency / to_amount      = what the user is credited or the payee receives
--   fee_amount                   = all-in fee in the from currency
--   usdc_amount / rate / fee_usdc = INTERNAL settlement leg (never exposed): settlement amount,
--                                   effective rate, fee expressed in settlement units.
ALTER TABLE app.quotes
    ADD COLUMN IF NOT EXISTS to_currency app.fiat_currency,
    ADD COLUMN IF NOT EXISTS to_amount   app.money_amount,
    ADD COLUMN IF NOT EXISTS fee_amount  app.money_amount;
COMMENT ON COLUMN app.quotes.usdc_amount IS 'INTERNAL settlement amount; never returned by the API.';
