import {
  CanActivate,
  ExecutionContext,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { createHash, timingSafeEqual } from 'node:crypto';
import { guardianSecretValue } from './guardian.secret';

/**
 * Autenticación de plataforma para el panel Appyra.
 *
 * - Solo acepta el token configurado en `GUARDIAN_PLATFORM_TOKEN`.
 * - Fail-closed: si el token no está configurado, el endpoint no existe (503).
 * - Comparación en tiempo constante y por digest, para no filtrar longitud ni
 *   contenido por temporización.
 * - Nunca registra el token recibido.
 */
@Injectable()
export class GuardianPlatformGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const expected = guardianSecretValue(process.env, 'GUARDIAN_PLATFORM_TOKEN');
    if (!expected) {
      throw new ServiceUnavailableException({
        code: 'GUARDIAN_PLATFORM_DISABLED',
        message: 'El acceso de plataforma no está configurado',
      });
    }

    const request = context.switchToHttp().getRequest<{
      headers?: Record<string, string | string[] | undefined>;
    }>();
    const raw = request?.headers?.['x-guardian-platform-token'];
    const provided = (Array.isArray(raw) ? raw[0] : raw ?? '').trim();

    if (!provided) {
      throw new UnauthorizedException({ code: 'PLATFORM_TOKEN_REQUIRED' });
    }

    const digest = (value: string) => createHash('sha256').update(value).digest();
    const matches =
      digest(provided).length === digest(expected).length &&
      timingSafeEqual(digest(provided), digest(expected));

    if (!matches) {
      throw new UnauthorizedException({ code: 'PLATFORM_TOKEN_INVALID' });
    }

    return true;
  }
}
