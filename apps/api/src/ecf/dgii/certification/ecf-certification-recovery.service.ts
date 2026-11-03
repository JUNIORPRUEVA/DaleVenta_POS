import {
  ECF_ATTEMPT_STALE_CODE,
  ECF_ATTEMPT_UNCERTAIN_CODE,
} from "./ecf-certification-attempt.policy";

/**
 * Recuperación de operaciones en estado incierto.
 *
 * Regla que este módulo NO permite romper: **un timeout no se reenvía**. Un
 * intento bloqueado solo sale de ahí con evidencia verificable aportada por una
 * persona autorizada, y esa decisión queda registrada con su autor.
 *
 * La vista que ve el administrador no incluye certificados, contraseñas ni
 * cuerpos de documentos: solo metadatos de la operación.
 */

export type EcfBlockedAttemptView = {
  attemptId: string;
  operation: string;
  stepKey: string | null;
  createdAt: string;
  idempotencyKey: string;
  externalId: string | null;
  errorCode: string | null;
  /** Motivo legible, sin datos sensibles. */
  reason: string;
  /** Acción segura que corresponde. */
  safeAction: string;
  needsEvidence: boolean;
};

/** Decisión administrativa admitida. */
export type EcfRecoveryDecision =
  | "CONFIRM_APPLIED_WITH_EVIDENCE"
  | "CONFIRM_NOT_APPLIED_RETRYABLE";

export type EcfRecoveryResult =
  | { ok: true; status: "SUCCEEDED" | "FAILED" }
  | { ok: false; code: string; detail: string };

export type EcfRecoveryAttemptRecord = {
  id: string;
  companyId: string;
  operation: string;
  stepKey: string | null;
  idempotencyKey: string;
  status: string;
  externalId: string | null;
  errorCode: string | null;
  errorMessage: string | null;
  createdAt: Date;
};

export type EcfRecoveryPrisma = {
  ecfCertificationAttempt: {
    findMany: (args: {
      where: { companyId: string };
      orderBy: { createdAt: "desc" };
      take: number;
    }) => Promise<EcfRecoveryAttemptRecord[]>;
    findUnique: (args: { where: { id: string } }) => Promise<EcfRecoveryAttemptRecord | null>;
    update: (args: {
      where: { id: string };
      data: Record<string, unknown>;
    }) => Promise<EcfRecoveryAttemptRecord>;
  };
  ecfAuditLog?: {
    create: (args: { data: Record<string, unknown> }) => Promise<unknown>;
  };
};

const BLOCKED_CODES = new Set<string>([
  ECF_ATTEMPT_UNCERTAIN_CODE,
  ECF_ATTEMPT_STALE_CODE,
  "UNKNOWN_RESULT",
  "HUMAN_REVIEW_REQUIRED",
]);

/** ¿Este intento está bloqueado y necesita una decisión humana? */
export function isBlockedAttempt(record: {
  status: string;
  errorCode: string | null;
}): boolean {
  if (record.status === "BLOCKED") return true;
  if (record.errorCode && BLOCKED_CODES.has(record.errorCode)) return true;
  return false;
}

function reasonOf(record: EcfRecoveryAttemptRecord): string {
  if (record.errorCode === ECF_ATTEMPT_UNCERTAIN_CODE) {
    return "El proveedor no confirmó el resultado. No se sabe si la operación se aplicó.";
  }
  if (record.errorCode === ECF_ATTEMPT_STALE_CODE) {
    return "La ejecución quedó interrumpida sin confirmación de resultado.";
  }
  if (record.errorCode === "HUMAN_REVIEW_REQUIRED") {
    return "La operación quedó marcada para revisión humana explícita.";
  }
  if (record.errorCode === "UNKNOWN_RESULT") {
    return "El resultado de la operación no se pudo interpretar.";
  }
  return "La operación está bloqueada a la espera de una decisión autorizada.";
}

export class EcfCertificationRecoveryService {
  constructor(private readonly prisma: EcfRecoveryPrisma) {}

  /** Intentos que necesitan decisión, de la empresa indicada y solo de ella. */
  async listBlocked(companyId: string, limit = 50): Promise<EcfBlockedAttemptView[]> {
    const rows = await this.prisma.ecfCertificationAttempt.findMany({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      take: limit,
    });
    return rows.filter(isBlockedAttempt).map((row) => ({
      attemptId: row.id,
      operation: row.operation,
      stepKey: row.stepKey,
      createdAt: row.createdAt.toISOString(),
      idempotencyKey: row.idempotencyKey,
      externalId: row.externalId,
      errorCode: row.errorCode,
      reason: reasonOf(row),
      // Nunca se ofrece «reintentar»: se ofrece reconciliar.
      safeAction:
        "Comprueba en el proveedor si la operación se aplicó y resuélvelo con " +
        "evidencia. No se puede reenviar por un timeout.",
      needsEvidence: true,
    }));
  }

  /**
   * Resuelve un intento bloqueado con una decisión explícita.
   *
   * - `CONFIRM_APPLIED_WITH_EVIDENCE`: exige referencia de evidencia. Marca el
   *   intento como completado para que no se repita.
   * - `CONFIRM_NOT_APPLIED_RETRYABLE`: deja el intento como fallo reintentable.
   *
   * En ambos casos se comprueba que el intento pertenece a la empresa del
   * llamador: una empresa no puede resolver el intento de otra.
   */
  async resolve(input: {
    companyId: string;
    attemptId: string;
    actorUserId: string;
    decision: EcfRecoveryDecision;
    evidenceRef?: string | null;
    note?: string | null;
    externalId?: string | null;
  }): Promise<EcfRecoveryResult> {
    const record = await this.prisma.ecfCertificationAttempt.findUnique({
      where: { id: input.attemptId },
    });
    if (!record || record.companyId !== input.companyId) {
      // Mismo trato que un id inexistente: no se filtra si existe en otra empresa.
      return { ok: false, code: "ECF_ATTEMPT_NOT_FOUND", detail: "Intento no encontrado." };
    }
    if (!isBlockedAttempt(record)) {
      return {
        ok: false,
        code: "ECF_ATTEMPT_NOT_BLOCKED",
        detail: "El intento no está bloqueado; no hay nada que reconciliar.",
      };
    }

    if (input.decision === "CONFIRM_APPLIED_WITH_EVIDENCE") {
      const evidenceRef = (input.evidenceRef ?? "").trim();
      if (evidenceRef.length === 0) {
        return {
          ok: false,
          code: "ECF_ATTEMPT_EVIDENCE_REQUIRED",
          detail:
            "Para dar por aplicada la operación hay que aportar la evidencia que lo demuestre.",
        };
      }
      await this.prisma.ecfCertificationAttempt.update({
        where: { id: record.id },
        data: {
          status: "SUCCEEDED",
          errorCode: null,
          errorMessage: null,
          responseRef: evidenceRef,
          ...(input.externalId ? { externalId: input.externalId } : {}),
        },
      });
      await this.audit(input, record, "CONFIRMED_APPLIED", evidenceRef);
      return { ok: true, status: "SUCCEEDED" };
    }

    await this.prisma.ecfCertificationAttempt.update({
      where: { id: record.id },
      data: {
        status: "FAILED",
        errorCode: "ECF_ATTEMPT_RECONCILED_RETRYABLE",
        errorMessage: (input.note ?? "Confirmado por el administrador como no aplicado.").slice(
          0,
          500,
        ),
      },
    });
    await this.audit(input, record, "CONFIRMED_NOT_APPLIED", null);
    return { ok: true, status: "FAILED" };
  }

  private async audit(
    input: {
      actorUserId: string;
      companyId: string;
      decision: EcfRecoveryDecision;
      note?: string | null;
    },
    record: EcfRecoveryAttemptRecord,
    result: "CONFIRMED_APPLIED" | "CONFIRMED_NOT_APPLIED",
    evidenceRef: string | null,
  ) {
    // La auditoría registra la DECISIÓN, nunca el contenido del documento.
    await this.prisma.ecfAuditLog?.create({
      data: {
        companyId: input.companyId,
        actorUserId: input.actorUserId,
        action: "STEP_UPDATED",
        targetType: "EcfCertificationAttempt",
        before: {
          id: record.id,
          operation: record.operation,
          status: record.status,
          errorCode: record.errorCode,
        },
        after: {
          id: record.id,
          result,
          decision: input.decision,
          evidenceRef,
          note: input.note ?? null,
        },
      },
    });
  }
}
