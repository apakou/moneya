import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { Response } from 'express';

/** RFC 7807 problem, matching `components.schemas.Problem` in openapi.yaml. */
export class ApiProblem extends HttpException {
  constructor(
    status: number,
    readonly code: string,
    title: string,
    readonly extra: { detail?: string; retryAfterSeconds?: number } = {},
  ) {
    super(title, status);
  }
}

@Catch()
export class ProblemFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();
    const trace_id = randomUUID();
    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code = 'INTERNAL_ERROR';
    let title = 'Something went wrong';
    let detail: string | undefined;

    if (exception instanceof ApiProblem) {
      status = exception.getStatus();
      code = exception.code;
      title = exception.message;
      detail = exception.extra.detail;
      if (exception.extra.retryAfterSeconds !== undefined) {
        res.setHeader('Retry-After', String(exception.extra.retryAfterSeconds));
      }
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      code = status === 404 ? 'NOT_FOUND' : status === 401 ? 'UNAUTHORIZED' : 'BAD_REQUEST';
      title = exception.message;
    }
    // Never echo raw error text for 5xx (it could carry provider/SDK detail).
    if (status >= 500) title = 'Something went wrong';

    res
      .status(status)
      .type('application/problem+json')
      .json({
        type: `https://api.moneya.app/problems/${code.toLowerCase()}`,
        title,
        status,
        detail,
        code,
        trace_id,
      });
  }
}
