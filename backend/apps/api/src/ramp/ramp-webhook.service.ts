import { Inject, Injectable } from '@nestjs/common';
import type { RampEvent } from '@moneya/ramp';
import type { Pool } from 'pg';
import { RAMP_POOL, RampOrdersService } from './ramp-orders.service';

/**
 * Records every verified event in audit.webhook_events (dedupe key: provider + eventId) and applies it
 * once. A duplicate of an already-applied event is acknowledged without effect; an event that was
 * recorded but failed to apply is retried on the next delivery. Applying is itself idempotent
 * (journal ids derive from the order id; status transitions are guarded).
 */
@Injectable()
export class RampWebhookService {
  constructor(
    @Inject(RAMP_POOL) private readonly pool: Pool,
    private readonly orders: RampOrdersService,
  ) {}

  async process(provider: string, event: RampEvent, rawPayload: string): Promise<void> {
    const { rows } = await this.pool.query<{ id: string; processed_at: Date | null }>(
      `INSERT INTO audit.webhook_events (provider, event_id, event_type, raw_payload, signature_ok)
       VALUES ($1, $2, $3, $4::jsonb, true)
       ON CONFLICT (provider, event_id) DO UPDATE SET provider = EXCLUDED.provider
       RETURNING id, processed_at`,
      [provider.toUpperCase(), event.eventId, `${event.kind}.${event.status}`, rawPayload],
    );
    const row = rows[0]!;
    if (row.processed_at) return;
    try {
      if (event.kind === 'COLLECTION') await this.orders.handleCollectionEvent(event);
      else await this.orders.handlePayoutEvent(event);
      await this.pool.query(
        'UPDATE audit.webhook_events SET processed_at = now(), error = NULL WHERE id = $1',
        [row.id],
      );
    } catch (err) {
      await this.pool.query('UPDATE audit.webhook_events SET error = $2 WHERE id = $1', [
        row.id,
        String((err as Error).message).slice(0, 200),
      ]);
      throw err; // 5xx → the provider retries
    }
  }
}
