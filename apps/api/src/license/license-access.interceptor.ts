import {
  CallHandler,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { isAllowedWhileRestricted } from './license.access.policy';

type RestrictedRequest = {
  method?: string;
  path?: string;
  url?: string;
  user?: {
    licenseAccess?: {
      level?: string;
      reason?: string;
      daysRemaining?: number | null;
    };
  };
};

/**
 * Con la licencia vencida o la cuenta suspendida el cliente **entra**, pero
 * solo puede usar Planes y Soporte. Este interceptor es la puerta: se ejecuta
 * despues de la autenticacion (por eso es interceptor y no guard) y falla
 * cerrado con cualquier ruta que no este en la lista blanca.
 *
 * Las dos situaciones usan la **misma** lista: ver el estado, pagar si debe
 * dinero y pedir ayuda. Asi la pantalla de cuenta suspendida puede pedir su
 * licencia y abrir el pago sin que el servidor la deje fuera.
 */
@Injectable()
export class LicenseAccessInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<RestrictedRequest>();
    const access = request.user?.licenseAccess;
    const level = (access?.level ?? '').toUpperCase();
    if (level !== 'RESTRICTED' && level !== 'BLOCKED') {
      return next.handle();
    }
    const method = request.method ?? 'GET';
    const path = request.path ?? request.url ?? '';
    if (isAllowedWhileRestricted(method, path)) {
      return next.handle();
    }
    const suspended = level === 'BLOCKED';
    throw new ForbiddenException({
      code: suspended ? 'LICENSE_SUSPENDED' : 'LICENSE_RESTRICTED',
      message: suspended
        ? 'Tu cuenta esta suspendida. Puedes revisar el estado en Planes y hablar con soporte; el resto de la app queda en pausa.'
        : 'Tu licencia vencio. Puedes renovarla desde Planes; mientras tanto solo Planes y Soporte estan disponibles.',
      reason: access?.reason ?? (suspended ? 'BLOCKED' : 'EXPIRED'),
      daysRemaining: access?.daysRemaining ?? null,
    });
  }
}
