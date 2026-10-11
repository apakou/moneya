export const AUTH_STORE = Symbol('AUTH_STORE');

export type KycTier = 'TIER_0' | 'TIER_1' | 'TIER_2';

export interface UserRow {
  id: string;
  phone: string;
  country: string;
  full_name: string | null;
  photo_url: string | null;
  kyc_tier: KycTier;
  created_at: Date;
}

export interface OtpRow {
  id: string;
  phone: string;
  codeHash: string;
  expiresAt: Date;
  consumedAt: Date | null;
  failedAttempts: number;
  createdAt: Date;
}

export interface RefreshRow {
  id: string;
  userId: string;
  deviceId: string;
  familyId: string;
  tokenHash: string;
  revokedAt: Date | null;
  replacedBy: string | null;
  expiresAt: Date;
}

export interface TxnTokenRow {
  id: string;
  userId: string;
  deviceId: string;
  tokenHash: string;
  consumedAt: Date | null;
  expiresAt: Date;
}

export interface PasscodeRow {
  userId: string;
  hash: string;
  failedAttempts: number;
  lockedUntil: Date | null;
}

/**
 * Persistence port for auth. The Postgres adapter maps 1:1 onto the tables in
 * 0001_init.sql (+ 0004_auth_sessions.sql). Methods that must be atomic in SQL
 * (consume*, revoke*) are single calls here for that reason.
 */
export interface AuthStore {
  countOtpsSince(phone: string, since: Date): Promise<number>;
  insertOtp(row: OtpRow): Promise<void>;
  latestActiveOtp(phone: string, now: Date): Promise<OtpRow | null>;
  bumpOtpFailure(id: string): Promise<void>;
  /** Marks consumed only if still unconsumed; false when someone else won. */
  consumeOtp(id: string, now: Date): Promise<boolean>;
  recordOtpFailure(phone: string, at: Date): Promise<void>;
  countOtpFailuresSince(phone: string, since: Date): Promise<number>;

  findUserByPhone(phone: string): Promise<UserRow | null>;
  findUserById(id: string): Promise<UserRow | null>;
  createUser(phone: string, country: string): Promise<UserRow>;
  upsertDevice(userId: string, deviceId: string): Promise<void>;

  insertRefresh(row: RefreshRow): Promise<void>;
  findRefreshByHash(tokenHash: string): Promise<RefreshRow | null>;
  /** Atomically revoke iff not yet revoked; returns false if already revoked. */
  revokeRefresh(id: string, now: Date, replacedBy: string | null): Promise<boolean>;
  revokeFamily(familyId: string, now: Date): Promise<void>;

  getPasscode(userId: string): Promise<PasscodeRow | null>;
  setPasscode(userId: string, hash: string): Promise<void>;
  /** Atomically increments the failure count; sets `lockedUntil` when the new count reaches `maxFailures`. */
  recordPasscodeFailure(userId: string, maxFailures: number, lockedUntil: Date): Promise<number>;
  resetPasscodeFailures(userId: string): Promise<void>;

  insertTxnToken(row: TxnTokenRow): Promise<void>;
  /** Atomic single-use consume; null when unknown, expired, consumed or wrong binding. */
  consumeTxnToken(
    tokenHash: string,
    userId: string,
    deviceId: string,
    now: Date,
  ): Promise<TxnTokenRow | null>;
}
