import { Inject, Injectable } from '@nestjs/common';
import * as argon2 from 'argon2';
import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';
import { ApiProblem } from '../common/problem';
import { AUTH_CONFIG, type AuthConfig } from './auth.config';
import { AUTH_STORE, type AuthStore, type UserRow } from './auth.store';
import { signJwt, verifyJwt } from './jwt';
import { parsePhone } from './phone';
import { SMS_PROVIDER, type SmsProvider } from './sms.provider';

export interface AuthContext {
  userId: string;
  deviceId: string;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const sha256 = (v: string): string => createHash('sha256').update(v).digest('hex');
const bad = (detail: string): ApiProblem =>
  new ApiProblem(400, 'VALIDATION_ERROR', 'Invalid request', { detail });
const otpInvalid = (): ApiProblem => new ApiProblem(401, 'OTP_INVALID', 'Invalid or expired code');
const passcodeInvalid = (): ApiProblem =>
  new ApiProblem(401, 'PASSCODE_INVALID', 'Incorrect passcode');

function requirePasscodeFormat(v: unknown, field: string): string {
  if (typeof v !== 'string' || !/^[0-9]{6}$/.test(v)) throw bad(`${field} must be 6 digits`);
  return v;
}

/** Rejects 000000, 111111, 123456, 654321... — trivially guessable. */
function isWeakPasscode(p: string): boolean {
  if (/^(\d)\1{5}$/.test(p)) return true;
  const d = [...p].map(Number);
  const step = (d[1] ?? 0) - (d[0] ?? 0);
  return Math.abs(step) === 1 && d.every((x, i) => i === 0 || x - (d[i - 1] ?? 0) === step);
}

@Injectable()
export class AuthService {
  constructor(
    @Inject(AUTH_STORE) private readonly store: AuthStore,
    @Inject(SMS_PROVIDER) private readonly sms: SmsProvider,
    @Inject(AUTH_CONFIG) private readonly cfg: AuthConfig,
  ) {}

  private now(): Date {
    return new Date();
  }

  // ---- OTP -----------------------------------------------------------------

  async requestOtp(body: unknown, locale: 'fr' | 'en') {
    const b = (body ?? {}) as Record<string, unknown>;
    const phone = parsePhone(b.phone);
    if (!phone) throw bad('phone must be a valid E.164 number');
    if (
      b.device_id !== undefined &&
      !(typeof b.device_id === 'string' && UUID_RE.test(b.device_id))
    ) {
      throw bad('device_id must be a UUID');
    }

    const now = this.now();
    const windowStart = new Date(now.getTime() - this.cfg.otpWindowSeconds * 1000);
    if ((await this.store.countOtpsSince(phone.e164, windowStart)) >= this.cfg.otpMaxPerWindow) {
      throw new ApiProblem(429, 'RATE_LIMITED', 'Too many requests', {
        retryAfterSeconds: this.cfg.otpWindowSeconds,
      });
    }

    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    await this.store.insertOtp({
      id: randomUUID(),
      phone: phone.e164,
      codeHash: this.hashOtp(phone.e164, code),
      expiresAt: new Date(now.getTime() + this.cfg.otpTtlSeconds * 1000),
      consumedAt: null,
      failedAttempts: 0,
      createdAt: now,
    });
    try {
      await this.sms.sendOtp(phone.e164, code, locale);
    } catch {
      throw new ApiProblem(503, 'SMS_UNAVAILABLE', 'Could not send the code, try again shortly');
    }
    // Same response whether or not the number has an account (no enumeration).
    return { retry_after_seconds: this.cfg.otpResendSeconds, masked_destination: phone.masked };
  }

  async verifyOtp(body: unknown) {
    const b = (body ?? {}) as Record<string, unknown>;
    const phone = parsePhone(b.phone);
    if (!phone) throw bad('phone must be a valid E.164 number');
    if (typeof b.code !== 'string' || !/^[0-9]{6}$/.test(b.code))
      throw bad('code must be 6 digits');
    if (typeof b.device_id !== 'string' || !UUID_RE.test(b.device_id))
      throw bad('device_id must be a UUID');

    const now = this.now();
    await this.assertNotLockedOut(phone.e164, now);

    const otp = await this.store.latestActiveOtp(phone.e164, now);
    if (!otp || otp.failedAttempts >= this.cfg.otpMaxFailuresPerHour) {
      await this.store.recordOtpFailure(phone.e164, now);
      throw otpInvalid();
    }
    const expected = Buffer.from(otp.codeHash, 'hex');
    const actual = Buffer.from(this.hashOtp(phone.e164, b.code), 'hex');
    if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
      await this.store.bumpOtpFailure(otp.id);
      await this.store.recordOtpFailure(phone.e164, now);
      throw otpInvalid();
    }
    if (!(await this.store.consumeOtp(otp.id, now))) throw otpInvalid(); // lost a race: single use

    const user =
      (await this.store.findUserByPhone(phone.e164)) ??
      (await this.store.createUser(phone.e164, phone.country));
    await this.store.upsertDevice(user.id, b.device_id);
    return this.issueTokens(user, b.device_id, randomUUID());
  }

  private async assertNotLockedOut(phone: string, now: Date): Promise<void> {
    const hour = await this.store.countOtpFailuresSince(phone, new Date(now.getTime() - 3600_000));
    if (hour < this.cfg.otpMaxFailuresPerHour) return;
    const recent = await this.store.countOtpFailuresSince(
      phone,
      new Date(now.getTime() - this.cfg.otpLockoutSeconds * 1000),
    );
    if (recent > 0) {
      throw new ApiProblem(429, 'OTP_LOCKED', 'Too many attempts', {
        retryAfterSeconds: this.cfg.otpLockoutSeconds,
      });
    }
  }

  private hashOtp(phone: string, code: string): string {
    return createHmac('sha256', this.cfg.otpHmacSecret).update(`${phone}:${code}`).digest('hex');
  }

  // ---- Tokens ----------------------------------------------------------------

  private async issueTokens(
    user: UserRow,
    deviceId: string,
    familyId: string,
    refreshId = randomUUID(),
  ) {
    const now = this.now();
    const iat = Math.floor(now.getTime() / 1000);
    const access = signJwt(
      { sub: user.id, did: deviceId, iat, exp: iat + this.cfg.accessTtlSeconds },
      this.cfg.jwtSecret,
    );
    const r = await this.mintRefresh(user.id, deviceId, familyId, now, refreshId);
    return {
      access_token: access,
      refresh_token: r.token,
      expires_in: this.cfg.accessTtlSeconds,
      user: this.toUser(user),
    };
  }

  private async mintRefresh(
    userId: string,
    deviceId: string,
    familyId: string,
    now: Date,
    id = randomUUID(),
  ) {
    const token = randomBytes(32).toString('base64url');
    await this.store.insertRefresh({
      id,
      userId,
      deviceId,
      familyId,
      tokenHash: sha256(token),
      revokedAt: null,
      replacedBy: null,
      expiresAt: new Date(now.getTime() + this.cfg.refreshTtlSeconds * 1000),
    });
    return { id, token };
  }

  async refresh(body: unknown) {
    const token = (body as Record<string, unknown> | null)?.refresh_token;
    if (typeof token !== 'string' || token.length < 20 || token.length > 200)
      throw bad('refresh_token required');
    const now = this.now();
    const row = await this.store.findRefreshByHash(sha256(token));
    const unauthorized = new ApiProblem(401, 'REFRESH_INVALID', 'Please sign in again');
    if (!row || row.expiresAt <= now) throw unauthorized;
    // Presenting an already-rotated token means it leaked: kill the whole family.
    if (row.revokedAt) {
      await this.store.revokeFamily(row.familyId, now);
      throw unauthorized;
    }
    const user = await this.store.findUserById(row.userId);
    if (!user) throw unauthorized;

    const newId = randomUUID();
    if (!(await this.store.revokeRefresh(row.id, now, newId))) {
      await this.store.revokeFamily(row.familyId, now); // concurrent double-use
      throw unauthorized;
    }
    return this.issueTokens(user, row.deviceId, row.familyId, newId);
  }

  async authenticate(header: string | undefined): Promise<AuthContext> {
    const m = /^Bearer (.+)$/.exec(header ?? '');
    if (!m?.[1]) throw new ApiProblem(401, 'UNAUTHORIZED', 'Authentication required');
    const claims = verifyJwt(m[1], this.cfg.jwtSecret, Math.floor(Date.now() / 1000));
    if (!claims || typeof claims.sub !== 'string' || typeof claims.did !== 'string') {
      throw new ApiProblem(401, 'UNAUTHORIZED', 'Authentication required');
    }
    return { userId: claims.sub, deviceId: claims.did };
  }

  private toUser(u: UserRow) {
    return { ...u, created_at: u.created_at.toISOString() };
  }

  // ---- Passcode / step-up ------------------------------------------------------

  async setPasscode(ctx: AuthContext, body: unknown): Promise<void> {
    const b = (body ?? {}) as Record<string, unknown>;
    const passcode = requirePasscodeFormat(b.passcode, 'passcode');
    if (isWeakPasscode(passcode))
      throw new ApiProblem(400, 'PASSCODE_TOO_WEAK', 'Choose a less predictable passcode');

    if (await this.store.getPasscode(ctx.userId)) {
      await this.verifyPasscode(
        ctx.userId,
        requirePasscodeFormat(b.current_passcode, 'current_passcode'),
      );
    }
    await this.store.setPasscode(
      ctx.userId,
      await argon2.hash(passcode, { type: argon2.argon2id, ...this.cfg.argon2 }),
    );
  }

  async stepUp(ctx: AuthContext, body: unknown) {
    const passcode = requirePasscodeFormat(
      (body as Record<string, unknown> | null)?.passcode,
      'passcode',
    );
    if (!(await this.store.getPasscode(ctx.userId))) {
      throw new ApiProblem(403, 'PASSCODE_NOT_SET', 'Set a passcode first');
    }
    await this.verifyPasscode(ctx.userId, passcode);

    const now = this.now();
    const token = randomBytes(32).toString('base64url');
    const expiresAt = new Date(now.getTime() + this.cfg.txnTokenTtlSeconds * 1000);
    await this.store.insertTxnToken({
      id: randomUUID(),
      userId: ctx.userId,
      deviceId: ctx.deviceId,
      tokenHash: sha256(token),
      consumedAt: null,
      expiresAt,
    });
    return { txn_token: token, expires_at: expiresAt.toISOString() };
  }

  private async verifyPasscode(userId: string, passcode: string): Promise<void> {
    const row = await this.store.getPasscode(userId);
    if (!row) throw passcodeInvalid();
    const now = this.now();
    if (row.lockedUntil && row.lockedUntil > now) {
      throw new ApiProblem(429, 'PASSCODE_LOCKED', 'Too many attempts', {
        retryAfterSeconds: Math.ceil((row.lockedUntil.getTime() - now.getTime()) / 1000),
      });
    }
    if (!(await argon2.verify(row.hash, passcode))) {
      await this.store.recordPasscodeFailure(
        userId,
        this.cfg.passcodeMaxFailures,
        new Date(now.getTime() + this.cfg.passcodeLockoutSeconds * 1000),
      );
      throw passcodeInvalid();
    }
    if (row.failedAttempts > 0 || row.lockedUntil) await this.store.resetPasscodeFailures(userId);
  }

  /** Called by money endpoints (via TxnTokenGuard): single-use, bound to (user, device). */
  async consumeTxnToken(ctx: AuthContext, token: string | undefined): Promise<void> {
    if (!token) throw new ApiProblem(401, 'STEP_UP_REQUIRED', 'Confirm with your passcode');
    const row = await this.store.consumeTxnToken(
      sha256(token),
      ctx.userId,
      ctx.deviceId,
      this.now(),
    );
    if (!row)
      throw new ApiProblem(409, 'TXN_TOKEN_CONSUMED', 'Confirmation expired or already used');
  }
}
