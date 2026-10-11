import { poolConfig } from '../src/common/db';

describe('poolConfig (Supabase-ready TLS settings)', () => {
  const url = 'postgres://postgres.abc:secret@aws-0-eu-west-1.pooler.supabase.com:5432/postgres';

  it('no TLS by default for local development', () => {
    expect(
      poolConfig({ DATABASE_URL: 'postgres://postgres@localhost:5432/db' }).ssl,
    ).toBeUndefined();
  });
  it('DATABASE_SSL=true verifies the server certificate', () => {
    expect(poolConfig({ DATABASE_URL: url, DATABASE_SSL: 'true' }).ssl).toEqual({
      rejectUnauthorized: true,
    });
  });
  it('a CA certificate pins trust to it (Supabase "SSL certificate")', () => {
    const cfg = poolConfig({
      DATABASE_URL: url,
      DATABASE_CA_CERT: '-----BEGIN CERTIFICATE-----\nabc\n-----END CERTIFICATE-----',
    });
    expect(cfg.ssl).toMatchObject({
      rejectUnauthorized: true,
      ca: expect.stringContaining('BEGIN CERTIFICATE'),
    });
  });
  it('refuses sslmode in the URL (it would override the verified ssl option)', () => {
    expect(() => poolConfig({ DATABASE_URL: `${url}?sslmode=require` })).toThrow(/sslmode/);
  });
  it('production refuses a remote database without TLS but allows localhost', () => {
    expect(() => poolConfig({ NODE_ENV: 'production', DATABASE_URL: url })).toThrow(
      /requires DATABASE_SSL/,
    );
    expect(() =>
      poolConfig({ NODE_ENV: 'production', DATABASE_URL: 'postgres://u:p@localhost:5432/db' }),
    ).not.toThrow();
    expect(() =>
      poolConfig({ NODE_ENV: 'production', DATABASE_URL: url, DATABASE_SSL: 'true' }),
    ).not.toThrow();
  });
  it('pool size is configurable and defaults sanely', () => {
    expect(poolConfig({ DATABASE_URL: url }).max).toBe(10);
    expect(poolConfig({ DATABASE_URL: url, DATABASE_POOL_MAX: '25' }).max).toBe(25);
    expect(poolConfig({ DATABASE_URL: url, DATABASE_POOL_MAX: 'abc' }).max).toBe(10);
  });
});
