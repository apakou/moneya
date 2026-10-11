import { Inject, Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import type { Pool } from 'pg';
import { ApiProblem } from './problem';

export const IDEMPOTENCY_POOL = Symbol('IDEMPOTENCY_POOL');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Stable JSON (sorted keys) so equivalent bodies hash equal. */
function canonical(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(canonical).join(',')}]`;
  if (v && typeof v === 'object') {
    return `{${Object.keys(v as object)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canonical((v as Record<string, unknown>)[k])}`)
      .join(',')}}`;
  }
  return JSON.stringify(v);
}

/**
 * `Idempotency-Key` for money POSTs (openapi.yaml, 24 h). Same key + same body replays the
 * stored response with the original status; same key + a different body is a 422.
 * Concurrent duplicates are serialized with an advisory lock, so the second waits and replays.
 * Failed attempts (non-2xx) are not stored: the client may retry the same key.
 */
@Injectable()
export class IdempotencyService {
  constructor(@Inject(IDEMPOTENCY_POOL) private readonly pool: Pool) {}

  async run<T extends object>(
    userId: string,
    route: string,
    key: string | undefined,
    body: unknown,
    status: number,
    fn: () => Promise<T>,
  ): Promise<{ status: number; body: T }> {
    if (!key || !UUID_RE.test(key)) {
      throw new ApiProblem(
        400,
        'IDEMPOTENCY_KEY_REQUIRED',
        'Idempotency-Key header (UUID) is required',
      );
    }
    const hash = createHash('sha256').update(canonical(body)).digest('hex');
    const client = await this.pool.connect();
    try {
      await client.query('SELECT pg_advisory_lock(hashtextextended($1, 0))', [
        `${userId}|${route}|${key}`,
      ]);
      try {
        const { rows } = await client.query(
          `SELECT request_hash, response_status, response_body FROM app.idempotency_keys
            WHERE user_id = $1 AND route = $2 AND key = $3 AND expires_at > now()`,
          [userId, route, key],
        );
        if (rows[0]) {
          if (rows[0].request_hash !== hash) {
            throw new ApiProblem(
              422,
              'IDEMPOTENCY_KEY_REUSED',
              'This Idempotency-Key was used with a different request',
            );
          }
          return { status: rows[0].response_status as number, body: rows[0].response_body as T };
        }
        const result = await fn();
        await client.query(
          `INSERT INTO app.idempotency_keys (user_id, route, key, request_hash, response_status, response_body)
           VALUES ($1,$2,$3,$4,$5,$6)
           ON CONFLICT (user_id, route, key) DO UPDATE
             SET request_hash = EXCLUDED.request_hash, response_status = EXCLUDED.response_status,
                 response_body = EXCLUDED.response_body, created_at = now(), expires_at = now() + interval '24 hours'`,
          [userId, route, key, hash, status, JSON.stringify(result)],
        );
        return { status, body: result };
      } finally {
        await client.query('SELECT pg_advisory_unlock(hashtextextended($1, 0))', [
          `${userId}|${route}|${key}`,
        ]);
      }
    } finally {
      client.release();
    }
  }
}
