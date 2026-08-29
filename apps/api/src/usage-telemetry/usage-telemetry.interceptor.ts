import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable } from 'rxjs';
import { UsageTelemetryService } from './usage-telemetry.service';

@Injectable()
export class UsageTelemetryInterceptor implements NestInterceptor {
  constructor(private readonly telemetry: UsageTelemetryService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest();
    const path = request?.path || request?.url || '';
    if (!path.startsWith('/internal/usage-telemetry') && path !== '/health') {
      this.telemetry.recordRequestUsage(request);
    }
    return next.handle();
  }
}
