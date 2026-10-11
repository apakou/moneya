import { Controller, Get, Query, Req, UseGuards } from '@nestjs/common';
import { AuthGuard, type AuthedRequest } from '../auth/auth.guard';
import { AuthService } from '../auth/auth.service';
import { WalletService } from './wallet.service';

@Controller('v1')
@UseGuards(AuthGuard)
export class WalletController {
  constructor(
    private readonly wallet: WalletService,
    private readonly auth: AuthService,
  ) {}

  @Get('users/me')
  me(@Req() req: AuthedRequest) {
    return this.auth.getUser(req.auth.userId);
  }

  @Get('wallet')
  getWallet(@Req() req: AuthedRequest) {
    return this.wallet.getWallet(req.auth.userId);
  }

  @Get('transfers')
  listTransfers(
    @Req() req: AuthedRequest,
    @Query('limit') limit?: string,
    @Query('cursor') cursor?: string,
    @Query('kind') kind?: string,
  ) {
    return this.wallet.listTransfers(req.auth.userId, { limit, cursor, kind });
  }
}
