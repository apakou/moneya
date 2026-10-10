import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import type { Request } from 'express';
import { AuthService, type AuthContext } from './auth.service';

export type AuthedRequest = Request & { auth: AuthContext };

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    req.auth = await this.auth.authenticate(req.headers.authorization);
    return true;
  }
}

/**
 * For money-moving endpoints (use after AuthGuard): consumes the single-use
 * X-Txn-Token minted by POST /v1/auth/step-up.
 */
@Injectable()
export class TxnTokenGuard implements CanActivate {
  constructor(private readonly auth: AuthService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const header = req.headers['x-txn-token'];
    await this.auth.consumeTxnToken(req.auth, typeof header === 'string' ? header : undefined);
    return true;
  }
}
