import { Pool, type PoolConfig } from 'pg';

/**
 * Database connection settings from the environment.
 *
 *   DATABASE_URL        postgres://user:pass@host:port/db  (no `sslmode` in it: see below)
 *   DATABASE_SSL        "true" → TLS with certificate verification (required for Supabase)
 *   DATABASE_CA_CERT    PEM of the CA to trust (Supabase: download "SSL certificate" from
 *                       Project Settings → Database); implies DATABASE_SSL=true
 *   DATABASE_POOL_MAX   max connections held by this process (default 10)
 *
 * `sslmode=` is deliberately not supported inside DATABASE_URL: node-postgres lets values parsed from
 * the URL override the `ssl` option, which would silently disable CA verification.
 */
export function poolConfig(env: NodeJS.ProcessEnv = process.env): PoolConfig {
  const url = env.DATABASE_URL;
  if (url && /[?&]sslmode=/i.test(url)) {
    throw new Error(
      'Remove sslmode from DATABASE_URL and use DATABASE_SSL / DATABASE_CA_CERT instead',
    );
  }
  const ca = env.DATABASE_CA_CERT?.trim();
  const ssl = ca
    ? { ca, rejectUnauthorized: true }
    : env.DATABASE_SSL === 'true'
      ? { rejectUnauthorized: true }
      : undefined;
  if (env.NODE_ENV === 'production' && url && !ssl && !/@(localhost|127\.0\.0\.1)/.test(url)) {
    throw new Error(
      'A remote DATABASE_URL in production requires DATABASE_SSL=true (and DATABASE_CA_CERT for Supabase)',
    );
  }
  const max = Number(env.DATABASE_POOL_MAX ?? 10);
  return { connectionString: url, ssl, max: Number.isInteger(max) && max > 0 ? max : 10 };
}

export const createPool = (env: NodeJS.ProcessEnv = process.env): Pool => new Pool(poolConfig(env));
