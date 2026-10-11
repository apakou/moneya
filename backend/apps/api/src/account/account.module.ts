import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RampModule } from '../ramp/ramp.module';
import { AccountController } from './account.controller';
import { AccountService } from './account.service';

/** Read-side account endpoints: profile, balance and transaction history. */
@Module({
  imports: [AuthModule, RampModule],
  controllers: [AccountController],
  providers: [AccountService],
})
export class AccountModule {}
