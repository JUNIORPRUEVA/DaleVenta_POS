import { Injectable, Logger } from "@nestjs/common";
import { EcfAuditAction, EcfCertificationStatus, Prisma } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import { DosaActivationService } from "../provider/dosa/dosa-activation.service";
import { DosaCredentialService } from "../provider/dosa/dosa-credential.service";
import type { DosaCredentialEnvironment } from "../provider/dosa/dosa-credential-vault.service";
import { resolveCertificationStatus } from "../ecf-certification-status.policy";
import {
  canDerivePromotion,
  deriveCertificationFromCredentials,
} from "./ecf-certification-activation.policy";

/**
 * Activación y autorización de emisión SIN intervención de Fulltech.
 *
 * Problema que resuelve
 * ---------------------
 * La cadena de evidencia del cliente estaba completa y probada
 * (`DosaActivationService`), pero **nadie la invocaba**: `activate()` no tenía
 * ningún llamador en código de producción, así que la credencial se quedaba en
 * `PENDING_CONFIRMATION` para siempre y el cliente, que había hecho todo su
 * trámite, no podía facturar.
 *
 * Este servicio cierra el círculo:
 *
 * 1. Intenta activar cada credencial pendiente con la evidencia que el cliente
 *    ya produjo. No acepta «autorízame»: delega en `DosaActivationService`, que
 *    lee la evidencia de la base de datos.
 * 2. Deriva el estado de certificación de las credenciales activas
 *    (`deriveCertificationFromCredentials`): TEST activo → `AUTHORIZED_SANDBOX`,
 *    PRODUCTION activo → `PRODUCTION_READY`.
 * 3. Si algo falta, devuelve **qué falta exactamente**, para que la interfaz se
 *    lo diga al cliente en vez de un error genérico.
 *
 * Reglas de seguridad
 * -------------------
 * * **Nunca** activa una credencial `REVOKED` ni la resucita.
 * * **Nunca** levanta `SUSPENDED` (pegajoso en `resolveCertificationStatus`) ni
 *   promociona por encima de `BLOCKED`.
 * * **Nunca** degrada: sin credencial activa conserva el estado que ya había.
 * * **Nunca** crea la configuración e-CF: sin fila, no hay empresa que autorizar.
 * * Todo cambio se audita con `CERTIFICATION_STATUS_DERIVED` y actor `null`
 *   (fue el sistema, no una persona: la interfaz no debe atribuírselo a nadie).
 * * No emite ni llama a DOSA: solo lee credenciales y escribe estados.
 */

const AUDIT_TARGET_TYPE = "ECF_CERTIFICATION_AUTHORIZATION";
const AUDIT_OPERATION_DERIVED = "CERTIFICATION_STATUS_DERIVED";

export type EcfActivationEnvironmentResult = {
  environment: DosaCredentialEnvironment;
  /** Estado de la credencial después del intento. */
  status: string;
  activated: boolean;
  /** Vacío cuando se activó o ya estaba activa. */
  blockingReasons: string[];
};

export type EcfActivationAttemptResult = {
  /** `true` cuando al menos una credencial quedó `ACTIVE` por esta llamada. */
  ok: boolean;
  companyId: string;
  /** Estado de certificación vigente al terminar. */
  certificationStatus: EcfCertificationStatus | null;
  /** `true` si esta llamada cambió el estado de certificación. */
  changed: boolean;
  /** Código cuando no se pudo evaluar (sin configuración, sin empresa). */
  code?: string;
  environments: EcfActivationEnvironmentResult[];
};

@Injectable()
export class EcfCertificationActivationService {
  private readonly logger = new Logger(EcfCertificationActivationService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly activation: DosaActivationService,
    private readonly credentials: DosaCredentialService,
  ) {}

  /**
   * Ejecuta el intento completo. Es idempotente: repetirlo no activa dos veces
   * ni duplica auditoría.
   */
  async attempt(companyId: string): Promise<EcfActivationAttemptResult> {
    const id = (companyId ?? "").trim();
    if (!id) {
      return {
        ok: false,
        companyId: "",
        certificationStatus: null,
        changed: false,
        code: "COMPANY_REQUIRED",
        environments: [],
      };
    }

    const config = await this.prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId: id },
      select: { certificationStatus: true },
    });
    if (!config) {
      return {
        ok: false,
        companyId: id,
        certificationStatus: null,
        changed: false,
        code: "ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND",
        environments: [],
      };
    }

    const environments = await this.activatePendingCredentials(id);
    const activated = environments.filter((row) => row.activated).length > 0;

    const stored = await this.credentials.listForCompany(id);
    const derived = deriveCertificationFromCredentials(
      stored.map((row) => ({ environment: row.environment, status: row.status })),
    );

    const outcome = await this.persistDerivedStatus({
      companyId: id,
      current: config.certificationStatus,
      derived,
    });

    return {
      ok: activated || outcome.changed,
      companyId: id,
      certificationStatus: outcome.certificationStatus,
      changed: outcome.changed,
      ...(outcome.code ? { code: outcome.code } : {}),
      environments,
    };
  }

  /**
   * Igual que `attempt`, pero **nunca lanza**.
   *
   * Se usa como efecto secundario de una acción del cliente (registrar su
   * autorización DGII): un fallo aquí no puede romper esa acción ni devolver un
   * error al usuario por algo que ocurre después de que su petición se guardó.
   */
  async attemptSafely(
    companyId: string,
  ): Promise<EcfActivationAttemptResult | null> {
    try {
      return await this.attempt(companyId);
    } catch (error) {
      this.logger.warn(
        `No se pudo evaluar la activación e-CF de ${companyId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      return null;
    }
  }

  /**
   * Intenta activar las credenciales que no están ni activas ni revocadas.
   *
   * Usa el RNC de la PROPIA credencial, no uno leído de otra tabla: es la clave
   * con la que se guardó y la que la bóveda espera encontrar.
   */
  private async activatePendingCredentials(
    companyId: string,
  ): Promise<EcfActivationEnvironmentResult[]> {
    const stored = await this.credentials.listForCompany(companyId);
    const results: EcfActivationEnvironmentResult[] = [];

    for (const row of stored) {
      if (row.status === "ACTIVE") {
        results.push({
          environment: row.environment,
          status: row.status,
          activated: false,
          blockingReasons: [],
        });
        continue;
      }
      if (row.status === "REVOKED") {
        // Una credencial revocada no se resucita sola: eso exigiría una decisión
        // administrativa explícita.
        results.push({
          environment: row.environment,
          status: row.status,
          activated: false,
          blockingReasons: ["ECF_DOSA_CREDENTIALS_REVOKED"],
        });
        continue;
      }

      const outcome = await this.activation.activate({
        companyId,
        rnc: row.rnc,
        environment: row.environment,
      });

      results.push({
        environment: row.environment,
        status: outcome.ok ? "ACTIVE" : row.status,
        activated: outcome.ok,
        blockingReasons: outcome.ok ? [] : [...outcome.blockingReasons],
      });
    }

    return results;
  }

  /**
   * Guarda el estado derivado aplicando las mismas reglas que el resto del
   * módulo: solo promociona, respeta `SUSPENDED` y no salta `BLOCKED`.
   */
  private async persistDerivedStatus(input: {
    companyId: string;
    current: EcfCertificationStatus;
    derived: EcfCertificationStatus | null;
  }): Promise<{
    certificationStatus: EcfCertificationStatus;
    changed: boolean;
    code?: string;
  }> {
    if (input.derived === null) {
      // Sin credencial activa no hay nada que afirmar: se conserva lo que había.
      return { certificationStatus: input.current, changed: false };
    }

    if (!canDerivePromotion({ current: input.current })) {
      return {
        certificationStatus: input.current,
        changed: false,
        code: "ECF_CERTIFICATION_STATE_BLOCKED",
      };
    }

    const next = resolveCertificationStatus({
      current: input.current,
      derived: input.derived,
    });
    if (next === input.current) {
      return { certificationStatus: input.current, changed: false };
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.ecfCompanyConfiguration.update({
        where: { companyId: input.companyId },
        data: { certificationStatus: next },
      });
      await tx.ecfAuditLog.create({
        data: {
          companyId: input.companyId,
          // `null` a propósito: lo hizo el sistema al completarse la evidencia
          // del cliente, no una persona. Atribuirlo a alguien sería falso.
          actorUserId: null,
          action: EcfAuditAction.CONFIG_UPDATED,
          targetType: AUDIT_TARGET_TYPE,
          targetId: null,
          before: { certificationStatus: input.current } as Prisma.InputJsonValue,
          after: { certificationStatus: next } as Prisma.InputJsonValue,
          metadata: {
            operation: AUDIT_OPERATION_DERIVED,
            derivedFrom: "DOSA_CREDENTIALS_ACTIVE",
          } as Prisma.InputJsonValue,
        },
      });
    });

    this.logger.log(
      `Certificación e-CF de ${input.companyId}: ${input.current} -> ${next} (derivada de credenciales activas)`,
    );

    return { certificationStatus: next, changed: true };
  }
}
