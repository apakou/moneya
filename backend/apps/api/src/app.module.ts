import { Module } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { HealthController } from './health.controller';
import { InvisibilityInterceptor } from './invisibility.interceptor';

@Module({
  controllers: [HealthController],
  providers: [{ provide: APP_INTERCEPTOR, useClass: InvisibilityInterceptor }],
})
export class AppModule {}
