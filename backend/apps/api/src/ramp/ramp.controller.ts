import {
  Body,
  Controller,
  Get,
  Headers,
  HttpCode,
  Inject,
  Param,
  Post,
  RawBodyRequest,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { RampError, type RampProvider } from '@moneya/ramp';
import { ApiProblem } from '../common/problem';
import { IdempotencyService } from '../common/idempotency.service';
import { AuthGuard, type AuthedRequest } from '../auth/auth.guard';
import { AuthService } from '../auth/auth.service';
import { RAMP_PROVIDER, RampOrdersService } from './ramp-orders.service';
import { RampWebhookService } from './ramp-webhook.service';

const body = (b: unknown): Record<string, unknown> =>
  b && typeof b === 'object' ? (b as Record<string, unknown>) : {};
const uuid = (id: string): string => {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))
    throw new ApiProblem(404, 'NOT_FOUND', 'Not found');
  return id;
};

@Controller('v1')
export class RampController {
  constructor(
    private readonly orders: RampOrdersService,
    private readonly idem: IdempotencyService,
    private readonly auth: AuthService,
  ) {}

  @Post('onramp/quote')
  @HttpCode(200)
  @UseGuards(AuthGuard)
  quoteOnramp(@Req() req: AuthedRequest, @Body() b: unknown) {
    const x = body(b);
    return this.orders.quoteOnramp(req.auth.userId, x.fiat_currency, x.fiat_amount);
  }

  // The single-use step-up token is consumed INSIDE the idempotent section, so a client retrying
  // after a lost response gets the stored result back instead of a "token already used" error.
  @Post('onramp/orders')
  @UseGuards(AuthGuard)
  async createOnramp(
    @Req() req: AuthedRequest,
    @Res({ passthrough: true }) res: Response,
    @Body() b: unknown,
    @Headers('idempotency-key') key?: string,
    @Headers('x-txn-token') txn?: string,
  ) {
    const r = await this.idem.run(
      req.auth.userId,
      'POST /v1/onramp/orders',
      key,
      b,
      202,
      async () => {
        await this.auth.consumeTxnToken(req.auth, txn);
        return this.orders.createOnramp(req.auth.userId, body(b));
      },
    );
    res.status(r.status);
    return r.body;
  }

  @Get('onramp/orders/:id')
  @UseGuards(AuthGuard)
  getOnramp(@Req() req: AuthedRequest, @Param('id') id: string) {
    return this.orders.getOnramp(req.auth.userId, uuid(id));
  }

  @Post('offramp/quote')
  @HttpCode(200)
  @UseGuards(AuthGuard)
  quoteOfframp(@Req() req: AuthedRequest, @Body() b: unknown) {
    const x = body(b);
    return this.orders.quoteOfframp(req.auth.userId, x.amount, x.currency, x.payout_currency);
  }

  @Post('offramp/orders')
  @UseGuards(AuthGuard)
  async createOfframp(
    @Req() req: AuthedRequest,
    @Res({ passthrough: true }) res: Response,
    @Body() b: unknown,
    @Headers('idempotency-key') key?: string,
    @Headers('x-txn-token') txn?: string,
  ) {
    const r = await this.idem.run(
      req.auth.userId,
      'POST /v1/offramp/orders',
      key,
      b,
      202,
      async () => {
        await this.auth.consumeTxnToken(req.auth, txn);
        return this.orders.createOfframp(req.auth.userId, body(b));
      },
    );
    res.status(r.status);
    return r.body;
  }

  @Get('offramp/orders/:id')
  @UseGuards(AuthGuard)
  getOfframp(@Req() req: AuthedRequest, @Param('id') id: string) {
    return this.orders.getOfframp(req.auth.userId, uuid(id));
  }
}

@Controller('webhooks')
export class RampWebhookController {
  constructor(
    @Inject(RAMP_PROVIDER) private readonly provider: RampProvider,
    private readonly webhooks: RampWebhookService,
  ) {}

  @Post('ramp')
  @HttpCode(200)
  async receive(
    @Req() req: RawBodyRequest<Request>,
    @Headers() headers: Record<string, string | undefined>,
  ) {
    const raw = req.rawBody?.toString('utf8');
    if (!raw) throw new ApiProblem(400, 'BAD_REQUEST', 'Empty body');
    let event;
    try {
      event = this.provider.parseWebhook(headers, raw);
    } catch (e) {
      if (e instanceof RampError && e.code === 'INVALID_SIGNATURE')
        throw new ApiProblem(400, 'INVALID_SIGNATURE', 'Invalid signature');
      throw e;
    }
    await this.webhooks.process(this.provider.name, event, raw);
    return {};
  }
}
