import { Module } from '@nestjs/common';
import { APP_FILTER, APP_INTERCEPTOR } from '@nestjs/core';
import { AuthModule } from './auth/auth.module';
import { ProblemFilter } from './common/problem';
import { HealthController } from './health.controller';
import { InvisibilityInterceptor } from './invisibility.interceptor';

@Module({
  imports: [AuthModule],
  controllers: [HealthController],
  providers: [
    { provide: APP_INTERCEPTOR, useClass: InvisibilityInterceptor },
    { provide: APP_FILTER, useClass: ProblemFilter },
  ],
})
export class AppModule {}
