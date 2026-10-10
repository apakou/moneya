import { createHmac, timingSafeEqual } from 'node:crypto';

/** Minimal HS256 JWT (access tokens only). The algorithm is fixed — never read from the header. */
const HEADER = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');

const mac = (data: string, secret: Uint8Array): Buffer =>
  createHmac('sha256', secret).update(data).digest();

export function signJwt(claims: Record<string, unknown>, secret: Uint8Array): string {
  const body = Buffer.from(JSON.stringify(claims)).toString('base64url');
  return `${HEADER}.${body}.${mac(`${HEADER}.${body}`, secret).toString('base64url')}`;
}

/** Returns the claims, or null for any malformed/forged/expired token. */
export function verifyJwt(
  token: string,
  secret: Uint8Array,
  nowSeconds: number,
): Record<string, unknown> | null {
  const parts = token.split('.');
  if (parts.length !== 3 || parts[0] !== HEADER) return null;
  const [h, b, s] = parts as [string, string, string];
  const given = Buffer.from(s, 'base64url');
  const expected = mac(`${h}.${b}`, secret);
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  try {
    const claims = JSON.parse(Buffer.from(b, 'base64url').toString()) as Record<string, unknown>;
    if (typeof claims.exp !== 'number' || claims.exp <= nowSeconds) return null;
    return claims;
  } catch {
    return null;
  }
}
