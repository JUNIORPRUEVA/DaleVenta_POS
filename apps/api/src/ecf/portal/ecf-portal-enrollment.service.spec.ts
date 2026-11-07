import { EcfPortalEnrollmentService, isPortalAutoEnrollmentEnabled } from "./ecf-portal-enrollment.service";

/**
 * Servicio de autorizacion por empresa, con un Prisma en memoria.
 *
 * Se comprueban las reglas que pueden fallar en silencio: idempotencia de la
 * concesion, motivo obligatorio, que revocar no borre el historial, que una
 * empresa no herede la autorizacion de otra y que la inscripcion automatica
 * este apagada salvo autorizacion explicita.
 */
type Row = Record<string, any>;

function makePrismaFake(seed?: {
  companies?: string[];
  enrollments?: Row[];
  autoRuleMet?: boolean;
}) {
  const enrollments: Row[] = (seed?.enrollments ?? []).map((row, index) => ({
    id: row.id ?? `enr-${index + 1}`,
    companyId: row.companyId,
    source: row.source ?? "ADMIN_AUTHORIZATION",
    status: row.status ?? "ACTIVE",
    reason: row.reason ?? "motivo de prueba",
    contractReference: row.contractReference ?? null,
    authorizedByUserId: row.authorizedByUserId ?? null,
    expiresAt: row.expiresAt ?? null,
    revokedAt: row.revokedAt ?? null,
    revokedByUserId: row.revokedByUserId ?? null,
    revocationReason: row.revocationReason ?? null,
    createdAt: row.createdAt ?? new Date(2026, 0, 1, 0, 0, index),
  }));
  const companies = seed?.companies ?? ["company-a", "company-b"];

  let seq = enrollments.length;

  const prisma: any = {
    ecfPortalEnrollment: {
      findFirst: async ({ where }: any) => {
        const matches = enrollments
          .filter(
            (row) =>
              row.companyId === where.companyId &&
              (where.status ? row.status === where.status : true),
          )
          .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
        return matches[0] ?? null;
      },
      findMany: async ({ where, take }: any) =>
        enrollments
          .filter((row) => row.companyId === where.companyId)
          .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
          .slice(0, take ?? 20),
      create: async ({ data }: any) => {
        const row = {
          id: `enr-${++seq}`,
          status: "ACTIVE",
          revokedAt: null,
          revocationReason: null,
          // Instante creciente: en Postgres los `now()` de dos transacciones
          // seguidas nunca empatan, y la "fila mas reciente" debe ser estable.
          createdAt: new Date(2026, 0, 1, 0, 0, seq),
          ...data,
        };
        row.createdAt = new Date(2026, 0, 1, 0, 0, seq);
        enrollments.push(row);
        return row;
      },
      updateMany: async ({ where, data }: any) => {
        const matches = enrollments.filter(
          (row) => row.companyId === where.companyId && row.status === where.status,
        );
        for (const row of matches) Object.assign(row, data);
        return { count: matches.length };
      },
    },
    company: {
      findUnique: async ({ where }: any) =>
        companies.includes(where.id) ? { id: where.id } : null,
    },
    $queryRaw: async () => [{ ok: seed?.autoRuleMet === true }],
    __rows: enrollments,
  };

  return prisma;
}

const ORIGINAL_ENV = { ...process.env };

afterEach(() => {
  process.env.ECF_PORTAL_AUTO_ENROLL_ENABLED = ORIGINAL_ENV.ECF_PORTAL_AUTO_ENROLL_ENABLED;
  if (ORIGINAL_ENV.ECF_PORTAL_PILOT_COMPANY_IDS === undefined) {
    delete process.env.ECF_PORTAL_PILOT_COMPANY_IDS;
  } else {
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = ORIGINAL_ENV.ECF_PORTAL_PILOT_COMPANY_IDS;
  }
});

describe("isPortalAutoEnrollmentEnabled", () => {
  it("esta apagada por defecto", () => {
    expect(isPortalAutoEnrollmentEnabled({})).toBe(false);
    expect(isPortalAutoEnrollmentEnabled({ ECF_PORTAL_AUTO_ENROLL_ENABLED: "" })).toBe(false);
    expect(isPortalAutoEnrollmentEnabled({ ECF_PORTAL_AUTO_ENROLL_ENABLED: "no" })).toBe(false);
  });

  it("solo se enciende con 'true' explicito", () => {
    expect(isPortalAutoEnrollmentEnabled({ ECF_PORTAL_AUTO_ENROLL_ENABLED: "true" })).toBe(true);
    expect(isPortalAutoEnrollmentEnabled({ ECF_PORTAL_AUTO_ENROLL_ENABLED: " TRUE " })).toBe(true);
  });
});

describe("EcfPortalEnrollmentService.eligibility", () => {
  it("sin autorizacion ni entorno, la empresa no es elegible", async () => {
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = "";
    const service = new EcfPortalEnrollmentService(makePrismaFake());

    const result = await service.eligibility("company-a");
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("NO_AUTHORIZATION");
    expect(result.companyId).toBe("company-a");
  });

  it("una empresa inscrita es elegible sin variable de entorno", async () => {
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = "";
    const service = new EcfPortalEnrollmentService(
      makePrismaFake({ enrollments: [{ companyId: "company-a" }] }),
    );

    await expect(service.isEligible("company-a")).resolves.toBe(true);
    await expect(service.isEligible("company-b")).resolves.toBe(false);
  });

  it("devuelve la caducidad en ISO para que la interfaz pueda avisar", async () => {
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = "";
    const expiresAt = new Date("2099-01-01T00:00:00Z");
    const service = new EcfPortalEnrollmentService(
      makePrismaFake({ enrollments: [{ companyId: "company-a", expiresAt }] }),
    );

    const result = await service.eligibility("company-a");
    expect(result.expiresAt).toBe(expiresAt.toISOString());
  });

  it("la lista heredada sigue sirviendo, marcada como heredada", async () => {
    process.env.ECF_PORTAL_PILOT_COMPANY_IDS = "company-a";
    const service = new EcfPortalEnrollmentService(makePrismaFake());

    const result = await service.eligibility("company-a");
    expect(result.eligible).toBe(true);
    expect(result.reason).toBe("ENROLLED_LEGACY_ENV");
    expect(result.legacy).toBe(true);
  });

  it("sin companyId no consulta la base y cierra el acceso", async () => {
    const prisma = makePrismaFake();
    let consulted = false;
    prisma.ecfPortalEnrollment.findFirst = async () => {
      consulted = true;
      return null;
    };
    const service = new EcfPortalEnrollmentService(prisma);

    const result = await service.eligibility("   ");
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("COMPANY_NOT_FOUND");
    expect(consulted).toBe(false);
  });
});

describe("EcfPortalEnrollmentService.grant", () => {
  it("concede y deja registro de quien, por que y desde cuando", async () => {
    const prisma = makePrismaFake();
    const service = new EcfPortalEnrollmentService(prisma);

    const result = await service.grant({
      companyId: "company-a",
      source: "ADMIN_AUTHORIZATION",
      reason: "Alta comercial autorizada por direccion",
      actorUserId: "staff-1",
      contractReference: "CTR-2026-001",
    });

    expect(result).toMatchObject({ ok: true, created: true });
    expect(prisma.__rows).toHaveLength(1);
    expect(prisma.__rows[0]).toMatchObject({
      companyId: "company-a",
      status: "ACTIVE",
      authorizedByUserId: "staff-1",
      contractReference: "CTR-2026-001",
    });
  });

  it("es idempotente: una segunda concesion no duplica la vigente", async () => {
    const prisma = makePrismaFake();
    const service = new EcfPortalEnrollmentService(prisma);

    const first = await service.grant({
      companyId: "company-a",
      source: "ADMIN_AUTHORIZATION",
      reason: "Primera autorizacion valida",
      actorUserId: "staff-1",
    });
    const second = await service.grant({
      companyId: "company-a",
      source: "ADMIN_AUTHORIZATION",
      reason: "Segunda autorizacion valida",
      actorUserId: "staff-2",
    });

    expect(first).toMatchObject({ ok: true, created: true });
    expect(second).toMatchObject({ ok: true, created: false });
    expect(prisma.__rows).toHaveLength(1);
  });

  it("exige motivo: una autorizacion sin motivo no es auditable", async () => {
    const prisma = makePrismaFake();
    const service = new EcfPortalEnrollmentService(prisma);

    const result = await service.grant({
      companyId: "company-a",
      source: "ADMIN_AUTHORIZATION",
      reason: "   ",
      actorUserId: "staff-1",
    });

    expect(result).toEqual({ ok: false, blockedReason: "REASON_REQUIRED" });
    expect(prisma.__rows).toHaveLength(0);
  });

  it("rechaza un origen fuera del catalogo", async () => {
    const service = new EcfPortalEnrollmentService(makePrismaFake());

    const result = await service.grant({
      companyId: "company-a",
      source: "PORQUE_SI" as any,
      reason: "Motivo suficientemente largo",
      actorUserId: "staff-1",
    });

    expect(result).toEqual({ ok: false, blockedReason: "SOURCE_NOT_ALLOWED" });
  });

  it("no autoriza una empresa inexistente", async () => {
    const prisma = makePrismaFake({ companies: ["company-a"] });
    const service = new EcfPortalEnrollmentService(prisma);

    const result = await service.grant({
      companyId: "company-z",
      source: "ADMIN_AUTHORIZATION",
      reason: "Motivo suficientemente largo",
      actorUserId: "staff-1",
    });

    expect(result).toEqual({ ok: false, blockedReason: "COMPANY_NOT_FOUND" });
    expect(prisma.__rows).toHaveLength(0);
  });

  it("autorizar una empresa no autoriza a otra", async () => {
    const prisma = makePrismaFake();
    const service = new EcfPortalEnrollmentService(prisma);

    await service.grant({
      companyId: "company-a",
      source: "ADMIN_AUTHORIZATION",
      reason: "Motivo suficientemente largo",
      actorUserId: "staff-1",
    });

    await expect(service.isEligible("company-a")).resolves.toBe(true);
    await expect(service.isEligible("company-b")).resolves.toBe(false);
  });

  it("permite conceder de nuevo despues de revocar, sin reutilizar la fila", async () => {
    const prisma = makePrismaFake();
    const service = new EcfPortalEnrollmentService(prisma);

    await service.grant({
      companyId: "company-a",
      source: "ADMIN_AUTHORIZATION",
      reason: "Autorizacion inicial valida",
      actorUserId: "staff-1",
    });
    await service.revoke({ companyId: "company-a", actorUserId: "staff-1", reason: "Baja del cliente" });
    const again = await service.grant({
      companyId: "company-a",
      source: "CONTRACT_REFERENCE",
      reason: "Reactivacion por contrato nuevo",
      actorUserId: "staff-2",
    });

    expect(again).toMatchObject({ ok: true, created: true });
    // Historial: la revocada se conserva y se anade una nueva.
    expect(prisma.__rows).toHaveLength(2);
    await expect(service.isEligible("company-a")).resolves.toBe(true);
  });
});

describe("EcfPortalEnrollmentService.revoke", () => {
  it("revoca sin borrar: el historial queda completo", async () => {
    const prisma = makePrismaFake({ enrollments: [{ companyId: "company-a" }] });
    const service = new EcfPortalEnrollmentService(prisma);

    const result = await service.revoke({
      companyId: "company-a",
      actorUserId: "staff-1",
      reason: "Cliente solicito la baja",
    });

    expect(result).toEqual({ ok: true, revoked: 1 });
    expect(prisma.__rows).toHaveLength(1);
    expect(prisma.__rows[0]).toMatchObject({
      status: "REVOKED",
      revokedByUserId: "staff-1",
      revocationReason: "Cliente solicito la baja",
    });
    expect(prisma.__rows[0].revokedAt).toBeInstanceOf(Date);
    await expect(service.isEligible("company-a")).resolves.toBe(false);
  });

  it("exige motivo tambien al revocar", async () => {
    const prisma = makePrismaFake({ enrollments: [{ companyId: "company-a" }] });
    const service = new EcfPortalEnrollmentService(prisma);

    const result = await service.revoke({ companyId: "company-a", actorUserId: "s", reason: "  " });
    expect(result).toEqual({ ok: false, blockedReason: "REASON_REQUIRED" });
    expect(prisma.__rows[0].status).toBe("ACTIVE");
  });

  it("revocar una empresa no afecta a las demas", async () => {
    const prisma = makePrismaFake({
      enrollments: [{ companyId: "company-a" }, { companyId: "company-b" }],
    });
    const service = new EcfPortalEnrollmentService(prisma);

    await service.revoke({ companyId: "company-a", actorUserId: "s", reason: "Baja de A" });

    await expect(service.isEligible("company-a")).resolves.toBe(false);
    await expect(service.isEligible("company-b")).resolves.toBe(true);
  });
});

describe("EcfPortalEnrollmentService.ensureAutoEnrollment", () => {
  it("esta apagada por defecto: no inscribe a nadie", async () => {
    process.env.ECF_PORTAL_AUTO_ENROLL_ENABLED = "";
    const prisma = makePrismaFake({ autoRuleMet: true });
    const service = new EcfPortalEnrollmentService(prisma);

    await expect(service.ensureAutoEnrollment("company-a")).resolves.toBe(false);
    expect(prisma.__rows).toHaveLength(0);
  });

  it("con la bandera encendida, inscribe a quien cumple la regla", async () => {
    process.env.ECF_PORTAL_AUTO_ENROLL_ENABLED = "true";
    const prisma = makePrismaFake({ autoRuleMet: true });
    const service = new EcfPortalEnrollmentService(prisma);

    await expect(service.ensureAutoEnrollment("company-a")).resolves.toBe(true);
    expect(prisma.__rows[0]).toMatchObject({
      companyId: "company-a",
      source: "AUTO_ELIGIBLE",
      status: "ACTIVE",
    });
  });

  it("con la bandera encendida, no inscribe a quien NO cumple la regla", async () => {
    process.env.ECF_PORTAL_AUTO_ENROLL_ENABLED = "true";
    const prisma = makePrismaFake({ autoRuleMet: false });
    const service = new EcfPortalEnrollmentService(prisma);

    await expect(service.ensureAutoEnrollment("company-a")).resolves.toBe(false);
    expect(prisma.__rows).toHaveLength(0);
  });

  it("nunca lanza: un fallo de base no rompe el flujo que la invoca", async () => {
    process.env.ECF_PORTAL_AUTO_ENROLL_ENABLED = "true";
    const prisma = makePrismaFake({ autoRuleMet: true });
    prisma.$queryRaw = async () => {
      throw new Error("boom");
    };
    const service = new EcfPortalEnrollmentService(prisma);

    await expect(service.ensureAutoEnrollment("company-a")).resolves.toBe(false);
  });
});
