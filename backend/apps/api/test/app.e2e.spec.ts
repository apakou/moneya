import { Controller, Get, INestApplication } from '@nestjs/common';
import { APP_INTERCEPTOR } from '@nestjs/core';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { HealthController } from '../src/health.controller';
import { InvisibilityInterceptor } from '../src/invisibility.interceptor';

@Controller('probe')
class ProbeController {
  @Get('clean')
  clean() {
    return { amount: '5000', currency: 'XOF', status: 'COMPLETED' };
  }

  @Get('leaky')
  leaky() {
    return { amount: '8', currency: 'USDC' };
  }

  @Get('leaky-key')
  leakyKey() {
    return { solana_signature: 'abc' };
  }
}

describe('API', () => {
  let app: INestApplication;

  beforeAll(async () => {
    const mod = await Test.createTestingModule({
      imports: [AppModule],
      controllers: [ProbeController],
    }).compile();
    app = mod.createNestApplication({ logger: false });
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health is up and carries no detail', async () => {
    const res = await request(app.getHttpServer()).get('/health').expect(200);
    expect(res.body).toEqual({ status: 'ok' });
  });

  it('lets a fiat-only response through', async () => {
    await request(app.getHttpServer()).get('/probe/clean').expect(200);
  });

  it('blocks a response mentioning the settlement asset', async () => {
    await request(app.getHttpServer()).get('/probe/leaky').expect(500);
  });

  it('blocks a response with a chain-revealing key', async () => {
    await request(app.getHttpServer()).get('/probe/leaky-key').expect(500);
  });
});

describe('InvisibilityInterceptor in production', () => {
  it('is a no-op (checked by the CI e2e suite instead)', async () => {
    const prev = process.env.NODE_ENV;
    process.env.NODE_ENV = 'production';
    try {
      const mod = await Test.createTestingModule({
        controllers: [HealthController, ProbeController],
        providers: [{ provide: APP_INTERCEPTOR, useClass: InvisibilityInterceptor }],
      }).compile();
      const prod = mod.createNestApplication({ logger: false });
      await prod.init();
      await request(prod.getHttpServer()).get('/probe/leaky').expect(200);
      await prod.close();
    } finally {
      process.env.NODE_ENV = prev;
    }
  });
});
