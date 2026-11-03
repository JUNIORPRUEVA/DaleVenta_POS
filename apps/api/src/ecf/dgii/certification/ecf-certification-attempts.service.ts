import {
  ECF_ATTEMPT_UNCERTAIN_CODE,
  certificationIdempotencyKey,
  decideAttempt,
  isUncertain,
  type EcfAttemptDecision,
} from "./ecf-certification-attempt.policy";

/**
 * Intentos de certificación, con idempotencia.
 *
 * Reutiliza la tabla existente `EcfCertificationAttempt`
 * (`@@unique([companyId, idempotencyKey])`). Antes de ejecutar una operación que
 * escribe se reserva el intento; si ya existe, se decide con la política:
 *
 *  - `SUCCEEDED`       → no se repite, se devuelve el resultado.
 *  - en curso reciente → no se duplica.
 *  - incierto/abandonado → se bloquea hasta reconciliar.
 *
 * `markUncertain` es la única forma correcta de cerrar un timeout: deja el
 * intento vivo con el código de resultado desconocido para que nadie lo reenvíe.
 */

export type EcfAttemptRecord = {
  id: string;
  status: string;
  errorCode: string | null;
  externalId: string | null;
  createdAt: Date;
};

/** Forma mínima del cliente Prisma que este servicio necesita. */
export type EcfAttemptPrisma = {
  ecfCertificationAttempt: {
    findUnique: (args: {
      where: { companyId_idempotencyKey: { companyId: string; idempotencyKey: string } };
    }) => Promise<EcfAttemptRecord | null>;
    findFirst: (args: {
      where: { companyId: string; operation: string; status: string; externalId?: { not: null } };
      orderBy: { createdAt: "desc" };
    }) => Promise<{ id: string; externalId: string | null } | null>;
    create: (args: {
      data: {
        companyId: string;
        operation: string;
        idempotencyKey: string;
        status: string;
        stepKey?: string | null;
        errorCode?: string | null;
        errorMessage?: string | null;
        externalId?: string | null;
        responseRef?: string | null;
        createdByUserId?: string | null;
      };
    }) => Promise<EcfAttemptRecord>;
    update: (args: {
      where: { id: string };
      data: Record<string, unknown>;
    }) => Promise<EcfAttemptRecord>;
  };
};

export type EcfReserveResult =
  | { action: "PROCEED"; attemptId: string }
  | { action: "RETURN_SUCCESS"; attemptId: string; externalId: string | null }
  | { action: "RETRY"; attemptId: string }
  | { action: "BLOCK_IN_FLIGHT"; attemptId: string; code: string }
  | { action: "BLOCK_UNCERTAIN"; attemptId: string; code: string };

export class EcfCertificationAttemptsService {
  constructor(
    private readonly prisma: EcfAttemptPrisma,
    private readonly options: { staleAfterMs?: number; now?: () => Date } = {},
  ) {}

  private get staleAfterMs() {
    return this.options.staleAfterMs ?? 10 * 60 * 1000;
  }

  private now() {
    return this.options.now?.() ?? new Date();
  }

  /**
   * Reserva el intento o explica por qué no se puede ejecutar.
   *
   * La creación es «crear o reutilizar»: si dos ejecuciones compiten, la clave
   * única de la base de datos hace que solo una cree el intento y la otra lea el
   * existente. Nunca hay dos envíos por la misma clave lógica.
   */
  async reserve(input: {
    companyId: string;
    operation: string;
    stepKey?: string | null;
    discriminator?: string | number;
    actorUserId?: string | null;
    retryableFailure?: boolean;
  }): Promise<EcfReserveResult> {
    const idempotencyKey = certificationIdempotencyKey({
      operation: input.operation,
      companyId: input.companyId,
      discriminator: input.discriminator,
    });

    const existing = await this.findByIdempotencyKey(input.companyId, idempotencyKey);
    if (existing) {
      return this.decide(existing, input.retryableFailure);
    }

    try {
      const created = await this.prisma.ecfCertificationAttempt.create({
        data: {
          companyId: input.companyId,
          operation: input.operation,
          idempotencyKey,
          status: "IN_PROGRESS",
          stepKey: input.stepKey ?? null,
          createdByUserId: input.actorUserId ?? null,
        },
      });
      return { action: "PROCEED", attemptId: created.id };
    } catch (error) {
      // Carrera perdida contra otra ejecución: se lee el intento ganador y se
      // decide igual que si hubiera existido siempre.
      if (isUniqueViolation(error)) {
        const winner = await this.findByIdempotencyKey(input.companyId, idempotencyKey);
        if (winner) return this.decide(winner, input.retryableFailure);
      }
      throw error;
    }
  }

  async markSucceeded(
    attemptId: string,
    data: { externalId?: string | null; responseRef?: string | null } = {},
  ) {
    // Nunca se guarda el cuerpo de la respuesta: solo referencias.
    return this.prisma.ecfCertificationAttempt.update({
      where: { id: attemptId },
      data: {
        status: "SUCCEEDED",
        errorCode: null,
        errorMessage: null,
        ...(data.externalId === undefined ? {} : { externalId: data.externalId }),
        ...(data.responseRef === undefined ? {} : { responseRef: data.responseRef }),
      },
    });
  }

  async markFailed(
    attemptId: string,
    data: { errorCode: string; errorMessage?: string | null },
  ) {
    return this.prisma.ecfCertificationAttempt.update({
      where: { id: attemptId },
      data: {
        status: "FAILED",
        errorCode: data.errorCode,
        errorMessage: data.errorMessage ?? null,
      },
    });
  }

  /**
   * Cierra un intento cuyo resultado se DESCONOCE.
   *
   * Se queda en `IN_PROGRESS` con `ECF_PROVIDER_RESULT_UNKNOWN`: así la política
   * lo trata como incierto y bloquea cualquier reenvío hasta reconciliar.
   */
  async markUncertain(
    attemptId: string,
    data: { errorCode?: string; errorMessage?: string | null } = {},
  ) {
    // El `errorCode` SIEMPRE es el marcador de resultado desconocido: es lo que
    // consulta la política para bloquear el reenvío. La causa original se
    // conserva en el mensaje, no en el código.
    const cause = [data.errorCode, data.errorMessage].filter(Boolean).join(" · ");
    return this.prisma.ecfCertificationAttempt.update({
      where: { id: attemptId },
      data: {
        status: "IN_PROGRESS",
        errorCode: ECF_ATTEMPT_UNCERTAIN_CODE,
        errorMessage: cause.length > 0 ? cause : null,
      },
    });
  }

  /** ¿Este intento necesita reconciliación manual? */
  needsReconciliation(record: EcfAttemptRecord): boolean {
    return isUncertain({
      status: record.status,
      errorCode: record.errorCode,
      ageMs: 0,
    });
  }

  /**
   * Identificador externo (p. ej. el del set de pruebas) del último intento
   * completado de una operación.
   *
   * Es la ÚNICA fuente: nunca se toma de configuración ni se inventa. Si no hay
   * intento completado con identificador, devuelve `null` y el llamador debe
   * detenerse explicando qué falta.
   */
  async latestExternalId(input: {
    companyId: string;
    operation: string;
  }): Promise<string | null> {
    const record = await this.prisma.ecfCertificationAttempt.findFirst({
      where: {
        companyId: input.companyId,
        operation: input.operation,
        status: "SUCCEEDED",
        externalId: { not: null },
      },
      orderBy: { createdAt: "desc" },
    });
    const value = record?.externalId?.trim();
    return value && value.length > 0 ? value : null;
  }

  private decide(
    record: EcfAttemptRecord,
    retryableFailure: boolean | undefined,
  ): EcfReserveResult {
    const decision: EcfAttemptDecision = decideAttempt({
      attempt: {
        status: record.status,
        errorCode: record.errorCode,
        ageMs: this.now().getTime() - record.createdAt.getTime(),
      },
      now: this.now(),
      staleAfterMs: this.staleAfterMs,
      retryableFailure,
    });
    switch (decision.action) {
      case "PROCEED":
        // No puede ocurrir con un registro existente; se trata como reintento.
        return { action: "RETRY", attemptId: record.id };
      case "RETURN_SUCCESS":
        return {
          action: "RETURN_SUCCESS",
          attemptId: record.id,
          externalId: record.externalId,
        };
      case "RETRY":
        return { action: "RETRY", attemptId: record.id };
      case "BLOCK_IN_FLIGHT":
        return {
          action: "BLOCK_IN_FLIGHT",
          attemptId: record.id,
          code: decision.code,
        };
      case "BLOCK_UNCERTAIN":
        return {
          action: "BLOCK_UNCERTAIN",
          attemptId: record.id,
          code: decision.code,
        };
    }
  }

  private findByIdempotencyKey(companyId: string, idempotencyKey: string) {
    return this.prisma.ecfCertificationAttempt.findUnique({
      where: { companyId_idempotencyKey: { companyId, idempotencyKey } },
    });
  }
}

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { code?: string }).code === "P2002"
  );
}
