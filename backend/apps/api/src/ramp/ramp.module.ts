import { Module } from '@nestjs/common';
import { SimulatedRampProvider, type RampProvider } from '@moneya/ramp';
import { randomBytes } from 'node:crypto';

export const RAMP_PROVIDER = Symbol('RAMP_PROVIDER');

/**
 * RAMP_PROVIDER=simulated (default outside production). A real adapter
 * (decision D2, pending RMP-00) plugs in here and must pass the contract suite
 * in packages/ramp/test/contract.ts. The simulator is refused in production.
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

@Module({
  providers: [{ provide: RAMP_PROVIDER, useFactory: () => createRampProvider() }],
  exports: [RAMP_PROVIDER],
})
export class RampModule {}
