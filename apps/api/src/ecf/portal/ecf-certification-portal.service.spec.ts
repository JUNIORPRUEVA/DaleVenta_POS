import {
  ConflictException,
  ForbiddenException,
  GoneException,
  UnauthorizedException,
} from "@nestjs/common";

import {
  EcfCertificationPortalService,
  PORTAL_SESSION_TTL_SECONDS,
  PORTAL_TICKET_TTL_SECONDS,
  hashToken,
  milestonesFor,
  parsePilotCompanyIds,
} from "./ecf-certification-portal.service";
import { EcfPortalEnrollmentService } from "./ecf-portal-enrollment.service";

/** Empresas autorizadas en las pruebas, salvo que el test diga otra cosa. */
const PILOT = ["company-a", "company-b"];

/**
 * Doble en memoria del PrismaService.
 *
 * Se limita a las operaciones que usa el servicio del portal. No pretende
 * imitar SQL: sirve para comprobar las REGLAS (hash, un solo uso, caducidad y
 * aislamiento por empresa), que es lo que puede fallar en silencio.
 */
function makePrismaFake(seed?: {
  companies?: Array<{ id: string; name: string }>;
  dosaSessions?: Array<Record<string, unknown>>;
  ecfConfigs?: Array<{ companyId: string; enabled: boolean }>;
  intentionProvider?: string | null;
  reconciled?: boolean;
  enrollments?: Array<Record<string, any>>;
  autoRuleMet?: boolean;
}) {
  const tickets: Array<Record<string, any>> = [];
  const sessions: Array<Record<string, any>> = [];
  const companies = seed?.companies ?? [
    { id: "company-a", name: "FULLTECH SRL" },
    { id: "company-b", name: "OTRA EMPRESA SRL" },
  ];
  const dosaSessions = (seed?.dosaSessions ?? [
    { companyId: "company-a", rnc: "000000001", attemptNo: 1,
      status: "NOT_STARTED", providerPostulationId: null, createdAt: new Date() },
    { companyId: "company-b", rnc: "999999999", attemptNo: 1,
      status: "NOT_STARTED", providerPostulationId: null, createdAt: new Date() },
  ]).map((row) => ({ id: `dosa-${row.companyId}`, ...row }));
  const ecfConfigs = seed?.ecfConfigs ?? [];

  let seq = 0;
  const nextId = (prefix: string) => `${prefix}-${++seq}`;

  const prisma: any = {
    // Regla de autoservicio: por defecto NO se cumple, de modo que estas
    // pruebas siguen midiendo la autorización explícita y la lista heredada.
    $queryRaw: async () => [{ ok: seed?.autoRuleMet === true }],
    ecfCertificationPortalTicket: {
      create: async ({ data }: any) => {
        const row = {
          id: nextId("ticket"),
          usedAt: null,
          createdAt: new Date(),
          ...data,
        };
        tickets.push(row);
        return row;
      },
      findUnique: async ({ where }: any) => {
        if (where.tokenHash) {
          return tickets.find((t) => t.tokenHash === where.tokenHash) ?? null;
        }
        return tickets.find((t) => t.id === where.id) ?? null;
      },
      updateMany: async ({ where, data }: any) => {
        const matches = tickets.filter(
          (t) =>
            (where.companyId === undefined || t.companyId === where.companyId) &&
            (where.id === undefined || t.id === where.id) &&
            (where.usedAt === undefined || t.usedAt === where.usedAt),
        );
        matches.forEach((t) => Object.assign(t, data));
        return { count: matches.length };
      },
    },
    ecfCertificationPortalSession: {
      create: async ({ data }: any) => {
        const row = {
          id: nextId("session"),
          revokedAt: null,
          lastSeenAt: null,
          createdAt: new Date(),
          ...data,
        };
        sessions.push(row);
        return row;
      },
      findUnique: async ({ where }: any) => {
        if (where.tokenHash) {
          return sessions.find((s) => s.tokenHash === where.tokenHash) ?? null;
        }
        return sessions.find((s) => s.id === where.id) ?? null;
      },
      update: async ({ where, data }: any) => {
        const row = sessions.find((s) => s.id === where.id);
        if (!row) throw new Error("session not found");
        Object.assign(row, data);
        return row;
      },
      updateMany: async ({ where, data }: any) => {
        const matches = sessions.filter(
          (s) =>
            (where.tokenHash === undefined || s.tokenHash === where.tokenHash) &&
            (where.revokedAt === undefined || s.revokedAt === where.revokedAt),
        );
        matches.forEach((s) => Object.assign(s, data));
        return { count: matches.length };
      },
    },
    company: {
      findUnique: async ({ where }: any) =>
        companies.find((c) => c.id === where.id) ?? null,
    },
    ecfDosaCertificationSession: {
      findFirst: async ({ where }: any) => {
        const rows = dosaSessions.filter((r) => r.companyId === where.companyId);
        return rows.length > 0 ? rows[rows.length - 1] : null;
      },
    },
    ecfAuditLog: {
      findMany: async () => seed?.intentionProvider === null ? [] : [
        { id: "audit-1", action: "ONBOARDING_STARTED",
          metadata: { provider: seed?.intentionProvider ?? "DOSA", created: true } },
        ...(seed?.reconciled ? [{ id: "audit-2", action: "INTENT_PROVIDER_RECONCILED",
          actorUserId: "admin-a", before: { provider: "ALANUBE" },
          after: { provider: "DOSA" }, metadata: { sourceAuditId: "audit-1",
            externalReviewReference: "provider-review-123",
            ownerApprovalReference: "owner-approval-123" } }] : []),
      ],
    },
    ecfCompanyConfiguration: {
      findUnique: async ({ where }: any) =>
        ecfConfigs.find((c) => c.companyId === where.companyId) ?? null,
    },
    // Autorizaciones POR EMPRESA. Por defecto vacio: la elegibilidad de estas
    // pruebas viene de la lista heredada, que es el caso de compatibilidad.
    ecfPortalEnrollment: {
      findFirst: async ({ where }: any) =>
        (seed?.enrollments ?? []).find((e: any) => e.companyId === where.companyId) ?? null,
      findMany: async ({ where }: any) =>
        (seed?.enrollments ?? []).filter((e: any) => e.companyId === where.companyId),
      create: async ({ data }: any) => ({ id: "enrollment-1", ...data }),
      updateMany: async () => ({ count: 0 }),
    },
    company: {
      findUnique: async ({ where }: any) =>
        companies.find((c) => c.id === where.id) ?? null,
    },
    // El servicio usa $transaction(array); en el doble basta con ejecutarlo.
    $transaction: async (ops: Array<Promise<unknown>>) => Promise.all(ops),
    __rows: { tickets, sessions },
  };

  return prisma;
}

function makeService(prisma: any, pilot: string[] = PILOT) {
  process.env.ECF_PORTAL_PILOT_COMPANY_IDS = pilot.join(',');
  return new EcfCertificationPortalService(
    prisma,
    new EcfPortalEnrollmentService(prisma),
  );
}

describe("elegibilidad (solo lectura)", () => {
  it("la empresa autorizada por entorno es elegible sin activar la emision", async () => {
    const service = makeService(makePrismaFake(), ["company-a"]);
    const result = await service.eligibility("company-a");
    expect(result.eligible).toBe(true);
    expect(result.reason).toBe("ENROLLED_LEGACY_ENV");
    expect(result.portalPath).toBe("/ecf/certificacion");
  });

  it("una empresa sin autorizacion no es elegible, y el motivo lo dice", async () => {
    const service = makeService(makePrismaFake(), ["company-a"]);
    const result = await service.eligibility("company-b");
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("NO_AUTHORIZATION");
  });

  it("sin piloto configurado nadie es elegible (cerrado por defecto)", async () => {
    const service = makeService(makePrismaFake(), []);
    expect((await service.eligibility("company-a")).eligible).toBe(false);
  });

  it("consultar la elegibilidad no crea tickets ni sesiones", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma, ["company-a"]);

    await service.eligibility("company-a");
    await service.eligibility("company-b");

    expect(prisma.__rows.tickets).toHaveLength(0);
    expect(prisma.__rows.sessions).toHaveLength(0);
  });
});

describe("autorizacion por empresa (base de datos, no entorno)", () => {
  const ACTIVE = (companyId: string, extra: Record<string, unknown> = {}) => ({
    companyId,
    status: "ACTIVE",
    source: "ADMIN_AUTHORIZATION",
    expiresAt: null,
    revokedAt: null,
    ...extra,
  });

  it("una empresa inscrita es elegible SIN figurar en la lista del entorno", async () => {
    const prisma = makePrismaFake({ enrollments: [ACTIVE("company-b")] });
    // La lista heredada solo contiene company-a: company-b entra por su fila.
    const service = makeService(prisma, ["company-a"]);

    const result = await service.eligibility("company-b");
    expect(result.eligible).toBe(true);
    expect(result.reason).toBe("ENROLLED");
    await expect(
      service.issueTicket({ companyId: "company-b", userId: "admin-b" }),
    ).resolves.toHaveProperty("ticket");
  });

  it("con la lista del entorno vacia, la fila de la empresa sigue sirviendo", async () => {
    const prisma = makePrismaFake({ enrollments: [ACTIVE("company-a")] });
    const service = makeService(prisma, []);
    expect((await service.eligibility("company-a")).eligible).toBe(true);
  });

  it("una autorizacion caducada deja de servir sin tocar el entorno", async () => {
    const prisma = makePrismaFake({
      enrollments: [ACTIVE("company-a", { expiresAt: new Date("2020-01-01T00:00:00Z") })],
    });
    const service = makeService(prisma, []);
    const result = await service.eligibility("company-a");
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe("AUTHORIZATION_EXPIRED");
  });

  it("una autorizacion revocada corta el acceso del ticket ya emitido", async () => {
    const prisma = makePrismaFake();
    const { ticket } = await makeService(prisma, ["company-a"]).issueTicket({
      companyId: "company-a",
      userId: "u",
    });

    // Se revoca en la base (la lista heredada se deja como estaba a proposito:
    // la revocacion debe ganarle).
    (prisma as any).ecfPortalEnrollment.findFirst = async () =>
      ACTIVE("company-a", { status: "REVOKED", revokedAt: new Date() });

    await expect(
      makeService(prisma, ["company-a"]).exchangeTicket({ ticket }),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("la autorizacion de una empresa no habilita a otra", async () => {
    const prisma = makePrismaFake({ enrollments: [ACTIVE("company-a")] });
    const service = makeService(prisma, []);

    await expect(
      service.issueTicket({ companyId: "company-b", userId: "admin-b" }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.__rows.tickets).toHaveLength(0);
  });
});

describe("compuerta del piloto (por companyId)", () => {
  it("no emite ticket para un intento histórico ALANUBE", async () => {
    const prisma = makePrismaFake({ intentionProvider: "ALANUBE" });
    const service = makeService(prisma, ["company-a"]);
    await expect(service.issueTicket({ companyId: "company-a", userId: "u" }))
      .rejects.toThrow("PORTAL_INTENTION_PROVIDER_UNVERIFIED");
    expect(prisma.__rows.tickets).toHaveLength(0);
  });

  it("acepta la reconciliación auditada solo para el intento y empresa piloto", async () => {
    const prisma = makePrismaFake({ intentionProvider: "ALANUBE", reconciled: true });
    const service = makeService(prisma, ["company-a"]);
    await expect(service.issueTicket({ companyId: "company-a", userId: "admin-a" }))
      .resolves.toHaveProperty("ticket");
    await expect(service.issueTicket({ companyId: "company-b", userId: "admin-b" }))
      .rejects.toBeInstanceOf(ForbiddenException);
  });

  it("no emite ticket sin intento verificado", async () => {
    const prisma = makePrismaFake({ dosaSessions: [] });
    const service = makeService(prisma, ["company-a"]);
    await expect(service.issueTicket({ companyId: "company-a", userId: "u" }))
      .rejects.toThrow("PORTAL_INTENTION_REQUIRED");
    expect(prisma.__rows.tickets).toHaveLength(0);
  });
  it("sin empresas configuradas el portal esta cerrado para todos", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma, []);

    expect(await service.isPilotCompany("company-a")).toBe(false);
    await expect(
      service.issueTicket({ companyId: "company-a", userId: "u" }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    // Ni siquiera se creo un ticket.
    expect(prisma.__rows.tickets).toHaveLength(0);
  });

  it("una empresa fuera del piloto no obtiene ticket aunque sea administradora", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma, ["company-a"]);

    await expect(
      service.issueTicket({ companyId: "company-b", userId: "admin-b" }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    await expect(
      service.issueTicket({ companyId: "company-a", userId: "admin-a" }),
    ).resolves.toHaveProperty("ticket");
  });

  it("un ticket de una empresa retirada del piloto no abre sesion", async () => {
    const prisma = makePrismaFake();
    const abierto = makeService(prisma, ["company-a"]);
    const { ticket } = await abierto.issueTicket({
      companyId: "company-a",
      userId: "u",
    });

    // Se retira la empresa del piloto entre la emision y el canje.
    const cerrado = makeService(prisma, []);
    await expect(cerrado.exchangeTicket({ ticket })).rejects.toBeInstanceOf(
      ForbiddenException,
    );
  });

  it("una sesion viva deja de servir cuando la empresa sale del piloto", async () => {
    const prisma = makePrismaFake();
    const { token } = await makeService(prisma, ["company-a"]).exchangeTicket({
      ticket: (
        await makeService(prisma, ["company-a"]).issueTicket({
          companyId: "company-a",
          userId: "u",
        })
      ).ticket,
    });

    await expect(
      makeService(prisma, []).readContext(token),
    ).rejects.toBeInstanceOf(ForbiddenException);
  });

  it("la lista de empresas tolera comas, espacios y mayusculas", () => {
    expect(
      parsePilotCompanyIds(" AAAA-1111 , bbbb-2222;;  CCCC-3333 "),
    ).toEqual(["aaaa-1111", "bbbb-2222", "cccc-3333"]);
    expect(parsePilotCompanyIds(undefined)).toEqual([]);
    expect(parsePilotCompanyIds("   ")).toEqual([]);
  });
});

describe("EcfCertificationPortalService", () => {
  it("emite un ticket guardando solo su hash y sin exponerlo en la base", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma);

    const { ticket, expiresAt } = await service.issueTicket({
      companyId: "company-a",
      userId: "user-1",
    });

    expect(ticket.length).toBeGreaterThanOrEqual(40);
    expect(prisma.__rows.tickets).toHaveLength(1);
    expect(prisma.__rows.tickets[0].tokenHash).toBe(hashToken(ticket));
    expect(prisma.__rows.tickets[0].tokenHash).not.toBe(ticket);
    // 120 s de vida: ni eterno ni inutilizable.
    const ttl = new Date(expiresAt).getTime() - Date.now();
    expect(ttl).toBeGreaterThan(100 * 1000);
    expect(ttl).toBeLessThanOrEqual(PORTAL_TICKET_TTL_SECONDS * 1000);
  });

  it("un ticket nuevo invalida el anterior sin tocar otras empresas", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma);

    await service.issueTicket({ companyId: "company-a", userId: "user-1" });
    await service.issueTicket({ companyId: "company-b", userId: "user-2" });
    await service.issueTicket({ companyId: "company-a", userId: "user-1" });

    const usadosA = prisma.__rows.tickets.filter(
      (t: any) => t.companyId === "company-a" && t.usedAt !== null,
    );
    const vivosB = prisma.__rows.tickets.filter(
      (t: any) => t.companyId === "company-b" && t.usedAt === null,
    );
    expect(usadosA).toHaveLength(1);
    expect(vivosB).toHaveLength(1);
  });

  it("canjea el ticket y devuelve el contexto de SU empresa", async () => {
    const prisma = makePrismaFake({
      dosaSessions: [
        {
          companyId: "company-a",
          rnc: "000000001",
          attemptNo: 1,
          status: "RUNNING",
          providerPostulationId: null,
          createdAt: new Date("2026-11-02T10:00:00Z"),
        },
      ],
    });
    const service = makeService(prisma);

    const { ticket } = await service.issueTicket({
      companyId: "company-a",
      userId: "user-1",
    });
    const result = await service.exchangeTicket({ ticket });

    expect(result.token.length).toBeGreaterThanOrEqual(40);
    expect(result.context.company.id).toBe("company-a");
    expect(result.context.company.commercialName).toBe("FULLTECH SRL");
    expect(result.context.company.taxId).toBe("000000001");
    expect(result.context.postulation?.attemptNo).toBe(1);
    expect(result.context.milestones.application).toBe("in_progress");
    // El portal NO enciende nada: e-CF sigue apagado si la empresa no lo tiene.
    expect(result.context.ecfEnabled).toBe(false);
  });

  it("un ticket ya usado no se puede canjear dos veces", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma);
    const { ticket } = await service.issueTicket({
      companyId: "company-a",
      userId: "user-1",
    });

    await service.exchangeTicket({ ticket });
    await expect(service.exchangeTicket({ ticket })).rejects.toBeInstanceOf(
      ConflictException,
    );
  });

  it("un ticket vencido se rechaza", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma);
    const { ticket } = await service.issueTicket({
      companyId: "company-a",
      userId: "user-1",
    });
    prisma.__rows.tickets[0].expiresAt = new Date(Date.now() - 1000);

    await expect(service.exchangeTicket({ ticket })).rejects.toBeInstanceOf(
      GoneException,
    );
  });

  it("el navegador no puede elegir la empresa: si reclama otra, no se canjea", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma);
    const { ticket } = await service.issueTicket({
      companyId: "company-a",
      userId: "user-1",
    });

    await expect(
      service.exchangeTicket({ ticket, companyIdFromClient: "company-b" }),
    ).rejects.toBeInstanceOf(ForbiddenException);
    // El ticket sigue sin consumir: el rechazo no gasta la capacidad.
    expect(prisma.__rows.tickets[0].usedAt).toBeNull();
  });

  it("aísla empresas: la sesión de A nunca devuelve datos de B", async () => {
    const prisma = makePrismaFake({
      dosaSessions: [
        {
          companyId: "company-b",
          rnc: "999999999",
          attemptNo: 7,
          status: "COMPLETED",
          providerPostulationId: "post-b",
          createdAt: new Date("2026-11-02T09:00:00Z"),
        },
        {
          companyId: "company-a",
          rnc: "000000001",
          attemptNo: 1,
          status: "NOT_STARTED",
          providerPostulationId: null,
          createdAt: new Date("2026-11-02T10:00:00Z"),
        },
      ],
    });
    const service = makeService(prisma);

    const a = await service.exchangeTicket({
      ticket: (await service.issueTicket({ companyId: "company-a", userId: "u" }))
        .ticket,
    });
    const b = await service.exchangeTicket({
      ticket: (await service.issueTicket({ companyId: "company-b", userId: "u" }))
        .ticket,
    });

    const ctxA = await service.readContext(a.token);
    const ctxB = await service.readContext(b.token);

    expect(ctxA.company.id).toBe("company-a");
    expect(ctxA.company.taxId).toBe("000000001");
    expect(ctxA.postulation?.attemptNo).toBe(1);

    expect(ctxB.company.id).toBe("company-b");
    expect(ctxB.company.taxId).toBe("999999999");
    expect(ctxB.postulation?.attemptNo).toBe(7);

    // Ninguno ve el RNC ni el intento del otro.
    expect(JSON.stringify(ctxA)).not.toContain("999999999");
    expect(JSON.stringify(ctxB)).not.toContain("000000001");
  });

  it("rechaza sesiones desconocidas, vencidas y revocadas", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma);

    await expect(service.readContext("token-inexistente-largo-123456")).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    await expect(service.readContext(null)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );

    const { token } = await service.exchangeTicket({
      ticket: (await service.issueTicket({ companyId: "company-a", userId: "u" }))
        .ticket,
    });

    prisma.__rows.sessions[0].expiresAt = new Date(Date.now() - 1);
    await expect(service.readContext(token)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );

    prisma.__rows.sessions[0].expiresAt = new Date(
      Date.now() + PORTAL_SESSION_TTL_SECONDS * 1000,
    );
    await service.revoke(token);
    await expect(service.readContext(token)).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
  });

  it("la sesión recuerda la empresa aunque el ticket desaparezca", async () => {
    const prisma = makePrismaFake();
    const service = makeService(prisma);
    const { token } = await service.exchangeTicket({
      ticket: (await service.issueTicket({ companyId: "company-a", userId: "u" }))
        .ticket,
    });

    prisma.__rows.tickets.length = 0; // simula limpieza de tickets viejos
    const ctx = await service.readContext(token);
    expect(ctx.company.id).toBe("company-a");
  });
});

describe("milestonesFor", () => {
  it("COMPLETED cierra la solicitud pero NO da por hecha la certificación", () => {
    const m = milestonesFor("COMPLETED");
    expect(m.application).toBe("done");
    expect(m.tests).toBe("pending");
    expect(m.certification).toBe("pending");
  });

  it("un intento en curso mantiene los hitos siguientes bloqueados", () => {
    for (const estado of ["RUNNING", "ATTENTION", "NOT_STARTED"]) {
      const m = milestonesFor(estado);
      expect(m.application).toBe("in_progress");
      expect(m.tests).toBe("locked");
      expect(m.certification).toBe("locked");
    }
  });

  it("un intento fallido se puede reintentar: vuelve a pendiente", () => {
    for (const estado of ["FAILED", "CANCELLED", "EXPIRED"]) {
      expect(milestonesFor(estado).application).toBe("pending");
    }
  });

  it("sin expediente no hay nada en curso", () => {
    const m = milestonesFor(null);
    expect(m).toEqual({
      application: "pending",
      tests: "locked",
      certification: "locked",
    });
  });
});
