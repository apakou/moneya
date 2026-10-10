import { randomBytes } from 'node:crypto';

export const AUTH_CONFIG = Symbol('AUTH_CONFIG');

export interface AuthConfig {
  jwtSecret: Uint8Array;
  otpHmacSecret: Buffer;
  accessTtlSeconds: number;
  refreshTtlSeconds: number;
  otpTtlSeconds: number;
  otpMaxPerWindow: number;
  otpWindowSeconds: number;
  otpResendSeconds: number;
  otpMaxFailuresPerHour: number;
  otpLockoutSeconds: number;
  passcodeMaxFailures: number;
  passcodeLockoutSeconds: number;
  txnTokenTtlSeconds: number;
  /** Lowered in tests; production values are the OWASP-style ones from the contract. */
  argon2: { memoryCost: number; timeCost: number; parallelism: number };
}

export function loadAuthConfig(env: NodeJS.ProcessEnv = process.env): AuthConfig {
  const prod = env.NODE_ENV === 'production';
  const secret = (name: string): Buffer => {
    const v = env[name];
    if (v && v.length >= 32) return Buffer.from(v);
    if (prod) throw new Error(`${name} must be set (>= 32 chars) in production`);
    return randomBytes(32); // dev: ephemeral, sessions die on restart
  };
  return {
    jwtSecret: new Uint8Array(secret('JWT_SECRET')),
    otpHmacSecret: secret('OTP_HMAC_SECRET'),
    accessTtlSeconds: 15 * 60,
    refreshTtlSeconds: 30 * 24 * 3600,
    otpTtlSeconds: 5 * 60,
    otpMaxPerWindow: 3,
    otpWindowSeconds: 10 * 60,
    otpResendSeconds: 60,
    otpMaxFailuresPerHour: 5,
    otpLockoutSeconds: 15 * 60,
    passcodeMaxFailures: 5,
    passcodeLockoutSeconds: 15 * 60,
    txnTokenTtlSeconds: 60,
    argon2: { memoryCost: 64 * 1024, timeCost: 3, parallelism: 1 },
  };
}
