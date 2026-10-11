import { Module } from '@nestjs/common';
import { AUTH_CONFIG, loadAuthConfig } from './auth.config';
import { AuthController } from './auth.controller';
import { AuthGuard, TxnTokenGuard } from './auth.guard';
import { AuthService } from './auth.service';
import { AUTH_STORE, type AuthStore } from './auth.store';
import { PgAuthStore } from './pg-auth.store';
import { InMemoryAuthStore } from './in-memory-auth.store';
import { createSmsProvider } from './sms.factory';
import { FakeSmsProvider, SMS_PROVIDER } from './sms.provider';

@Module({
  controllers: [AuthController],
  providers: [
    AuthService,
    AuthGuard,
    TxnTokenGuard,
    { provide: AUTH_CONFIG, useFactory: () => loadAuthConfig() },
    {
      provide: AUTH_STORE,
      useFactory: (): AuthStore => {
        if (process.env.DATABASE_URL) return PgAuthStore.fromUrl(process.env.DATABASE_URL);
        if (process.env.NODE_ENV === 'production')
          throw new Error('DATABASE_URL is required in production');
        return new InMemoryAuthStore(); // dev/test only
      },
    },
    FakeSmsProvider,
    {
      provide: SMS_PROVIDER,
      useFactory: (fake: FakeSmsProvider) => createSmsProvider(process.env, fake),
      inject: [FakeSmsProvider],
    },
  ],
  exports: [AuthService, AuthGuard, TxnTokenGuard, AUTH_STORE],
})
export class AuthModule {}
