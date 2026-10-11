import { Module } from '@nestjs/common';
import { APP_FILTER, APP_INTERCEPTOR } from '@nestjs/core';
import { AccountModule } from './account/account.module';
import { AuthModule } from './auth/auth.module';
import { RampModule } from './ramp/ramp.module';
import { ProblemFilter } from './common/problem';
import { HealthController } from './health.controller';
import { InvisibilityInterceptor } from './invisibility.interceptor';

@Module({
  imports: [AuthModule, RampModule, AccountModule],
  controllers: [HealthController],
  providers: [
    { provide: APP_INTERCEPTOR, useClass: InvisibilityInterceptor },
    { provide: APP_FILTER, useClass: ProblemFilter },
  ],
})
export class AppModule {}
