import { decideAttempt } from "./ecf-certification-attempt.policy";
import {
  EcfCertificationRecoveryService,
  isBlockedAttempt,
  type EcfRecoveryAttemptRecord,
  type EcfRecoveryPrisma,
} from "./ecf-certification-recovery.service";

function record(overrides: Partial<EcfRecoveryAttemptRecord> = {}): EcfRecoveryAttemptRecord {
  return {
    id: "a1",
    companyId: "c1",
    operation: "SET_TESTS",
    stepKey: "SET_TESTS",
    idempotencyKey: "SET_TESTS:c1:0",
    status: "IN_PROGRESS",
    externalId: null,
    errorCode: "ECF_PROVIDER_RESULT_UNKNOWN",
    errorMessage: "TIMEOUT",
    createdAt: new Date("2026-11-01T09:00:00.000Z"),
    ...overrides,
  };
}

function fakePrisma(seed: EcfRecoveryAttemptRecord[]) {
  const rows = [...seed];
  const audits: Record<string, unknown>[] = [];
  const prisma: EcfRecoveryPrisma & { audits: Record<string, unknown>[] } = {
    audits,
    ecfCertificationAttempt: {
      findMany: async ({ where }) => rows.filter((row) => row.companyId === where.companyId),
      findUnique: async ({ where }) => rows.find((row) => row.id === where.id) ?? null,
      update: async ({ where, data }) => {
        const row = rows.find((item) => item.id === where.id);
        if (!row) throw new Error("not found");
        Object.assign(row, data);
        return row;
      },
    },
    ecfAuditLog: {
      create: async ({ data }) => {
        audits.push(data);
        return data;
      },
    },
  };
  return prisma;
}

describe("recuperación de intentos — vista administrativa", () => {
  it("solo lista los intentos bloqueados de LA empresa", async () => {
    const prisma = fakePrisma([
      record({ id: "a1" }),
      record({ id: "a2", status: "SUCCEEDED", errorCode: null }),
      record({ id: "a3", companyId: "c2" }),
      record({ id: "a4", errorCode: "HUMAN_REVIEW_REQUIRED" }),
    ]);
    const view = await new EcfCertificationRecoveryService(prisma).listBlocked("c1");
    expect(view.map((item) => item.attemptId)).toEqual(["a1", "a4"]);
  });

  it("la vista no contiene material sensible y ofrece reconciliar, no reintentar", async () => {
    const prisma = fakePrisma([record()]);
    const [item] = await new EcfCertificationRecoveryService(prisma).listBlocked("c1");
    const serialized = JSON.stringify(item);
    expect(serialized).not.toContain("PRIVATE KEY");
    expect(serialized).not.toContain("password");
    expect(item.safeAction).toContain("No se puede reenviar");
    expect(item.needsEvidence).toBe(true);
    expect(item.reason).toContain("no confirmó");
  });

  it("un intento exitoso no se considera bloqueado", () => {
    expect(isBlockedAttempt({ status: "SUCCEEDED", errorCode: null })).toBe(false);
    expect(isBlockedAttempt({ status: "BLOCKED", errorCode: null })).toBe(true);
  });
});

describe("recuperación de intentos — resolución", () => {
  it("exige evidencia para darlo por aplicado", async () => {
    const prisma = fakePrisma([record()]);
    const result = await new EcfCertificationRecoveryService(prisma).resolve({
      companyId: "c1",
      attemptId: "a1",
      actorUserId: "u1",
      decision: "CONFIRM_APPLIED_WITH_EVIDENCE",
      evidenceRef: "   ",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("ECF_ATTEMPT_EVIDENCE_REQUIRED");
  });

  it("con evidencia lo marca completado, deja auditoría y no repite la llamada", async () => {
    const prisma = fakePrisma([record()]);
    const service = new EcfCertificationRecoveryService(prisma);
    const result = await service.resolve({
      companyId: "c1",
      attemptId: "a1",
      actorUserId: "u1",
      decision: "CONFIRM_APPLIED_WITH_EVIDENCE",
      evidenceRef: "evidence://acuse-123",
      externalId: "set-999",
      note: "Confirmado en el panel del proveedor",
    });
    expect(result).toEqual({ ok: true, status: "SUCCEEDED" });
    const stored = await prisma.ecfCertificationAttempt.findUnique({ where: { id: "a1" } });
    expect(stored?.status).toBe("SUCCEEDED");
    expect(stored?.externalId).toBe("set-999");
    expect(prisma.audits).toHaveLength(1);
    // La auditoría guarda la decisión, no el documento.
    expect(JSON.stringify(prisma.audits[0])).toContain("CONFIRMED_APPLIED");

    // Y el intento ya no vuelve a enviarse nunca.
    const after = decideAttempt({
      attempt: { status: "SUCCEEDED", errorCode: null, ageMs: 10 },
      now: new Date(),
      staleAfterMs: 600_000,
    });
    expect(after).toEqual({ action: "RETURN_SUCCESS" });
  });

  it("confirmar que NO se aplicó deja el intento reintentable", async () => {
    const prisma = fakePrisma([record()]);
    const result = await new EcfCertificationRecoveryService(prisma).resolve({
      companyId: "c1",
      attemptId: "a1",
      actorUserId: "u1",
      decision: "CONFIRM_NOT_APPLIED_RETRYABLE",
      note: "El proveedor no registra el set",
    });
    expect(result).toEqual({ ok: true, status: "FAILED" });
    const stored = await prisma.ecfCertificationAttempt.findUnique({ where: { id: "a1" } });
    expect(stored?.errorCode).toBe("ECF_ATTEMPT_RECONCILED_RETRYABLE");

    // Con esa marca, la política sí permite un nuevo intento controlado.
    const after = decideAttempt({
      attempt: { status: "FAILED", errorCode: stored?.errorCode ?? null, ageMs: 10 },
      now: new Date(),
      staleAfterMs: 600_000,
      retryableFailure: true,
    });
    expect(after).toEqual({ action: "RETRY" });
  });

  it("no se puede resolver el intento de otra empresa", async () => {
    const prisma = fakePrisma([record({ companyId: "c1" })]);
    const result = await new EcfCertificationRecoveryService(prisma).resolve({
      companyId: "c2",
      attemptId: "a1",
      actorUserId: "u1",
      decision: "CONFIRM_NOT_APPLIED_RETRYABLE",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("ECF_ATTEMPT_NOT_FOUND");
    const stored = await prisma.ecfCertificationAttempt.findUnique({ where: { id: "a1" } });
    expect(stored?.status).toBe("IN_PROGRESS");
  });

  it("un intento no bloqueado no se «reconcilia»", async () => {
    const prisma = fakePrisma([record({ status: "SUCCEEDED", errorCode: null })]);
    const result = await new EcfCertificationRecoveryService(prisma).resolve({
      companyId: "c1",
      attemptId: "a1",
      actorUserId: "u1",
      decision: "CONFIRM_APPLIED_WITH_EVIDENCE",
      evidenceRef: "x",
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.code).toBe("ECF_ATTEMPT_NOT_BLOCKED");
  });
});
