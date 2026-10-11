import { randomUUID } from 'node:crypto';
import type {
  AuthStore,
  OtpRow,
  PasscodeRow,
  RefreshRow,
  TxnTokenRow,
  UserRow,
} from './auth.store';

/** Dev/test store. Single-process, so the "atomic" ops are trivially atomic. */
export class InMemoryAuthStore implements AuthStore {
  private otps: OtpRow[] = [];
  private otpFailures: { phone: string; at: Date }[] = [];
  private users: UserRow[] = [];
  private devices = new Set<string>();
  private refresh: RefreshRow[] = [];
  private passcodes = new Map<string, PasscodeRow>();
  private txn: TxnTokenRow[] = [];

  countOtpsSince(phone: string, since: Date) {
    return Promise.resolve(
      this.otps.filter((o) => o.phone === phone && o.createdAt >= since).length,
    );
  }
  insertOtp(row: OtpRow) {
    this.otps.push({ ...row });
    return Promise.resolve();
  }
  latestActiveOtp(phone: string, now: Date) {
    const rows = this.otps
      .filter((o) => o.phone === phone && !o.consumedAt && o.expiresAt > now)
      .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
    return Promise.resolve(rows[0] ? { ...rows[0] } : null);
  }
  bumpOtpFailure(id: string) {
    const o = this.otps.find((x) => x.id === id);
    if (o) o.failedAttempts += 1;
    return Promise.resolve();
  }
  consumeOtp(id: string, now: Date) {
    const o = this.otps.find((x) => x.id === id);
    if (!o || o.consumedAt) return Promise.resolve(false);
    o.consumedAt = now;
    return Promise.resolve(true);
  }
  recordOtpFailure(phone: string, at: Date) {
    this.otpFailures.push({ phone, at });
    return Promise.resolve();
  }
  countOtpFailuresSince(phone: string, since: Date) {
    return Promise.resolve(
      this.otpFailures.filter((f) => f.phone === phone && f.at >= since).length,
    );
  }

  findUserByPhone(phone: string) {
    return Promise.resolve(this.users.find((u) => u.phone === phone) ?? null);
  }
  findUserById(id: string) {
    return Promise.resolve(this.users.find((u) => u.id === id) ?? null);
  }
  createUser(phone: string, country: string) {
    const u: UserRow = {
      id: randomUUID(),
      phone,
      country,
      full_name: null,
      photo_url: null,
      kyc_tier: 'TIER_0',
      created_at: new Date(),
    };
    this.users.push(u);
    return Promise.resolve(u);
  }
  upsertDevice(userId: string, deviceId: string) {
    this.devices.add(`${userId}:${deviceId}`);
    return Promise.resolve();
  }

  insertRefresh(row: RefreshRow) {
    this.refresh.push({ ...row });
    return Promise.resolve();
  }
  findRefreshByHash(tokenHash: string) {
    const r = this.refresh.find((x) => x.tokenHash === tokenHash);
    return Promise.resolve(r ? { ...r } : null);
  }
  revokeRefresh(id: string, now: Date, replacedBy: string | null) {
    const r = this.refresh.find((x) => x.id === id);
    if (!r || r.revokedAt) return Promise.resolve(false);
    r.revokedAt = now;
    r.replacedBy = replacedBy;
    return Promise.resolve(true);
  }
  revokeFamily(familyId: string, now: Date) {
    for (const r of this.refresh) if (r.familyId === familyId && !r.revokedAt) r.revokedAt = now;
    return Promise.resolve();
  }

  getPasscode(userId: string) {
    const p = this.passcodes.get(userId);
    return Promise.resolve(p ? { ...p } : null);
  }
  setPasscode(userId: string, hash: string) {
    this.passcodes.set(userId, { userId, hash, failedAttempts: 0, lockedUntil: null });
    return Promise.resolve();
  }
  recordPasscodeFailure(userId: string, maxFailures: number, lockedUntil: Date) {
    const p = this.passcodes.get(userId);
    if (!p) return Promise.resolve(0);
    p.failedAttempts += 1;
    if (p.failedAttempts >= maxFailures) p.lockedUntil = lockedUntil;
    return Promise.resolve(p.failedAttempts);
  }
  resetPasscodeFailures(userId: string) {
    const p = this.passcodes.get(userId);
    if (p) {
      p.failedAttempts = 0;
      p.lockedUntil = null;
    }
    return Promise.resolve();
  }

  insertTxnToken(row: TxnTokenRow) {
    this.txn.push({ ...row });
    return Promise.resolve();
  }
  consumeTxnToken(tokenHash: string, userId: string, deviceId: string, now: Date) {
    const t = this.txn.find(
      (x) =>
        x.tokenHash === tokenHash &&
        x.userId === userId &&
        x.deviceId === deviceId &&
        !x.consumedAt &&
        x.expiresAt > now,
    );
    if (!t) return Promise.resolve(null);
    t.consumedAt = now;
    return Promise.resolve({ ...t });
  }
}
