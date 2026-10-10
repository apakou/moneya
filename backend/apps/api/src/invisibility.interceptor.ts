import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { assertNoLeaks } from '@moneya/invisibility';
import { Observable, tap } from 'rxjs';

/**
 * Plan §1.1 (INV-03): outside production, any response that reveals stablecoin /
 * chain details fails loudly (HTTP 500 + the offending JSON paths in the log) so
 * a leak is caught by tests and dev usage, never shipped silently.
 *
 * In production the same check is enforced by the e2e suite in CI; it is not run
 * per request to avoid a hot-path cost.
 */
@Injectable()
export class InvisibilityInterceptor implements NestInterceptor {
  intercept(_ctx: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (process.env.NODE_ENV === 'production') return next.handle();
    return next.handle().pipe(tap((body) => assertNoLeaks(body)));
  }
}
