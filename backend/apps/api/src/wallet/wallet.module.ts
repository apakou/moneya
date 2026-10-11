import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RampModule } from '../ramp/ramp.module';
import { WalletController } from './wallet.controller';
import { WalletService } from './wallet.service';

@Module({
  imports: [AuthModule, RampModule],
  controllers: [WalletController],
  providers: [WalletService],
})
export class WalletModule {}
