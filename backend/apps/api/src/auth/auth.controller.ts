import { Body, Controller, Headers, HttpCode, Post, Req, UseGuards } from '@nestjs/common';
import { AuthGuard, type AuthedRequest } from './auth.guard';
import { AuthService } from './auth.service';

@Controller('v1/auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('otp')
  @HttpCode(202)
  requestOtp(@Body() body: unknown, @Headers('accept-language') lang?: string) {
    return this.auth.requestOtp(body, /^en/i.test(lang ?? '') ? 'en' : 'fr');
  }

  @Post('otp/verify')
  @HttpCode(200)
  verifyOtp(@Body() body: unknown) {
    return this.auth.verifyOtp(body);
  }

  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() body: unknown) {
    return this.auth.refresh(body);
  }

  @Post('passcode')
  @HttpCode(204)
  @UseGuards(AuthGuard)
  async setPasscode(@Req() req: AuthedRequest, @Body() body: unknown): Promise<void> {
    await this.auth.setPasscode(req.auth, body);
  }

  @Post('step-up')
  @HttpCode(200)
  @UseGuards(AuthGuard)
  stepUp(@Req() req: AuthedRequest, @Body() body: unknown) {
    return this.auth.stepUp(req.auth, body);
  }
}
