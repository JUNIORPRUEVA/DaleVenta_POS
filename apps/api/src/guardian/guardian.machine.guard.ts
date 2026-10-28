import {
  CanActivate,
  ExecutionContext,
  Injectable,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import { GuardianMachineIdentity, GuardianMachineService } from './guardian.machine.service';

/** Ventana de tolerancia del sello temporal anti-replay (segundos). */
export const GUARDIAN_MACHINE_MAX_SKEW_SECONDS = 300;
/** Límite de peticiones por credencial y minuto (protección de caudal). */
export const GUARDIAN_MACHINE_RATE_LIMIT_PER_MINUTE = 120;

type MachineRequest = {
  headers?: Record<string, string | string[] | undefined>;
  ip?: string;
  guardianMachine?: GuardianMachineIdentity;
};

function headerValue(request: MachineRequest, name: string): string {
  const raw = request?.headers?.[name];
  return (Array.isArray(raw) ? raw[0] : raw ?? '').trim();
}

/**
 * Guard de ingesta por credencial de máquina.
 *
 * Se registra solo en `GuardianMachineController`: no modifica ni debilita el
 * guard JWT del resto de la API.
 *
 * Reglas:
 * - Fail-closed: sin `x-guardian-key` no hay acceso.
 * - La clave nunca se registra en logs ni en la respuesta.
 * - Sello temporal opcional (`x-guardian-ts`) con ventana de ±5 min: mitiga la
 *   reutilización de una petición capturada sin necesidad de firmar el cuerpo.
 * - Límite de caudal en memoria por credencial, con mapa acotado.
 * - Un fallo de base de datos se responde 503 (nunca 401: no se confunde
 *   "no puedo verificar" con "credencial inválida").
 */
@Injectable()
export class GuardianMachineGuard implements CanActivate {
  private readonly logger = new Logger(GuardianMachineGuard.name);
  private readonly windowStart = new Map<string, { count: number; startedAt: number }>();

  constructor(private readonly machine: GuardianMachineService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<MachineRequest>();
    const rawKey = headerValue(request, 'x-guardian-key');

    if (!rawKey) {
      throw new UnauthorizedException({ code: 'MACHINE_KEY_REQUIRED' });
    }

    const rawTimestamp = headerValue(request, 'x-guardian-ts');
    if (rawTimestamp) {
      const parsed = Number(rawTimestamp);
      const seconds = Number.isFinite(parsed)
        ? parsed > 1e12
          ? Math.floor(parsed / 1000)
          : Math.floor(parsed)
        : NaN;
      const nowSeconds = Math.floor(Date.now() / 1000);
      if (!Number.isFinite(seconds) || Math.abs(nowSeconds - seconds) > GUARDIAN_MACHINE_MAX_SKEW_SECONDS) {
        throw new UnauthorizedException({ code: 'MACHINE_TIMESTAMP_OUT_OF_WINDOW' });
      }
    }

    let identity: GuardianMachineIdentity | null = null;
    try {
      identity = await this.machine.authenticate(rawKey);
    } catch (error) {
      this.logger.error(
        `No se pudo verificar la credencial de máquina: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      throw new ServiceUnavailableException({ code: 'MACHINE_AUTH_UNAVAILABLE' });
    }

    if (!identity) {
      throw new UnauthorizedException({ code: 'MACHINE_KEY_INVALID' });
    }

    this.assertRateLimit(identity.credentialId);
    request.guardianMachine = identity;
    return true;
  }

  private assertRateLimit(credentialId: string) {
    const now = Date.now();
    const entry = this.windowStart.get(credentialId);
    if (!entry || now - entry.startedAt >= 60_000) {
      this.windowStart.set(credentialId, { count: 1, startedAt: now });
      if (this.windowStart.size > 1_000) {
        for (const [key, value] of this.windowStart) {
          if (now - value.startedAt > 300_000) this.windowStart.delete(key);
        }
      }
      return;
    }
    entry.count += 1;
    if (entry.count > GUARDIAN_MACHINE_RATE_LIMIT_PER_MINUTE) {
      throw new UnauthorizedException({ code: 'MACHINE_RATE_LIMITED' });
    }
  }
}
