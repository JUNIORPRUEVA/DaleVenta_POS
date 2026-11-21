import { CallHandler, ExecutionContext, Injectable, Logger, NestInterceptor } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { Observable, tap } from 'rxjs';
import { CatalogRealtimeRelayService } from './catalog-realtime-relay.service';

@Injectable()
export class ProductLifecycleRealtimeInterceptor implements NestInterceptor {
  private readonly logger = new Logger(ProductLifecycleRealtimeInterceptor.name);
  constructor(private readonly realtime: CatalogRealtimeRelayService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const action = context.getHandler().name;
    if (!['create', 'update', 'remove', 'archive', 'reactivate', 'annul', 'adjustStock'].includes(action)) return next.handle();
    const request = context.switchToHttp().getRequest();
    const companyId = request.user?.companyId;
    return next.handle().pipe(tap((result: any) => {
      const productId = request.params?.id ?? result?.product?.id ?? result?.id;
      if (!companyId || !productId) return;
      // A committed mutation remains successful if notification delivery fails.
      // Only identifiers leave this channel; prices/costs require authorized GET.
      try {
        this.realtime.emitCompany(companyId, 'product.changed', {
          eventId: randomUUID(), companyId, productId, action,
        });
      } catch (error) {
        this.logger.warn(`Product notification failed after ${action}`);
      }
    }));
  }
}
