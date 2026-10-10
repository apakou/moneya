import { Module } from '@nestjs/common';
import { AUTH_CONFIG, loadAuthConfig } from './auth.config';
import { AuthController } from './auth.controller';
import { AuthGuard, TxnTokenGuard } from './auth.guard';
import { AuthService } from './auth.service';
import { AUTH_STORE } from './auth.store';
import { InMemoryAuthStore } from './in-memory-auth.store';
import { FakeSmsProvider, SMS_PROVIDER } from './sms.provider';

const prodGuard = (what: string): never => {
  throw new Error(
    `${what}: no production adapter yet — refusing to boot with the in-memory/fake one`,
  );
};

@Module({
  controllers: [AuthController],
  providers: [
    AuthService,
    AuthGuard,
    TxnTokenGuard,
    { provide: AUTH_CONFIG, useFactory: () => loadAuthConfig() },
    {
      provide: AUTH_STORE,
      useFactory: () =>
        process.env.NODE_ENV === 'production' ? prodGuard('AUTH_STORE') : new InMemoryAuthStore(),
    },
    FakeSmsProvider,
    {
      provide: SMS_PROVIDER,
      useFactory: (fake: FakeSmsProvider) =>
        process.env.NODE_ENV === 'production' ? prodGuard('SMS_PROVIDER') : fake,
      inject: [FakeSmsProvider],
    },
  ],
  exports: [AuthService, AuthGuard, TxnTokenGuard],
})
export class AuthModule {}
