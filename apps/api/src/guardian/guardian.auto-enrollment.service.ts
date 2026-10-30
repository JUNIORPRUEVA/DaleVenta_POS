import { Injectable, Logger } from '@nestjs/common';
import { createHash, randomBytes } from 'node:crypto';
import {
  GuardianAutoEnrollmentConfig,
  isCompanyAllowedForAutoEnrollment,
  isCompanyLicenseEligible,
  resolveGuardianAutoEnrollmentConfig,
} from './guardian.auto-enrollment.config';
import {
  GUARDIAN_COMPANY_DISABLED,
} from './guardian.company.policy';
import {
  GUARDIAN_ENROLLMENT_CODE_PREFIX,
  generateEnrollmentCode,
  hashGuardianEnrollmentCode,
} from './guardian.enrollment.service';

/**
 * Auto-enrolamiento de instalaciones para empresas **elegibles**.
 *
 * Problema que resuelve: exigir un código por empresa y por equipo hacía que la
 * cobertura real dependiera de una tarea manual. La instalación ya tiene una
 * sesión autenticada de la empresa, así que puede pedir su propia autorización
 * de enrolamiento.
 *
 * Diseño (sin secretos compartidos):
 * 1. La app, con JWT válido, llama a `POST /guardian/installations/enrollment-grant`.
 * 2. El servidor verifica empresa autorizada + licencia vigente + cuota de
 *    instalaciones + límite de concesiones, y devuelve un **código de un solo
 *    uso** de vida corta (misma tabla y misma semántica atómica que el flujo
 *    manual: `guardian_enrollment_codes`).
 * 3. La app canjea ese código en `POST /guardian/installations/enroll` y recibe
 *    una credencial **ligada a la instalación** (`installId`), con caducidad y
 *    revocación.
 *
 * Garantías:
 * - La empresa **nunca** viene de la petición: sale de la sesión autenticada y
 *   del código emitido para esa empresa.
 * - El código en claro no se almacena (solo SHA-256) ni se registra en logs.
 * - Todo el flujo queda auditado sin datos sensibles.
 */
export type GuardianAutoEnrollmentOutcome =
  | { ok: true; code: string; expiresAt: string; companyId: string; activated: boolean }
  | { ok: false; code: string; message: string };

const LABEL_PREFIX = 'auto:';
const INSTALL_ID_PATTERN = /^[A-Za-z0-9._:-]{6,120}$/;

/** Lector mínimo (permite pruebas sin Prisma real). */
export type GuardianAutoEnrollmentStore = {
  company: {
    findUnique(args: {
      where: { id: string };
      select: {
        guardianEnabled: true;
        status: true;
        licenseStatus: true;
        licenseBlockedAt: true;
        licenseExpiresAt: true;
      };
    }): Promise<{
      guardianEnabled: boolean;
      status: string;
      licenseStatus: string;
      licenseBlockedAt: Date | null;
      licenseExpiresAt: Date | null;
    } | null>;
    update(args: {
      where: { id: string };
      data: {
        guardianEnabled: boolean;
        guardianEnabledAt?: Date | null;
        guardianEnabledBy?: string | null;
      };
    }): Promise<unknown>;
  };
  guardianMachineCredential: {
    count(args: {
      where: {
        companyId: string;
        enabled: boolean;
        revokedAt: null;
        OR: Array<{ expiresAt: null } | { expiresAt: { gt: Date } }>;
      };
    }): Promise<number>;
    findFirst(args: {
      where: { companyId: string; installId: string };
      select: { id: true };
    }): Promise<{ id: string } | null>;
    updateMany(args: {
      where: { companyId: string; revokedAt: null };
      data: { enabled: boolean; revokedAt: Date };
    }): Promise<{ count: number }>;
  };
  guardianEnrollmentCode: {
    count(args: { where: { companyId: string; createdAt: { gte: Date } } }): Promise<number>;
    create(args: {
      data: {
        companyId: string;
        codeHash: string;
        codePrefix: string;
        label: string;
        maxUses: number;
        expiresAt: Date;
      };
    }): Promise<{ id: string; expiresAt: Date }>;
    updateMany(args: {
      where: { companyId: string; revokedAt: null; expiresAt: { gt: Date } };
      data: { revokedAt: Date };
    }): Promise<{ count: number }>;
  };
  guardianAccessLog: {
    create(args: {
      data: {
        actorUserId: string | null;
        actorRole: string | null;
        action: string;
        companyId: string;
        ip: string | null;
        requestId: string | null;
      };
    }): Promise<unknown>;
  };
};

@Injectable()
export class GuardianAutoEnrollmentService {
  private readonly logger = new Logger(GuardianAutoEnrollmentService.name);

  /** Límite en memoria por empresa (defensa contra ráfagas, complementa la BD). */
  private readonly bursts = new Map<string, { startedAt: number; count: number }>();

  constructor(private readonly prisma: GuardianAutoEnrollmentStore) {}

  /**
   * Emite una autorización de enrolamiento de vida corta para la empresa de la
   * sesión. Nunca crea credenciales: el canje sigue siendo el paso 2.
   */
  async requestGrant(params: {
    companyId: string;
    actorUserId: string | null;
    actorRole: string | null;
    installId: string;
    platform?: string | null;
    appVersion?: string | null;
    ip?: string | null;
  }): Promise<GuardianAutoEnrollmentOutcome> {
    const config = resolveGuardianAutoEnrollmentConfig();
    const companyId = String(params.companyId ?? '').trim();
    const installId = String(params.installId ?? '').trim();
    const now = new Date();

    if (!config.enabled) {
      return {
        ok: false,
        code: 'AUTO_ENROLLMENT_DISABLED',
        message: 'El auto-enrolamiento no está habilitado',
      };
    }
    if (!companyId) {
      return {
        ok: false,
        code: 'COMPANY_REQUIRED',
        message: 'La sesión no tiene una empresa activa',
      };
    }
    if (!isCompanyAllowedForAutoEnrollment(config, companyId)) {
      return {
        ok: false,
        code: 'COMPANY_NOT_ALLOWED',
        message: 'La empresa no está incluida en el despliegue de auto-enrolamiento',
      };
    }
    if (!INSTALL_ID_PATTERN.test(installId)) {
      return { ok: false, code: 'INSTALL_ID_INVALID', message: 'installId inválido' };
    }
    if (this.isBurstLimited(config, companyId, now)) {
      return {
        ok: false,
        code: 'ENROLLMENT_RATE_LIMITED',
        message: 'Demasiadas solicitudes de enrolamiento',
      };
    }

    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: {
        guardianEnabled: true,
        status: true,
        licenseStatus: true,
        licenseBlockedAt: true,
        licenseExpiresAt: true,
      },
    });
    if (!company) {
      return { ok: false, code: 'COMPANY_NOT_FOUND', message: 'Empresa no disponible' };
    }
    if (!isCompanyLicenseEligible(company, now)) {
      return {
        ok: false,
        code: 'COMPANY_NOT_ELIGIBLE',
        message: 'La empresa no tiene una licencia vigente',
      };
    }

    const existingForInstall = await this.prisma.guardianMachineCredential.findFirst({
      where: { companyId, installId },
      select: { id: true },
    });
    if (!existingForInstall) {
      const active = await this.prisma.guardianMachineCredential.count({
        where: {
          companyId,
          enabled: true,
          revokedAt: null,
          OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
        },
      });
      if (active >= config.maxInstallationsPerCompany) {
        return {
          ok: false,
          code: 'INSTALLATION_LIMIT_REACHED',
          message: 'La empresa alcanzó el máximo de instalaciones monitoreadas',
        };
      }
    }

    const recent = await this.prisma.guardianEnrollmentCode.count({
      where: { companyId, createdAt: { gte: new Date(now.getTime() - 60 * 60 * 1000) } },
    });
    if (recent >= config.grantsPerCompanyHour) {
      return {
        ok: false,
        code: 'ENROLLMENT_RATE_LIMITED',
        message: 'Demasiadas autorizaciones de enrolamiento en la última hora',
      };
    }

    // Activación por defecto: la empresa autorizada en el despliegue queda
    // instrumentada. Es reversible con el control administrativo.
    let activated = false;
    if (!company.guardianEnabled) {
      if (!config.activateOnGrant) {
        return {
          ok: false,
          code: GUARDIAN_COMPANY_DISABLED,
          message: 'La empresa no tiene APPYRA Guardian activado',
        };
      }
      await this.prisma.company.update({
        where: { id: companyId },
        data: {
          guardianEnabled: true,
          guardianEnabledAt: now,
          guardianEnabledBy: 'AUTO_ENROLLMENT',
        },
      });
      activated = true;
      await this.audit({
        companyId,
        actorUserId: params.actorUserId,
        actorRole: params.actorRole,
        action: 'COMPANY_AUTO_ACTIVATED',
        ip: params.ip ?? null,
      });
    }

    const code = generateEnrollmentCode();
    const expiresAt = new Date(now.getTime() + config.grantTtlSeconds * 1000);
    await this.prisma.guardianEnrollmentCode.create({
      data: {
        companyId,
        codeHash: hashGuardianEnrollmentCode(code),
        codePrefix: code.slice(0, 12),
        label: `${LABEL_PREFIX}${(params.platform ?? 'unknown').slice(0, 20)}`,
        maxUses: 1,
        expiresAt,
      },
    });

    await this.audit({
      companyId,
      actorUserId: params.actorUserId,
      actorRole: params.actorRole,
      action: 'ENROLLMENT_GRANT_ISSUED',
      ip: params.ip ?? null,
    });

    this.logger.log(
      `autorizacion de enrolamiento emitida empresa=${companyId} plataforma=${
        params.platform ?? 'n/a'
      } ttl=${config.grantTtlSeconds}s activada=${activated}`,
    );

    return {
      ok: true,
      code,
      expiresAt: expiresAt.toISOString(),
      companyId,
      activated,
    };
  }

  /** Estado del monitoreo para la revelación en la app (sin datos sensibles). */
  async getCompanyStatus(companyId: string): Promise<{
    companyId: string;
    guardianEnabled: boolean;
    autoEnrollmentAllowed: boolean;
    activeInstallations: number;
    maxInstallations: number;
  }> {
    const config = resolveGuardianAutoEnrollmentConfig();
    const id = String(companyId ?? '').trim();
    const company = id
      ? await this.prisma.company.findUnique({
          where: { id },
          select: {
            guardianEnabled: true,
            status: true,
            licenseStatus: true,
            licenseBlockedAt: true,
            licenseExpiresAt: true,
          },
        })
      : null;
    let activeInstallations = 0;
    if (id) {
      activeInstallations = await this.prisma.guardianMachineCredential.count({
        where: {
          companyId: id,
          enabled: true,
          revokedAt: null,
          OR: [{ expiresAt: null }, { expiresAt: { gt: new Date() } }],
        },
      });
    }
    return {
      companyId: id,
      guardianEnabled: company?.guardianEnabled === true,
      autoEnrollmentAllowed:
        config.enabled && isCompanyAllowedForAutoEnrollment(config, id),
      activeInstallations,
      maxInstallations: config.maxInstallationsPerCompany,
    };
  }

  /**
   * Control administrativo de desactivación.
   *
   * Además de apagar el monitoreo, revoca las credenciales de instalación y las
   * autorizaciones pendientes: una instalación ya enrolada deja de poder enviar
   * telemetría inmediatamente, sin esperar a que caduque nada.
   */
  async disableForCompany(params: {
    companyId: string;
    actorUserId: string | null;
    actorRole: string | null;
    ip?: string | null;
  }): Promise<{ credentialsRevoked: number; grantsRevoked: number }> {
    const companyId = String(params.companyId ?? '').trim();
    const now = new Date();
    await this.prisma.company.update({
      where: { id: companyId },
      data: { guardianEnabled: false },
    });
    const credentials = await this.prisma.guardianMachineCredential.updateMany({
      where: { companyId, revokedAt: null },
      data: { enabled: false, revokedAt: now },
    });
    const grants = await this.prisma.guardianEnrollmentCode.updateMany({
      where: { companyId, revokedAt: null, expiresAt: { gt: now } },
      data: { revokedAt: now },
    });
    await this.audit({
      companyId,
      actorUserId: params.actorUserId,
      actorRole: params.actorRole,
      action: 'COMPANY_GUARDIAN_DISABLED_BY_ADMIN',
      ip: params.ip ?? null,
    });
    this.logger.warn(
      `Guardian desactivado por administrador empresa=${companyId} credenciales=${credentials.count} autorizaciones=${grants.count}`,
    );
    return { credentialsRevoked: credentials.count, grantsRevoked: grants.count };
  }

  /** Límite de ráfaga en memoria: ventana de un minuto, por empresa. */
  private isBurstLimited(
    config: GuardianAutoEnrollmentConfig,
    companyId: string,
    now: Date,
  ): boolean {
    const key = companyId;
    const ts = now.getTime();
    const entry = this.bursts.get(key);
    const maxPerMinute = Math.max(1, Math.ceil(config.grantsPerCompanyHour / 4));
    if (!entry || ts - entry.startedAt >= 60_000) {
      this.bursts.set(key, { startedAt: ts, count: 1 });
      if (this.bursts.size > 5_000) {
        for (const [k, v] of this.bursts) {
          if (ts - v.startedAt > 300_000) this.bursts.delete(k);
        }
      }
      return false;
    }
    entry.count += 1;
    return entry.count > maxPerMinute;
  }

  /** Auditoría best-effort: nunca rompe el flujo del cliente. */
  private async audit(params: {
    companyId: string;
    actorUserId: string | null;
    actorRole: string | null;
    action: string;
    ip: string | null;
  }): Promise<void> {
    try {
      await this.prisma.guardianAccessLog.create({
        data: {
          actorUserId: params.actorUserId,
          actorRole: params.actorRole,
          action: params.action,
          companyId: params.companyId,
          ip: (params.ip ?? '').slice(0, 64) || null,
          requestId: `auto-enroll:${params.action}`.slice(0, 128),
        },
      });
    } catch (error) {
      this.logger.warn(
        `No se pudo auditar ${params.action}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}

/** Utilidad para pruebas: hash del código emitido (nunca se registra en logs). */
export function hashGrantCode(raw: string): string {
  return createHash('sha256').update(String(raw ?? '').trim(), 'utf8').digest('hex');
}

/** Utilidad para pruebas: forma esperada de un código emitido. */
export function isIssuedGrantCode(raw: string): boolean {
  const value = String(raw ?? '');
  return value.startsWith(GUARDIAN_ENROLLMENT_CODE_PREFIX) && /^[A-Za-z0-9_]+$/.test(value);
}

/** Genera un identificador de instalación de ejemplo (solo pruebas). */
export function debugGenerateInstallId(): string {
  return `test-${randomBytes(6).toString('hex')}`;
}
