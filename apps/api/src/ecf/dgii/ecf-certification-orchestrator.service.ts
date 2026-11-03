import { Inject, Injectable, Optional } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

import {
  EcfAlanubeCertificationClient,
  type EcfCertificationCallContext,
  type EcfCertificationOutcome,
} from "../alanube/certification/ecf-alanube-certification.client";
import type { EcfSetTestsInput } from "../alanube/certification/ecf-alanube-certification.contracts";
import { EcfCertificationAttemptsService } from "./certification/ecf-certification-attempts.service";

/**
 * Orquestador de la certificación e-CF.
 *
 * NO es una segunda máquina de estados: recibe un paso del catálogo ya
 * clasificado por `ecf-dgii-activation.policy.ts` y devuelve el resultado en la
 * MISMA forma que consume el motor (`ok`, `simulated`, `summary`, `errorCode`,
 * `blockedReason`). El motor sigue siendo el único dueño de `EcfOnboardingStep`.
 *
 * Reglas que este servicio respeta:
 *
 *  1. Sin asociación con Alanube no se finge que existe: se bloquea explicando qué
 *     falta. Enrolar la empresa exige enviar el certificado, y la custodia del
 *     certificado sigue sin resolverse formalmente.
 *  2. Nunca se reenvía una operación de escritura sin saber si la anterior se
 *     aplicó: los intentos se reservan en `EcfCertificationAttempt`.
 *  3. Una respuesta técnica correcta del proveedor NO es una aprobación oficial:
 *     el paso se marca como máximo «técnico completado», y los pasos que exigen
 *     confirmación externa ni siquiera llegan aquí (son `CLIENT_ACTION`).
 *  4. Todo va por el transporte del módulo. Si el modo no es simulado, este
 *     orquestador no se invoca.
 */

export type EcfOrchestratorOutcome = {
  ok: boolean;
  simulated: boolean;
  summary: string;
  errorCode?: string;
  detail?: string;
  blockedReason?: string;
};

/** Forma mínima de Prisma que necesita el orquestador. */
export type EcfOrchestratorPrisma = {
  ecfCompanyConfiguration: {
    findUnique: (args: {
      where: { companyId: string };
      select: { alanubeCompanyId: true };
    }) => Promise<{ alanubeCompanyId: string | null } | null>;
  };
};

/** Pasos del catálogo que este orquestador puede ejecutar. */
export const ECF_ORCHESTRATED_STEPS = [
  "ALANUBE_REGISTRATION",
  "XML_SIGNATURE",
  "SET_TESTS",
  "SIMULATIONS",
] as const;

export type EcfOrchestratedStep = (typeof ECF_ORCHESTRATED_STEPS)[number];

export function isOrchestratedStep(key: string): key is EcfOrchestratedStep {
  return (ECF_ORCHESTRATED_STEPS as readonly string[]).includes(key);
}

@Injectable()
export class EcfCertificationOrchestratorService {
  constructor(
    private readonly config: ConfigService,
    private readonly client: EcfAlanubeCertificationClient,
    private readonly attempts: EcfCertificationAttemptsService,
    @Optional()
    @Inject("ECF_ORCHESTRATOR_PRISMA")
    private readonly prisma?: EcfOrchestratorPrisma,
  ) {}

  async runProviderStep(input: {
    companyId: string;
    stepKey: string;
    actorUserId: string;
  }): Promise<EcfOrchestratorOutcome> {
    const configuration = await this.prisma?.ecfCompanyConfiguration.findUnique({
      where: { companyId: input.companyId },
      select: { alanubeCompanyId: true },
    });
    const idCompany = configuration?.alanubeCompanyId?.trim() || null;

    if (!idCompany) {
      // Sin empresa asociada no hay nada que consultar. Asociar exige enviar el
      // certificado de firma, y esa custodia no está autorizada todavía.
      return {
        ok: false,
        simulated: true,
        summary: "SIN_ASOCIACION_ALANUBE",
        errorCode: "ECF_CERTIFICATION_NO_COMPANY_ASSOCIATION",
        blockedReason:
          "La empresa todavía no está asociada al proveedor certificado. " +
          "Asociarla requiere enviar el certificado de firma digital, y esa " +
          "custodia está pendiente de confirmación con el proveedor.",
      };
    }

    const ctx: EcfCertificationCallContext = {
      token: this.token(),
      idempotencyKey: `${input.stepKey}:${input.companyId}`,
    };

    switch (input.stepKey as EcfOrchestratedStep) {
      case "ALANUBE_REGISTRATION":
        return this.runAttempt({
          companyId: input.companyId,
          stepKey: input.stepKey,
          actorUserId: input.actorUserId,
          operation: "ALANUBE_COMPANY_INFO",
          execute: () => this.client.getCompanyInfo(idCompany, ctx),
          summarize: (value) =>
            `Empresa consultada en el proveedor${value.legalName ? `: ${value.legalName}` : ""}.`,
        });

      case "XML_SIGNATURE":
        // El XML de postulación lo produce el Portal de certificación; el
        // producto no lo genera ni lo guarda, así que no hay nada que firmar aún.
        return {
          ok: false,
          simulated: true,
          summary: "XML_NO_DISPONIBLE",
          errorCode: "ECF_CERTIFICATION_XML_NOT_AVAILABLE",
          blockedReason:
            "Falta el XML de postulación que emite el Portal de certificación. " +
            "Cuando lo tengas, se firmará con el certificado de la empresa y se " +
            "registrará como evidencia.",
        };

      case "SET_TESTS":
        return this.runAttempt({
          companyId: input.companyId,
          stepKey: input.stepKey,
          actorUserId: input.actorUserId,
          operation: "SET_TESTS",
          discriminator: 0,
          execute: () => this.client.createSetTests(this.setTestsInput(idCompany), ctx),
          // El identificador REAL que devuelve el proveedor se persiste en el
          // intento. Es el único que la consulta posterior puede usar.
          externalIdOf: (value) => value.id,
          summarize: (value) =>
            value.id
              ? `Set de pruebas generado (${value.id}).`
              : "Set de pruebas solicitado al proveedor sin identificador.",
        });

      case "SIMULATIONS": {
        const idSet = await this.attempts.latestExternalId({
          companyId: input.companyId,
          operation: "SET_TESTS",
        });
        // Sin identificador persistido no hay nada que consultar: inventarlo
        // (o tomarlo de configuración) consultaría otro set o ninguno.
        if (!idSet) {
          return {
            ok: false,
            simulated: true,
            summary: "SIN_SET_DE_PRUEBAS",
            errorCode: "ECF_CERTIFICATION_SET_TESTS_ID_MISSING",
            blockedReason:
              "Todavía no hay un set de pruebas generado con identificador " +
              "confirmado. Genera el set antes de consultar su estado.",
          };
        }
        if (idSet === idCompany) {
          return {
            ok: false,
            simulated: true,
            summary: "IDENTIFICADORES_IGUALES",
            errorCode: "ECF_ALANUBE_IDENTIFIERS_SWAPPED",
            blockedReason:
              "El identificador guardado coincide con el de la compañía: no se " +
              "puede consultar el set con datos cruzados.",
          };
        }
        return this.runAttempt({
          companyId: input.companyId,
          stepKey: input.stepKey,
          actorUserId: input.actorUserId,
          operation: "SET_TESTS_STATUS",
          discriminator: idSet,
          execute: () => this.client.checkSetTests(idSet, idCompany, ctx),
          summarize: (value) =>
            `Estado del set de pruebas: ${value.status ?? "sin estado informado"}.`,
        });
      }

      default:
        return {
          ok: false,
          simulated: false,
          summary: "PASO_NO_ORQUESTADO",
          errorCode: "ECF_CERTIFICATION_STEP_NOT_ORCHESTRATED",
        };
    }
  }

  /**
   * Envuelve una operación del proveedor con la reserva de intento.
   *
   * La reserva es lo que impide el segundo envío: si el intento anterior quedó
   * incierto, aquí se corta y se pide reconciliación.
   */
  private async runAttempt<T>(input: {
    companyId: string;
    stepKey: string;
    actorUserId: string;
    operation: string;
    discriminator?: string | number;
    execute: () => Promise<EcfCertificationOutcome<T>>;
    externalIdOf?: (value: T) => string | null;
    summarize: (value: T) => string;
  }): Promise<EcfOrchestratorOutcome> {
    const reservation = await this.attempts.reserve({
      companyId: input.companyId,
      operation: input.operation,
      stepKey: input.stepKey,
      discriminator: input.discriminator,
      actorUserId: input.actorUserId,
    });

    if (reservation.action === "BLOCK_UNCERTAIN") {
      return {
        ok: false,
        simulated: true,
        summary: "RESULTADO_INCIERTO",
        errorCode: reservation.code,
        blockedReason:
          "Una ejecución anterior de este paso quedó sin confirmación. Hay que " +
          "reconciliar el estado con el proveedor antes de volver a intentarlo.",
      };
    }
    if (reservation.action === "BLOCK_IN_FLIGHT") {
      return {
        ok: false,
        simulated: true,
        summary: "EN_CURSO",
        errorCode: reservation.code,
        blockedReason: "Este paso se está ejecutando ahora mismo.",
      };
    }
    if (reservation.action === "RETURN_SUCCESS") {
      return {
        ok: true,
        simulated: true,
        summary: `Ya estaba completado (${reservation.externalId ?? "sin referencia"}).`,
      };
    }

    const outcome = await input.execute();
    if (outcome.ok) {
      const externalId = input.externalIdOf?.(outcome.value) ?? null;
      await this.attempts.markSucceeded(reservation.attemptId, { externalId });
      return {
        ok: true,
        simulated: outcome.simulated,
        summary: input.summarize(outcome.value),
      };
    }

    if (outcome.kind === "UNCERTAIN") {
      await this.attempts.markUncertain(reservation.attemptId, {
        errorCode: outcome.code,
        errorMessage: outcome.detail,
      });
      return {
        ok: false,
        simulated: outcome.simulated,
        summary: "RESULTADO_INCIERTO",
        errorCode: outcome.code,
        detail: outcome.detail,
        blockedReason:
          "No se pudo confirmar el resultado de la operación. No se reintenta " +
          "automáticamente para evitar un doble envío.",
      };
    }

    await this.attempts.markFailed(reservation.attemptId, {
      errorCode: outcome.code,
      errorMessage: outcome.detail,
    });
    return {
      ok: false,
      simulated: outcome.simulated,
      summary: outcome.kind,
      errorCode: outcome.code,
      detail: outcome.detail,
      ...(outcome.kind === "UNCONFIGURED"
        ? {
            blockedReason:
              "La integración con el proveedor no está configurada para esta " +
              "operación en este entorno.",
          }
        : {}),
    };
  }

  private token(): string {
    return (
      this.config.get<string>("ECF_CERTIFICATION_SIMULATED_TOKEN") ??
      "simulated-certification-token"
    );
  }

  private setTestsInput(idCompany: string): EcfSetTestsInput {
    return {
      idCompany,
      retryNumber: Number(this.config.get<string>("ECF_CERTIFICATION_RETRY_NUMBER") ?? 0),
      billingIndicator: "1",
      itemName: "Servicio de prueba FullPOS",
      goodServiceIndicator: "1",
      itemDescription: "Documento de prueba del set de certificación",
      unitPriceItem: 100,
    };
  }
}
