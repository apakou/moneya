import { Controller, Get, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard, type AuthedRequest } from '../auth/auth.guard';
import { AccountService } from './account.service';

@Controller('v1')
@UseGuards(AuthGuard)
export class AccountController {
  constructor(private readonly account: AccountService) {}

  @Get('users/me')
  me(@Req() req: AuthedRequest) {
    return this.account.me(req.auth.userId);
  }

  @Get('wallet')
  wallet(@Req() req: AuthedRequest, @Query('currency') currency?: string) {
    return this.account.wallet(req.auth.userId, currency);
  }

  @Get('transactions')
  transactions(
    @Req() req: AuthedRequest,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
  ) {
    return this.account.transactions(req.auth.userId, limit, cursor);
  }
}
