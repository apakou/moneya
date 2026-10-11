import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Pool } from 'pg';
import type {
  AuthStore,
  KycTier,
  OtpRow,
  PasscodeRow,
  RefreshRow,
  TxnTokenRow,
  UserRow,
} from './auth.store';

const USER_COLS = 'id, phone, country, full_name, photo_url, kyc_tier, created_at';

/** PostgreSQL adapter for {@link AuthStore}; tables from 0001 + 0004 + 0006. */
@Injectable()
export class PgAuthStore implements AuthStore, OnModuleDestroy {
  constructor(private readonly pool: Pool) {}

  static fromUrl(connectionString: string): PgAuthStore {
    return new PgAuthStore(new Pool({ connectionString, max: 10 }));
  }

  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }

  // ----- OTP -----------------------------------------------------------------

  async countOtpsSince(phone: string, since: Date): Promise<number> {
    const { rows } = await this.pool.query<{ n: number }>(
      'SELECT count(*)::int AS n FROM app.otp_attempts WHERE phone = $1 AND created_at >= $2',
      [phone, since],
    );
    return rows[0]!.n;
  }

  async insertOtp(r: OtpRow): Promise<void> {
    await this.pool.query(
      `INSERT INTO app.otp_attempts (id, phone, code_hash, expires_at, consumed_at, failed_attempts, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [r.id, r.phone, r.codeHash, r.expiresAt, r.consumedAt, r.failedAttempts, r.createdAt],
    );
  }

  async latestActiveOtp(phone: string, now: Date): Promise<OtpRow | null> {
    const { rows } = await this.pool.query(
      `SELECT id, phone, code_hash, expires_at, consumed_at, failed_attempts, created_at
         FROM app.otp_attempts
        WHERE phone = $1 AND consumed_at IS NULL AND expires_at > $2
        ORDER BY created_at DESC LIMIT 1`,
      [phone, now],
    );
    const r = rows[0];
    return r
      ? {
          id: r.id,
          phone: r.phone,
          codeHash: r.code_hash,
          expiresAt: r.expires_at,
          consumedAt: r.consumed_at,
          failedAttempts: r.failed_attempts,
          createdAt: r.created_at,
        }
      : null;
  }

  async bumpOtpFailure(id: string): Promise<void> {
    await this.pool.query(
      'UPDATE app.otp_attempts SET failed_attempts = failed_attempts + 1 WHERE id = $1',
      [id],
    );
  }

  async consumeOtp(id: string, now: Date): Promise<boolean> {
    const r = await this.pool.query(
      'UPDATE app.otp_attempts SET consumed_at = $2 WHERE id = $1 AND consumed_at IS NULL',
      [id, now],
    );
    return r.rowCount === 1;
  }

  async recordOtpFailure(phone: string, at: Date): Promise<void> {
    await this.pool.query('INSERT INTO app.otp_failures (phone, created_at) VALUES ($1, $2)', [
      phone,
      at,
    ]);
  }

  async countOtpFailuresSince(phone: string, since: Date): Promise<number> {
    const { rows } = await this.pool.query<{ n: number }>(
      'SELECT count(*)::int AS n FROM app.otp_failures WHERE phone = $1 AND created_at >= $2',
      [phone, since],
    );
    return rows[0]!.n;
  }

  // ----- Users / devices -----------------------------------------------------------

  async findUserByPhone(phone: string): Promise<UserRow | null> {
    const { rows } = await this.pool.query(
      `SELECT ${USER_COLS} FROM app.users WHERE phone = $1 AND deleted_at IS NULL`,
      [phone],
    );
    return rows[0] ? this.toUser(rows[0]) : null;
  }

  async findUserById(id: string): Promise<UserRow | null> {
    const { rows } = await this.pool.query(
      `SELECT ${USER_COLS} FROM app.users WHERE id = $1 AND deleted_at IS NULL`,
      [id],
    );
    return rows[0] ? this.toUser(rows[0]) : null;
  }

  /** Race-safe: two first logins for the same phone yield the same row. */
  async createUser(phone: string, country: string): Promise<UserRow> {
    const { rows } = await this.pool.query(
      `INSERT INTO app.users (phone, country) VALUES ($1, $2)
       ON CONFLICT (phone) DO UPDATE SET phone = EXCLUDED.phone
       RETURNING ${USER_COLS}`,
      [phone, country],
    );
    return this.toUser(rows[0]);
  }

  async upsertDevice(userId: string, deviceId: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO app.auth_devices (user_id, device_id) VALUES ($1, $2)
       ON CONFLICT (user_id, device_id) DO UPDATE SET last_seen_at = now()`,
      [userId, deviceId],
    );
  }

  private toUser(r: Record<string, unknown>): UserRow {
    return {
      id: r.id as string,
      phone: r.phone as string,
      country: r.country as string,
      full_name: (r.full_name as string | null) ?? null,
      photo_url: (r.photo_url as string | null) ?? null,
      kyc_tier: r.kyc_tier as KycTier,
      created_at: r.created_at as Date,
    };
  }

  // ----- Refresh tokens ----------------------------------------------------------------

  async insertRefresh(r: RefreshRow): Promise<void> {
    await this.pool.query(
      `INSERT INTO app.refresh_tokens (id, user_id, device_id, family_id, token_hash, revoked_at, replaced_by, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [r.id, r.userId, r.deviceId, r.familyId, r.tokenHash, r.revokedAt, r.replacedBy, r.expiresAt],
    );
  }

  async findRefreshByHash(tokenHash: string): Promise<RefreshRow | null> {
    const { rows } = await this.pool.query(
      `SELECT id, user_id, device_id, family_id, token_hash, revoked_at, replaced_by, expires_at
         FROM app.refresh_tokens WHERE token_hash = $1`,
      [tokenHash],
    );
    const r = rows[0];
    return r
      ? {
          id: r.id,
          userId: r.user_id,
          deviceId: r.device_id,
          familyId: r.family_id,
          tokenHash: r.token_hash,
          revokedAt: r.revoked_at,
          replacedBy: r.replaced_by,
          expiresAt: r.expires_at,
        }
      : null;
  }

  async revokeRefresh(id: string, now: Date, replacedBy: string | null): Promise<boolean> {
    const r = await this.pool.query(
      'UPDATE app.refresh_tokens SET revoked_at = $2, replaced_by = $3 WHERE id = $1 AND revoked_at IS NULL',
      [id, now, replacedBy],
    );
    return r.rowCount === 1;
  }

  async revokeFamily(familyId: string, now: Date): Promise<void> {
    await this.pool.query(
      'UPDATE app.refresh_tokens SET revoked_at = $2 WHERE family_id = $1 AND revoked_at IS NULL',
      [familyId, now],
    );
  }

  // ----- Passcode -------------------------------------------------------------------------

  async getPasscode(userId: string): Promise<PasscodeRow | null> {
    const { rows } = await this.pool.query(
      'SELECT user_id, hash, failed_attempts, locked_until FROM app.passcode_hashes WHERE user_id = $1',
      [userId],
    );
    const r = rows[0];
    return r
      ? {
          userId: r.user_id,
          hash: r.hash,
          failedAttempts: r.failed_attempts,
          lockedUntil: r.locked_until,
        }
      : null;
  }

  async setPasscode(userId: string, hash: string): Promise<void> {
    await this.pool.query(
      `INSERT INTO app.passcode_hashes (user_id, hash) VALUES ($1, $2)
       ON CONFLICT (user_id) DO UPDATE SET hash = EXCLUDED.hash, failed_attempts = 0, locked_until = NULL`,
      [userId, hash],
    );
  }

  async recordPasscodeFailure(
    userId: string,
    maxFailures: number,
    lockedUntil: Date,
  ): Promise<number> {
    const { rows } = await this.pool.query<{ failed_attempts: number }>(
      `UPDATE app.passcode_hashes
          SET failed_attempts = failed_attempts + 1,
              locked_until = CASE WHEN failed_attempts + 1 >= $2 THEN $3::timestamptz ELSE locked_until END
        WHERE user_id = $1
        RETURNING failed_attempts`,
      [userId, maxFailures, lockedUntil],
    );
    return rows[0]?.failed_attempts ?? 0;
  }

  async resetPasscodeFailures(userId: string): Promise<void> {
    await this.pool.query(
      'UPDATE app.passcode_hashes SET failed_attempts = 0, locked_until = NULL WHERE user_id = $1',
      [userId],
    );
  }

  // ----- Txn tokens ---------------------------------------------------------------------------

  async insertTxnToken(r: TxnTokenRow): Promise<void> {
    await this.pool.query(
      'INSERT INTO app.txn_tokens (id, user_id, device_id, token_hash, expires_at) VALUES ($1, $2, $3, $4, $5)',
      [r.id, r.userId, r.deviceId, r.tokenHash, r.expiresAt],
    );
  }

  /** Single statement = atomic single-use, even across replicas. */
  async consumeTxnToken(
    tokenHash: string,
    userId: string,
    deviceId: string,
    now: Date,
  ): Promise<TxnTokenRow | null> {
    const { rows } = await this.pool.query(
      `UPDATE app.txn_tokens SET consumed_at = $4
        WHERE token_hash = $1 AND user_id = $2 AND device_id = $3
          AND consumed_at IS NULL AND expires_at > $4
        RETURNING id, user_id, device_id, token_hash, consumed_at, expires_at`,
      [tokenHash, userId, deviceId, now],
    );
    const r = rows[0];
    return r
      ? {
          id: r.id,
          userId: r.user_id,
          deviceId: r.device_id,
          tokenHash: r.token_hash,
          consumedAt: r.consumed_at,
          expiresAt: r.expires_at,
        }
      : null;
  }
}
