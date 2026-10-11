import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import {
  RampError,
  validateRequest,
  type RampEvent,
  type RampFailureReason,
  type RampOperation,
  type RampProvider,
  type RampRequest,
  type RampStatus,
} from './types';

interface Stored {
  kind: 'COLLECTION' | 'PAYOUT';
  req: RampRequest;
  op: RampOperation;
}

export interface SimulatedRampOptions {
  /** HMAC secret for webhooks. */
  webhookSecret: string;
  /**
   * true (default): an operation resolves on first `getOperation` according to the
   * phone's magic suffix. false: stays PENDING until `resolve()`.
   */
  autoSettle?: boolean;
  now?: () => Date;
}

/**
 * Deterministic stand-in for a real provider, for local dev, staging and tests.
 * Magic phone suffixes (last 4 digits):
 *   0000 → FAILED PROVIDER_REJECTED    1111 → stays PENDING    2222 → FAILED INSUFFICIENT_FUNDS
 *   anything else → SUCCEEDED
 * Never use in production (the API module refuses to).
 */
export class SimulatedRampProvider implements RampProvider {
  readonly name = 'simulated';
  private readonly ops = new Map<string, Stored>();
  private readonly byOrder = new Map<string, string>();
  private readonly autoSettle: boolean;
  private readonly now: () => Date;

  constructor(private readonly opts: SimulatedRampOptions) {
    this.autoSettle = opts.autoSettle ?? true;
    this.now = opts.now ?? (() => new Date());
  }

  async createCollection(req: RampRequest): Promise<RampOperation> {
    return this.create('COLLECTION', req);
  }

  async createPayout(req: RampRequest): Promise<RampOperation> {
    return this.create('PAYOUT', req);
  }

  private create(kind: Stored['kind'], req: RampRequest): Promise<RampOperation> {
    validateRequest(req);
    const key = `${kind}:${req.orderId}`;
    const existing = this.byOrder.get(key);
    if (existing) {
      const s = this.ops.get(existing)!;
      if (
        s.req.amount !== req.amount ||
        s.req.currency !== req.currency ||
        s.req.phone !== req.phone
      ) {
        return Promise.reject(
          new RampError('INVALID_REQUEST', 'orderId reused with different parameters'),
        );
      }
      return Promise.resolve({ ...s.op });
    }
    const providerRef = `sim_${randomUUID()}`;
    const op: RampOperation = { providerRef, status: 'PENDING' };
    if (kind === 'COLLECTION')
      op.userAction = { type: 'USSD_PROMPT', value: 'Approve the payment on your phone' };
    this.ops.set(providerRef, { kind, req, op });
    this.byOrder.set(key, providerRef);
    return Promise.resolve({ ...op });
  }

  async getOperation(providerRef: string): Promise<RampOperation> {
    const s = this.ops.get(providerRef);
    if (!s) return Promise.reject(new RampError('NOT_FOUND', 'Unknown operation'));
    if (this.autoSettle && s.op.status === 'PENDING') this.apply(s, this.outcomeFor(s.req.phone));
    return Promise.resolve({ ...s.op });
  }

  /** Test/staging hook: settle a pending operation and get the signed webhook a real provider would send. */
  resolve(
    providerRef: string,
    status: Exclude<RampStatus, 'PENDING'>,
    failureReason?: RampFailureReason,
  ) {
    const s = this.ops.get(providerRef);
    if (!s) throw new RampError('NOT_FOUND', 'Unknown operation');
    this.apply(s, { status, failureReason });
    return this.signedWebhook(s);
  }

  /** The webhook for an operation's current state (used to test the receiving side). */
  signedWebhook(s: Stored | string) {
    const st = typeof s === 'string' ? this.ops.get(s) : s;
    if (!st) throw new RampError('NOT_FOUND', 'Unknown operation');
    const event: RampEvent = {
      eventId: `evt_${randomUUID()}`,
      kind: st.kind,
      providerRef: st.op.providerRef,
      orderId: st.req.orderId,
      status: st.op.status,
      failureReason: st.op.failureReason,
    };
    const body = JSON.stringify(event);
    const ts = String(Math.floor(this.now().getTime() / 1000));
    return { body, headers: { 'x-ramp-timestamp': ts, 'x-ramp-signature': this.sign(ts, body) } };
  }

  parseWebhook(headers: Record<string, string | undefined>, rawBody: string): RampEvent {
    const ts = headers['x-ramp-timestamp'];
    const sig = headers['x-ramp-signature'];
    if (!ts || !sig || !/^[0-9]+$/.test(ts))
      throw new RampError('INVALID_SIGNATURE', 'Missing signature');
    if (Math.abs(this.now().getTime() / 1000 - Number(ts)) > 300)
      throw new RampError('INVALID_SIGNATURE', 'Stale timestamp');
    const expected = Buffer.from(this.sign(ts, rawBody), 'hex');
    const given = Buffer.from(sig, 'hex');
    if (expected.length !== given.length || !timingSafeEqual(expected, given)) {
      throw new RampError('INVALID_SIGNATURE', 'Bad signature');
    }
    return JSON.parse(rawBody) as RampEvent;
  }

  private sign(ts: string, body: string): string {
    return createHmac('sha256', this.opts.webhookSecret).update(`${ts}.${body}`).digest('hex');
  }

  private outcomeFor(phone: string): { status: RampStatus; failureReason?: RampFailureReason } {
    const tail = phone.slice(-4);
    if (tail === '0000') return { status: 'FAILED', failureReason: 'PROVIDER_REJECTED' };
    if (tail === '2222') return { status: 'FAILED', failureReason: 'INSUFFICIENT_FUNDS' };
    if (tail === '1111') return { status: 'PENDING' };
    return { status: 'SUCCEEDED' };
  }

  private apply(s: Stored, o: { status: RampStatus; failureReason?: RampFailureReason }): void {
    if (s.op.status !== 'PENDING') return; // terminal states never change
    s.op.status = o.status;
    if (o.failureReason) s.op.failureReason = o.failureReason;
    if (o.status !== 'PENDING') delete s.op.userAction;
  }
}
