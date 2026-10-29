import { Injectable, Logger } from '@nestjs/common';
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import {
  GUARDIAN_COMPANY_DISABLED,
  isGuardianEnabledForCompany,
} from './guardian.company.policy';

/**
 * Enrolamiento de instalaciones (POS de escritorio y móvil).
 *
 * Problema que resuelve: el agente Flutter necesita enviar incidentes **antes**
 * de que exista una sesión de usuario (fallos de arranque, actualizador,
 * errores de SQLite local). No se puede incrustar un secreto compartido en un
 * instalador, y un JWT de usuario no es una credencial de máquina.
 *
 * Flujo:
 * 1. Un operador de plataforma genera un código de un solo uso para una empresa
 *    (`guardian_enrollment_codes`), con caducidad corta.
 * 2. La instalación llama a `POST /guardian/installations/enroll` con ese código
 *    y su `installId`.
 * 3. El servidor crea (o rota) una credencial de máquina ligada a esa empresa y
 *    a esa instalación, con caducidad propia, y devuelve la clave **una vez**.
 * 4. La app la guarda en almacenamiento seguro y la usa contra
 *    `/guardian/machine/incidents`.
 *
 * Garantías:
 * - El código y la clave solo se almacenan como SHA-256.
 * - Uso acotado y atómico (no se puede canjear dos veces en carrera).
 * - Caducidad y revocación independientes para código y credencial.
 * - La empresa se resuelve por el código, nunca por la petición.
 */

export const GUARDIAN_ENROLLMENT_CODE_PREFIX = 'genr_';
const MIN_CODE_LENGTH = 24;
const MAX_CODE_LENGTH = 200;

/** Días de validez de la credencial de instalación (configurable). */
export const DEFAULT_INSTALL_CREDENTIAL_DAYS = 30;

export type GuardianEnrollmentOutcome =
  | {
      ok: true;
      installId: string;
      companyId: string;
      credential: string;
      expiresAt: string;
    }
  | { ok: false; code: string; message: string };

export function hashGuardianEnrollmentCode(raw: string): string {
  return createHash('sha256').update(String(raw ?? '').trim(), 'utf8').digest('hex');
}

export function isWellFormedEnrollmentCode(raw: string): boolean {
  const value = String(raw ?? '').trim();
  if (value.length < MIN_CODE_LENGTH || value.length > MAX_CODE_LENGTH) return false;
  if (!value.startsWith(GUARDIAN_ENROLLMENT_CODE_PREFIX)) return false;
  return /^[A-Za-z0-9_-]+$/.test(value);
}

export function generateEnrollmentCode(): string {
  return `${GUARDIAN_ENROLLMENT_CODE_PREFIX}${randomBytes(24).toString('hex')}`;
}

/** Clave de instalación emitida al enrolar: prefijo `gmk_` (misma que la de máquina). */
export function generateInstallCredential(): string {
  return `gmk_${randomBytes(24).toString('hex')}`;
}

export function installCredentialDays(env: NodeJS.ProcessEnv = process.env): number {
  const parsed = Number.parseInt(String(env.GUARDIAN_INSTALL_CREDENTIAL_DAYS ?? '').trim(), 10);
  if (!Number.isFinite(parsed)) return DEFAULT_INSTALL_CREDENTIAL_DAYS;
  return Math.min(365, Math.max(1, parsed));
}

const INSTALL_ID_PATTERN = /^[A-Za-z0-9._:-]{6,120}$/;

@Injectable()
export class GuardianEnrollmentService {
  private readonly logger = new Logger(GuardianEnrollmentService.name);
  private readonly attempts = new Map<string, { startedAt: number; count: number }>();

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Canjea un código por una credencial de instalación.
   * Nunca devuelve detalles internos en el mensaje de error.
   */
  async enroll(params: {
    code: string;
    installId: string;
    platform?: string | null;
    appVersion?: string | null;
    ip?: string | null;
  }): Promise<GuardianEnrollmentOutcome> {
    const rawCode = String(params.code ?? '').trim();
    const installId = String(params.installId ?? '').trim();

    if (!isWellFormedEnrollmentCode(rawCode)) {
      return { ok: false, code: 'ENROLLMENT_CODE_INVALID', message: 'Código de enrolamiento inválido' };
    }
    if (!INSTALL_ID_PATTERN.test(installId)) {
      return { ok: false, code: 'INSTALL_ID_INVALID', message: 'installId inválido' };
    }
    if (this.isRateLimited(rawCode)) {
      return { ok: false, code: 'ENROLLMENT_RATE_LIMITED', message: 'Demasiados intentos' };
    }

    const now = new Date();
    const codeHash = hashGuardianEnrollmentCode(rawCode);
    const record = await this.prisma.guardianEnrollmentCode.findUnique({
      where: { codeHash },
      select: { id: true, companyId: true, maxUses: true, uses: true, expiresAt: true, revokedAt: true },
    });

    if (!record) {
      return { ok: false, code: 'ENROLLMENT_CODE_INVALID', message: 'Código de enrolamiento inválido' };
    }

    // Fase 7 — el código pertenece a una empresa, pero la empresa debe tener
    // Guardian activado para que el canje prospere.
    if (!(await isGuardianEnabledForCompany(this.prisma, record.companyId))) {
      return {
        ok: false,
        code: GUARDIAN_COMPANY_DISABLED,
        message: 'La empresa no tiene APPYRA Guardian activado',
      };
    }
    if (record.revokedAt) {
      return { ok: false, code: 'ENROLLMENT_CODE_REVOKED', message: 'Código de enrolamiento revocado' };
    }
    if (record.expiresAt.getTime() <= now.getTime()) {
      return { ok: false, code: 'ENROLLMENT_CODE_EXPIRED', message: 'Código de enrolamiento caducado' };
    }
    if (record.uses >= record.maxUses) {
      return { ok: false, code: 'ENROLLMENT_CODE_EXHAUSTED', message: 'Código de enrolamiento ya utilizado' };
    }

    // Consumo atómico: dos instalaciones no pueden canjear el mismo uso.
    const consumed = await this.prisma.guardianEnrollmentCode.updateMany({
      where: { id: record.id, uses: { lt: record.maxUses } },
      data: { uses: { increment: 1 } },
    });
    if (consumed.count !== 1) {
      return { ok: false, code: 'ENROLLMENT_CODE_EXHAUSTED', message: 'Código de enrolamiento ya utilizado' };
    }

    const credential = generateInstallCredential();
    const keyHash = createHash('sha256').update(credential, 'utf8').digest('hex');
    const expiresAt = new Date(now.getTime() + installCredentialDays() * 24 * 60 * 60 * 1000);

    const existing = await this.prisma.guardianMachineCredential.findFirst({
      where: { companyId: record.companyId, installId },
      select: { id: true },
    });

    if (existing) {
      // Rotación: misma instalación, nueva clave y nueva caducidad.
      await this.prisma.guardianMachineCredential.update({
        where: { id: existing.id },
        data: {
          keyHash,
          keyPrefix: credential.slice(0, 12),
          enabled: true,
          revokedAt: null,
          expiresAt,
        },
      });
    } else {
      await this.prisma.guardianMachineCredential.create({
        data: {
          companyId: record.companyId,
          label: `Instalación ${installId}`.slice(0, 120),
          keyHash,
          keyPrefix: credential.slice(0, 12),
          installId,
          scopes: ['ingest:incidents'],
          enabled: true,
          expiresAt,
        },
      });
    }

    void this.audit({
      companyId: record.companyId,
      installId,
      ip: params.ip ?? null,
      platform: params.platform ?? null,
      codeId: record.id,
    });

    return {
      ok: true,
      installId,
      companyId: record.companyId,
      credential,
      expiresAt: expiresAt.toISOString(),
    };
  }

  /** Registro de auditoría del enrolamiento (best-effort, sin romper el flujo). */
  private async audit(params: {
    companyId: string;
    installId: string;
    ip: string | null;
    platform: string | null;
    codeId: string;
  }): Promise<void> {
    try {
      await this.prisma.guardianAccessLog.create({
        data: {
          actorUserId: null,
          actorRole: 'MACHINE',
          action: 'INSTALLATION_ENROLLED',
          companyId: params.companyId,
          ip: (params.ip ?? '').slice(0, 64) || null,
          requestId: `enroll:${params.codeId}`.slice(0, 128),
        },
      });
    } catch (error) {
      this.logger.warn(
        `No se pudo auditar el enrolamiento de ${params.installId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  /** Límite de intentos por código (mapa acotado, ventana de un minuto). */
  private isRateLimited(rawCode: string): boolean {
    const now = Date.now();
    const key = hashGuardianEnrollmentCode(rawCode).slice(0, 16);
    const entry = this.attempts.get(key);
    if (!entry || now - entry.startedAt >= 60_000) {
      this.attempts.set(key, { startedAt: now, count: 1 });
      if (this.attempts.size > 1_000) {
        for (const [k, v] of this.attempts) {
          if (now - v.startedAt > 300_000) this.attempts.delete(k);
        }
      }
      return false;
    }
    entry.count += 1;
    return entry.count > 10;
  }
}

/** Comparación en tiempo constante de dos códigos (uso defensivo). */
export function enrollmentCodeMatches(provided: string, expected: string): boolean {
  const a = Buffer.from(hashGuardianEnrollmentCode(provided), 'hex');
  const b = Buffer.from(hashGuardianEnrollmentCode(expected), 'hex');
  return a.length === b.length && timingSafeEqual(a, b);
}
