import { Controller, Get } from '@nestjs/common';

@Controller()
export class HealthController {
  /** Liveness probe (FND smoke-test endpoint). Carries no chain or provider detail. */
  @Get('health')
  health(): { status: 'ok' } {
    return { status: 'ok' };
  }
}
