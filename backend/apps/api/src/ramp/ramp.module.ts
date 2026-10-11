import { Inject, Injectable, Logger, Module, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { LedgerService } from '@moneya/ledger';
import { SimulatedRampProvider, type RampProvider } from '@moneya/ramp';
import { randomBytes } from 'node:crypto';
import type { Pool } from 'pg';
import { createPool } from '../common/db';
import { AuthModule } from '../auth/auth.module';
import { IDEMPOTENCY_POOL, IdempotencyService } from '../common/idempotency.service';
import { RampController, RampWebhookController } from './ramp.controller';
import { RampWebhookService } from './ramp-webhook.service';
import { loadPricing } from './pricing';
import {
  RAMP_POOL,
  RAMP_PRICING,
  RAMP_PROVIDER,
  RAMP_SETTLEMENT,
  RampOrdersService,
  type SettlementPort,
} from './ramp-orders.service';

/**
 * RAMP_PROVIDER=simulated (default outside production). A real adapter (decision D2,
 * pending RMP-00) plugs in here and must pass the contract suite in
 * packages/ramp/test/contract.ts. The simulator is refused in production.
 */
export function createRampProvider(env: NodeJS.ProcessEnv = process.env): RampProvider {
  const kind = env.RAMP_PROVIDER ?? (env.NODE_ENV === 'production' ? '' : 'simulated');
  if (kind === 'simulated') {
    if (env.NODE_ENV === 'production')
      throw new Error('RAMP_PROVIDER=simulated is not allowed in production');
    return new SimulatedRampProvider({
      webhookSecret: env.RAMP_WEBHOOK_SECRET ?? randomBytes(32).toString('hex'),
    });
  }
  throw new Error('RAMP_PROVIDER must be "simulated" (no real adapter exists yet)');
}

/** Dev/staging only: treats the treasury as paid as soon as the collection succeeds. */
export class SimulatedSettlement implements SettlementPort {
  confirm(order: { expectedAmount: string }): Promise<string | null> {
    return Promise.resolve(order.expectedAmount);
  }
}

/** Closes the shared pool on shutdown so the process (and test runs) can exit cleanly. */
@Injectable()
export class RampPoolLifecycle implements OnModuleDestroy {
  constructor(@Inject(RAMP_POOL) private readonly pool: Pool) {}
  async onModuleDestroy(): Promise<void> {
    await this.pool.end();
  }
}

/**
 * Polls the provider for orders whose webhook never arrived (and, with the simulated provider,
 * for every order: it sends no webhooks). Opt-in via RAMP_RESUMER_INTERVAL_MS (>= 1000);
 * syncPending is idempotent, so several instances running it is safe.
 */
@Injectable()
export class RampResumer implements OnModuleInit, OnModuleDestroy {
  private readonly log = new Logger(RampResumer.name);
  private timer?: NodeJS.Timeout;
  constructor(private readonly orders: RampOrdersService) {}

  onModuleInit(): void {
    const ms = Number(process.env.RAMP_RESUMER_INTERVAL_MS ?? 0);
    if (!Number.isInteger(ms) || ms < 1000) return;
    let running = false;
    this.timer = setInterval(() => {
      if (running) return;
      running = true;
      this.orders
        .syncPending()
        .catch((e: unknown) => this.log.warn(`resumer failed: ${String(e)}`))
        .finally(() => {
          running = false;
        });
    }, ms);
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }
}

@Module({
  imports: [AuthModule],
  controllers: [RampController, RampWebhookController],
  providers: [
    {
      provide: RAMP_POOL,
      useFactory: () => {
        if (!process.env.DATABASE_URL && process.env.NODE_ENV === 'production') {
          throw new Error('DATABASE_URL is required in production');
        }
        return createPool(); // connects lazily
      },
    },
    { provide: RAMP_PROVIDER, useFactory: () => createRampProvider() },
    { provide: RAMP_PRICING, useFactory: () => loadPricing() },
    {
      provide: RAMP_SETTLEMENT,
      // Production gets the real matcher (STL-05); until then top-ups cannot complete there.
      useFactory: () => (process.env.NODE_ENV === 'production' ? null : new SimulatedSettlement()),
    },
    {
      provide: LedgerService,
      useFactory: (pool: Pool) => new LedgerService(pool),
      inject: [RAMP_POOL],
    },
    { provide: IDEMPOTENCY_POOL, useExisting: RAMP_POOL },
    IdempotencyService,
    RampPoolLifecycle,
    RampWebhookService,
    RampOrdersService,
    RampResumer,
  ],
  exports: [RampOrdersService, RAMP_PROVIDER, RAMP_POOL, RAMP_PRICING, LedgerService],
})
export class RampModule {}
