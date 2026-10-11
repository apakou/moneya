# Supabase runbook

Decision: the backend's database is **Supabase** (managed PostgreSQL). The backend is plain Node + `pg`; it
uses Supabase **only as hosted Postgres** — not Supabase Auth, Storage or Realtime (yet).

## 1. What you create (once per environment)

Two projects: **staging** and **production**. Pick the region closest to your users and note the project ref
(`Project Settings → General`). On production, turn on **Point-in-Time Recovery** (Database → Backups): the ledger is
the source of truth for money.

Never paste the database password, JWT secrets or service keys into chat, commits or tickets. They go in your
secret manager / the hosting platform's environment.

## 2. Apply the schema

The authoritative migrations are `docs/backend/migrations/000N_*.sql` (append-only, tested in CI). Supabase wants
timestamped files, which are **generated** into `supabase/migrations/`:

```bash
python3 scripts/sync_supabase_migrations.py           # regenerate after adding a migration
python3 scripts/sync_supabase_migrations.py --check   # CI fails if they drift

supabase login
supabase link --project-ref <staging-ref>
supabase db push --dry-run                            # review
supabase db push
```

Then verify on **staging** (the SQL test rolls back, it leaves no data):

```bash
psql "$DIRECT_DB_URL" -v ON_ERROR_STOP=1 -f docs/backend/migrations/tests/0002_ledger.test.sql
psql "$DIRECT_DB_URL" -c "select count(*) from app.v_ledger_imbalance"   # must be 0
```

Compatibility note: everything was tested on **PostgreSQL 16**; `supabase/config.toml` targets 17 (the current
default for new projects). Run the SQL test above on staging before production, and check
`SHOW server_version;` matches `[db] major_version`.

## 3. Connect the backend

`Project Settings → Database → Connection string`. Use the **Session pooler** (port 5432 on the pooler host) to start;
the **Transaction pooler** (port 6543) also works — the code uses only transaction-scoped locks and no named
prepared statements.

| Variable | Value |
|---|---|
| `DATABASE_URL` | `postgresql://postgres.<ref>:<password>@<pooler-host>:5432/postgres` — **without** `sslmode` |
| `DATABASE_CA_CERT` | PEM text of Supabase's "SSL certificate" (same page). Implies TLS with verification |
| `DATABASE_SSL` | `true` if you rely on the system trust store instead of `DATABASE_CA_CERT` |
| `DATABASE_POOL_MAX` | default 10 per process; keep (instances × max) under your plan's connection limit |

`sslmode=` inside the URL is rejected on purpose: node-postgres lets URL values override the `ssl` option, which
would silently drop certificate verification. In production a remote database without TLS refuses to start.

Other secrets the API needs: `JWT_SECRET`, `OTP_HMAC_SECRET` (≥ 32 chars), `SMS_PROVIDER=http` +
`SMS_HTTP_CONFIGS`, `RAMP_RATES` (see `backend/.env.example`).

## 4. Security posture

- **Data API exposure:** `supabase/config.toml` exposes only `public`. Our tables live in `app` and `audit` and must
  **not** be added to "Exposed schemas". Nothing talks to PostgREST.
- **Row-level security:** migration 0001 enables RLS with policies based on `auth.uid()` (Supabase Auth). The backend
  does its own authentication and connects as `postgres`, which bypasses RLS, so those policies are dormant
  defence-in-depth. The comment in 0001 saying `app.users.id` must equal `auth.users.id` does **not** apply: users are
  created by the backend with its own ids. (Do not edit 0001; it is append-only.)
- **Hardening to do before launch:** create a dedicated `moneya_api` role with only the grants the backend needs and
  connect with that instead of `postgres`.
- **KYC documents** (not built yet) will need object storage; Supabase Storage is the natural choice, with private
  buckets and signed URLs.

## 5. Local development

`supabase start` (needs Docker) boots Postgres with the real `auth` schema and applies `supabase/migrations/`.
Local URL: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`. Or use any PostgreSQL 16 and the numbered files
(that is what CI does, with a stub `auth.uid()`).
