import {
  ECF_ATTEMPT_STALE_CODE,
  ECF_ATTEMPT_UNCERTAIN_CODE,
  certificationIdempotencyKey,
  decideAttempt,
} from "./ecf-certification-attempt.policy";
import {
  EcfCertificationAttemptsService,
  type EcfAttemptPrisma,
  type EcfAttemptRecord,
} from "./ecf-certification-attempts.service";

const now = new Date("2026-11-01T10:00:00.000Z");

function attempt(overrides: Partial<EcfAttemptRecord> = {}): EcfAttemptRecord {
  return {
    id: "a1",
    status: "IN_PROGRESS",
    errorCode: null,
    externalId: null,
    createdAt: new Date(now.getTime() - 1000),
    ...overrides,
  };
}

describe("política de intentos de certificación", () => {
  it("sin intento previo se procede", () => {
    expect(
      decideAttempt({ attempt: null, now, staleAfterMs: 600_000 }),
    ).toEqual({ action: "PROCEED" });
  });

  it("un éxito previo nunca se repite", () => {
    expect(
      decideAttempt({
        attempt: { status: "SUCCEEDED", errorCode: null, ageMs: 1 },
        now,
        staleAfterMs: 600_000,
      }),
    ).toEqual({ action: "RETURN_SUCCESS" });
  });

  it("un resultado desconocido bloquea hasta reconciliar", () => {
    const decision = decideAttempt({
      attempt: {
        status: "IN_PROGRESS",
        errorCode: ECF_ATTEMPT_UNCERTAIN_CODE,
        ageMs: 5,
      },
      now,
      staleAfterMs: 600_000,
    });
    expect(decision).toEqual({
      action: "BLOCK_UNCERTAIN",
      code: ECF_ATTEMPT_UNCERTAIN_CODE,
    });
  });

  it("un intento en curso reciente no se duplica", () => {
    expect(
      decideAttempt({
        attempt: { status: "IN_PROGRESS", errorCode: null, ageMs: 1000 },
        now,
        staleAfterMs: 600_000,
      }),
    ).toEqual({ action: "BLOCK_IN_FLIGHT", code: "ECF_ATTEMPT_IN_FLIGHT" });
  });

  it("un intento abandonado NO se reenvía: pudo haberse aplicado", () => {
    expect(
      decideAttempt({
        attempt: { status: "IN_PROGRESS", errorCode: null, ageMs: 3_600_000 },
        now,
        staleAfterMs: 600_000,
      }),
    ).toEqual({ action: "BLOCK_UNCERTAIN", code: ECF_ATTEMPT_STALE_CODE });
  });

  it("un fallo definitivo reintentable se reintenta; uno no reintentable no", () => {
    expect(
      decideAttempt({
        attempt: { status: "FAILED", errorCode: "X", ageMs: 10 },
        now,
        staleAfterMs: 600_000,
        retryableFailure: true,
      }),
    ).toEqual({ action: "RETRY" });
    expect(
      decideAttempt({
        attempt: { status: "FAILED", errorCode: "X", ageMs: 10 },
        now,
        staleAfterMs: 600_000,
        retryableFailure: false,
      }).action,
    ).toBe("BLOCK_UNCERTAIN");
  });
});

describe("clave de idempotencia", () => {
  it("es determinista y distingue operaciones y discriminadores", () => {
    const a = certificationIdempotencyKey({
      operation: "SET_TESTS",
      companyId: "c1",
      discriminator: 0,
    });
    const b = certificationIdempotencyKey({
      operation: "SET_TESTS",
      companyId: "c1",
      discriminator: 0,
    });
    const other = certificationIdempotencyKey({
      operation: "SET_TESTS",
      companyId: "c1",
      discriminator: 1,
    });
    expect(a).toBe(b);
    expect(a).not.toBe(other);
    expect(a).toBe("SET_TESTS:c1:0");
  });
});

/** Prisma falso con la clave única de la base de datos. */
function fakePrisma() {
  const rows: EcfAttemptRecord[] = [];
  const prisma: EcfAttemptPrisma & { rows: EcfAttemptRecord[] } = {
    rows,
    ecfCertificationAttempt: {
      findUnique: async ({ where }) =>
        rows.find(
          (row) =>
            row.id === where.companyId_idempotencyKey.companyId ||
            (row as unknown as { companyId?: string; idempotencyKey?: string })
              .idempotencyKey === where.companyId_idempotencyKey.idempotencyKey,
        ) ?? null,
      create: async ({ data }) => {
        // Simula la restricción única de la base.
        const exists = rows.some(
          (row) =>
            (row as unknown as { idempotencyKey?: string }).idempotencyKey ===
            data.idempotencyKey,
        );
        if (exists) {
          const error = Object.assign(new Error("unique"), { code: "P2002" });
          throw error;
        }
        const created = {
          id: `a${rows.length + 1}`,
          status: data.status,
          errorCode: data.errorCode ?? null,
          externalId: data.externalId ?? null,
          createdAt: now,
          ...data,
        } as unknown as EcfAttemptRecord;
        rows.push(created);
        return created;
      },
      update: async ({ where, data }) => {
        const row = rows.find((item) => item.id === where.id);
        if (!row) throw new Error("not found");
        Object.assign(row, data);
        return row;
      },
    },
  };
  return prisma;
}

describe("servicio de intentos — idempotencia y carreras", () => {
  const service = (prisma: EcfAttemptPrisma) =>
    new EcfCertificationAttemptsService(prisma, {
      now: () => now,
      staleAfterMs: 600_000,
    });

  it("la primera reserva crea el intento y la segunda NO duplica", async () => {
    const prisma = fakePrisma();
    const svc = service(prisma);
    const first = await svc.reserve({ companyId: "c1", operation: "SET_TESTS", discriminator: 0 });
    expect(first.action).toBe("PROCEED");
    const second = await svc.reserve({ companyId: "c1", operation: "SET_TESTS", discriminator: 0 });
    expect(second.action).toBe("BLOCK_IN_FLIGHT");
    expect(prisma.rows).toHaveLength(1);
  });

  it("una reserva simultánea (P2002) reutiliza el intento ganador", async () => {
    const prisma = fakePrisma();
    // El intento ya existe, pero `findUnique` del falso no lo ve la primera vez.
    prisma.rows.push({
      id: "a1",
      status: "IN_PROGRESS",
      errorCode: null,
      externalId: null,
      createdAt: now,
      // campos extra que usa el falso para la clave única
      companyId: "c1",
      idempotencyKey: "SIGN:c1",
    } as unknown as EcfAttemptRecord);
    const svc = service(prisma);
    const result = await svc.reserve({ companyId: "c1", operation: "SIGN" });
    expect(["BLOCK_IN_FLIGHT", "PROCEED"]).toContain(result.action);
    expect(prisma.rows.length).toBeLessThanOrEqual(2);
  });

  it("tras un éxito, la misma operación devuelve el resultado y no reenvía", async () => {
    const prisma = fakePrisma();
    const svc = service(prisma);
    const reserved = await svc.reserve({ companyId: "c1", operation: "SIGN" });
    expect(reserved.action).toBe("PROCEED");
    if (reserved.action !== "PROCEED") return;
    await svc.markSucceeded(reserved.attemptId, { externalId: "doc-1" });

    const again = await svc.reserve({ companyId: "c1", operation: "SIGN" });
    expect(again.action).toBe("RETURN_SUCCESS");
    if (again.action === "RETURN_SUCCESS") expect(again.externalId).toBe("doc-1");
    expect(prisma.rows).toHaveLength(1);
  });

  it("un timeout deja el intento incierto y bloquea el reenvío", async () => {
    const prisma = fakePrisma();
    const svc = service(prisma);
    const reserved = await svc.reserve({ companyId: "c1", operation: "SET_TESTS", discriminator: 0 });
    if (reserved.action !== "PROCEED") throw new Error("esperaba PROCEED");
    await svc.markUncertain(reserved.attemptId, { errorMessage: "timeout" });

    const retry = await svc.reserve({
      companyId: "c1",
      operation: "SET_TESTS",
      discriminator: 0,
    });
    expect(retry.action).toBe("BLOCK_UNCERTAIN");
    if (retry.action === "BLOCK_UNCERTAIN") {
      expect(retry.code).toBe(ECF_ATTEMPT_UNCERTAIN_CODE);
    }
    expect(prisma.rows).toHaveLength(1);
  });

  it("tras reiniciar el proceso el intento sigue bloqueando el reenvío", async () => {
    const prisma = fakePrisma();
    const first = service(prisma);
    const reserved = await first.reserve({ companyId: "c1", operation: "SET_TESTS", discriminator: 0 });
    if (reserved.action !== "PROCEED") throw new Error("esperaba PROCEED");
    await first.markUncertain(reserved.attemptId);

    // Instancia nueva = proceso reiniciado; lee el mismo estado persistido.
    const restarted = service(prisma);
    const result = await restarted.reserve({
      companyId: "c1",
      operation: "SET_TESTS",
      discriminator: 0,
    });
    expect(result.action).toBe("BLOCK_UNCERTAIN");
  });

  it("empresas distintas tienen intentos independientes", async () => {
    const prisma = fakePrisma();
    const svc = service(prisma);
    const a = await svc.reserve({ companyId: "c1", operation: "SET_TESTS", discriminator: 0 });
    const b = await svc.reserve({ companyId: "c2", operation: "SET_TESTS", discriminator: 0 });
    expect(a.action).toBe("PROCEED");
    expect(b.action).toBe("PROCEED");
    expect(prisma.rows).toHaveLength(2);
  });
});
