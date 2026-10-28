import { Injectable, Logger } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';

/**
 * Autenticación de máquina (servidor a servidor) para la ingesta de telemetría.
 *
 * Modelo de seguridad:
 * - La instalación de DaleVentas POS recibe una clave de alta entropía con el
 *   prefijo `gmk_`. Nunca es un JWT de usuario: no caduca con la sesión de una
 *   persona y no puede usarse contra el resto de la API.
 * - Solo se persiste su SHA-256. Una fuga de la base de datos no revela claves.
 * - La empresa se resuelve **por la credencial**, jamás por el cuerpo de la
 *   petición: es el mecanismo que garantiza el aislamiento multiempresa.
 * - Fail-closed: sin coincidencia, credencial deshabilitada, revocada o caducada
 *   la respuesta es `null` y el controlador responde 401.
 */
export const GUARDIAN_MACHINE_KEY_PREFIX = 'gmk_';
const MIN_KEY_LENGTH = 24;
const MAX_KEY_LENGTH = 200;

export type GuardianMachineIdentity = {
  credentialId: string;
  companyId: string;
  installId: string | null;
  label: string;
};

/** SHA-256 hexadecimal: única forma en que una clave existe en la base de datos. */
export function hashGuardianMachineKey(rawKey: string): string {
  return createHash('sha256').update(String(rawKey ?? '').trim(), 'utf8').digest('hex');
}

/**
 * Prefijo público de la clave (para identificar la credencial en soporte sin
 * exponerla). Se muestra tal cual y no permite reconstruir el secreto.
 */
export function guardianMachineKeyPrefix(rawKey: string): string {
  return String(rawKey ?? '')
    .trim()
    .slice(0, 12);
}

export function isWellFormedGuardianMachineKey(rawKey: string): boolean {
  const value = String(rawKey ?? '').trim();
  if (value.length < MIN_KEY_LENGTH || value.length > MAX_KEY_LENGTH) return false;
  if (!value.startsWith(GUARDIAN_MACHINE_KEY_PREFIX)) return false;
  return /^[A-Za-z0-9_-]+$/.test(value);
}

@Injectable()
export class GuardianMachineService {
  private readonly logger = new Logger(GuardianMachineService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Resuelve la identidad asociada a una clave. NUNCA registra la clave ni su
   * hash completo; solo el id de la credencial cuando la autenticación prospera.
   */
  async authenticate(rawKey: string, now: Date = new Date()): Promise<GuardianMachineIdentity | null> {
    const key = String(rawKey ?? '').trim();
    if (!isWellFormedGuardianMachineKey(key)) return null;

    const keyHash = hashGuardianMachineKey(key);
    const credential = await this.prisma.guardianMachineCredential.findUnique({
      where: { keyHash },
      select: {
        id: true,
        companyId: true,
        installId: true,
        label: true,
        enabled: true,
        revokedAt: true,
        expiresAt: true,
      },
    });

    if (!credential) return null;
    if (!credential.enabled) return null;
    if (credential.revokedAt) return null;
    if (credential.expiresAt && credential.expiresAt.getTime() <= now.getTime()) return null;

    return {
      credentialId: credential.id,
      companyId: credential.companyId,
      installId: credential.installId ?? null,
      label: credential.label,
    };
  }

  /**
   * Marca la credencial como usada y deja rastro de auditoría.
   * Best-effort: un fallo aquí no puede invalidar una ingesta ya autorizada.
   */
  async recordUsage(params: {
    identity: GuardianMachineIdentity;
    ip?: string | null;
    requestId?: string | null;
    acceptedEvents: number;
    totalEvents: number;
  }): Promise<void> {
    try {
      await Promise.all([
        this.prisma.guardianMachineCredential.update({
          where: { id: params.identity.credentialId },
          data: { lastUsedAt: new Date() },
        }),
        this.prisma.guardianAccessLog.create({
          data: {
            actorUserId: null,
            actorRole: 'MACHINE',
            action: 'MACHINE_INGEST',
            incidentId: null,
            companyId: params.identity.companyId,
            ip: (params.ip ?? '').slice(0, 64) || null,
            requestId: (params.requestId ?? '').slice(0, 128) || null,
          },
        }),
      ]);
    } catch (error) {
      this.logger.warn(
        `No se pudo auditar el uso de la credencial ${params.identity.credentialId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}
