import { DOSA_INCIDENT_STATUS } from "./dosa-incident.policy";
import {
  DosaIncidentService,
  type DosaIncidentRetryRunner,
} from "./dosa-incident.service";

/**
 * Doble de Prisma.
 *
 * Solo implementa lo que el servicio usa. `$queryRaw` se resuelve por orden de
 * llamada (las cinco detecciones del barrido), que es el único orden que el
 * servicio puede producir.
 */
function buildPrisma(options: {
  detections?: unknown[][];
  openCompanies?: string[];
  openRowsByCompany?: Record<string, unknown[]>;
  attempts?: number;
  /** `false` simula que otra instancia reclamó el intento. */
  claim?: boolean;
} = {}) {
  const detections = [...(options.detections ?? [[], [], [], [], []])];
  const openRows = options.openRowsByCompany ?? {};

  const incidents = {
    findMany: jest.fn(async (args: { distinct?: unknown[]; where?: { companyId?: unknown } }) => {
      if (args.distinct) {
        return (options.openCompanies ?? []).map((companyId) => ({ companyId }));
      }
      const companyId = typeof args.where?.companyId === "string" ? args.where.companyId : "";
      return openRows[companyId] ?? [];
    }),
    upsert: jest.fn(async () => ({})),
    updateMany: jest.fn(async () => ({ count: 1 })),
    findFirst: jest.fn(async () => ({ attempts: options.attempts ?? 0 })),
    count: jest.fn(async () => 0),
  };

  const prisma = {
    $queryRaw: jest.fn(
      async (
        strings: TemplateStringsArray,
        ..._values: unknown[]
      ): Promise<unknown[]> => {
        // El reclamo del intento usa UPDATE ... RETURNING; las detecciones son
        // SELECT. Se distinguen por el texto de la consulta, no por el orden,
        // para que el doble no dependa de cuántas detecciones haya.
        const sql = strings.join(" ");
        if (sql.includes('RETURNING "attempts"')) {
          return options.claim === false
            ? []
            : [{ attempts: (options.attempts ?? 0) + 1 }];
        }
        return detections.shift() ?? [];
      },
    ),
    $transaction: jest.fn(async (operations: Promise<unknown>[]) =>
      Promise.all(operations),
    ),
    ecfDosaIncident: incidents,
  };

  return { prisma, incidents };
}

function detection(overrides: Record<string, unknown> = {}) {
  return {
    company_id: "company-a",
    rnc: "133080206",
    subject_ref: "post-1",
    total: "1",
    ...overrides,
  };
}

describe("DosaIncidentService — detección y registro", () => {
  it("sin condiciones no escribe nada", async () => {
    const { prisma, incidents } = buildPrisma();
    const service = new DosaIncidentService(prisma as never);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.created).toBe(0);
    expect(incidents.upsert).not.toHaveBeenCalled();
    expect(incidents.updateMany).not.toHaveBeenCalled();
  });

  it("un evento con credenciales sin guardar crea una incidencia ALTA", async () => {
    const { prisma, incidents } = buildPrisma({
      detections: [[detection()], [], [], [], []],
    });
    const service = new DosaIncidentService(prisma as never);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.created).toBe(1);
    const call = incidents.upsert.mock.calls[0][0] as {
      where: { companyId_incidentKey: { companyId: string; incidentKey: string } };
      create: { severity: string; kind: string; status: string; companyId: string };
    };
    expect(call.where.companyId_incidentKey.companyId).toBe("company-a");
    expect(call.create.kind).toBe("EVENT_CREDENTIALS_NOT_STORED");
    expect(call.create.severity).toBe("ALTA");
    expect(call.create.status).toBe(DOSA_INCIDENT_STATUS.OPEN);
    // Nunca se escribe nada en las tablas de credenciales.
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(5);
  });

  it("dos empresas producen dos incidencias aisladas", async () => {
    const { prisma, incidents } = buildPrisma({
      detections: [
        [
          detection({ company_id: "company-a", subject_ref: "post-a" }),
          detection({ company_id: "company-b", rnc: "130000002", subject_ref: "post-b" }),
        ],
        [],
        [],
        [],
        [],
      ],
    });
    const service = new DosaIncidentService(prisma as never);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.created).toBe(2);
    const companies = incidents.upsert.mock.calls.map(
      (call) =>
        (call[0] as { create: { companyId: string } }).create.companyId,
    );
    expect(companies.sort()).toEqual(["company-a", "company-b"]);
  });

  it("una condición que ya no existe se resuelve", async () => {
    const { prisma, incidents } = buildPrisma({
      openCompanies: ["company-a"],
      openRowsByCompany: {
        "company-a": [
          {
            id: "inc-1",
            incidentKey: "EVENT_CREDENTIALS_NOT_STORED:post-1",
            kind: "EVENT_CREDENTIALS_NOT_STORED",
            status: DOSA_INCIDENT_STATUS.OPEN,
            attempts: 0,
            nextAttemptAt: null,
          },
        ],
      },
    });
    const service = new DosaIncidentService(prisma as never);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.resolved).toBe(1);
    const data = (incidents.updateMany.mock.calls[0][0] as { data: { status: string } }).data;
    expect(data.status).toBe(DOSA_INCIDENT_STATUS.RESOLVED);
  });

  it("el fallo de una empresa no impide procesar las demás", async () => {
    const { prisma, incidents } = buildPrisma({
      detections: [
        [
          detection({ company_id: "company-a" }),
          detection({ company_id: "company-b", subject_ref: "post-b" }),
        ],
        [],
        [],
        [],
        [],
      ],
    });
    // La primera escritura revienta; la segunda debe ejecutarse igual.
    incidents.upsert.mockRejectedValueOnce(new Error("fallo simulado"));
    const service = new DosaIncidentService(prisma as never);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.errors).toBe(1);
    expect(summary.created).toBe(1);
    expect(incidents.upsert).toHaveBeenCalledTimes(2);
  });
});

describe("DosaIncidentService — reintento seguro", () => {
  const unboundRow = {
    id: "inc-1",
    incidentKey: "POSTULATION_NOT_BOUND:post-1",
    kind: "POSTULATION_NOT_BOUND",
    status: DOSA_INCIDENT_STATUS.OPEN,
    attempts: 0,
    nextAttemptAt: null,
  };

  function buildRunner(ok: boolean): jest.Mocked<DosaIncidentRetryRunner> {
    return {
      retryBinding: jest.fn(async () => (ok ? { ok: true } : { ok: false, errorCode: "BINDING_NOT_APPLICABLE" })),
    };
  }

  it("reintenta la vinculación y resuelve si funciona", async () => {
    const { prisma, incidents } = buildPrisma({
      detections: [
        [],
        [],
        [],
        [detection()],
        [],
      ],
      openCompanies: ["company-a"],
      openRowsByCompany: { "company-a": [unboundRow] },
    });
    const runner = buildRunner(true);
    const service = new DosaIncidentService(prisma as never, runner);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.retried).toBe(1);
    expect(summary.retrySucceeded).toBe(1);
    expect(runner.retryBinding).toHaveBeenCalledWith({
      companyId: "company-a",
      rnc: "133080206",
      providerPostulationId: "post-1",
    });
    const data = (incidents.updateMany.mock.calls[0][0] as {
      data: { status: string; attempts?: number };
    }).data;
    expect(data.status).toBe(DOSA_INCIDENT_STATUS.RESOLVED);
    // `attempts` lo incrementa el reclamo atómico, no el cierre: escribirlo otra
    // vez desde aquí fue justo lo que permitía contarlo dos veces con varias
    // réplicas.
    expect(data.attempts).toBeUndefined();
  });

  it("si otra instancia reclama el intento, no se ejecuta dos veces", async () => {
    const { prisma, incidents } = buildPrisma({
      detections: [[], [], [], [detection()], []],
      openCompanies: ["company-a"],
      openRowsByCompany: { "company-a": [unboundRow] },
      // El reclamo devuelve 0 filas: otra réplica se lo llevó.
      claim: false,
    });
    const runner = buildRunner(true);
    const service = new DosaIncidentService(prisma as never, runner);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.retried).toBe(1);
    expect(summary.retrySucceeded).toBe(0);
    expect(runner.retryBinding).not.toHaveBeenCalled();
    // Y no se toca el estado de la incidencia: la resolvió quien ganó el reclamo.
    expect(incidents.updateMany).not.toHaveBeenCalled();
  });

  it("si el reintento falla, agenda el siguiente y no escala de inmediato", async () => {
    const { prisma, incidents } = buildPrisma({
      detections: [[], [], [], [detection()], []],
      openCompanies: ["company-a"],
      openRowsByCompany: { "company-a": [unboundRow] },
    });
    const runner = buildRunner(false);
    const service = new DosaIncidentService(prisma as never, runner);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.retried).toBe(1);
    expect(summary.retrySucceeded).toBe(0);
    const data = (incidents.updateMany.mock.calls[0][0] as {
      data: { status: string; nextAttemptAt: Date | null; lastErrorCode: string };
    }).data;
    expect(data.status).toBe(DOSA_INCIDENT_STATUS.OPEN);
    expect(data.nextAttemptAt).toBeInstanceOf(Date);
    expect(data.lastErrorCode).toBe("BINDING_NOT_APPLICABLE");
  });

  it("sin ejecutor configurado no inventa un éxito", async () => {
    const { prisma, incidents } = buildPrisma({
      detections: [[], [], [], [detection()], []],
      openCompanies: ["company-a"],
      openRowsByCompany: { "company-a": [unboundRow] },
    });
    const service = new DosaIncidentService(prisma as never);

    const summary = await service.scan({ now: new Date("2026-11-07T12:00:00Z") });

    expect(summary.retrySucceeded).toBe(0);
    const data = (incidents.updateMany.mock.calls[0][0] as {
      data: { lastErrorCode: string };
    }).data;
    expect(data.lastErrorCode).toBe("RETRY_RUNNER_NOT_CONFIGURED");
  });
});

describe("DosaIncidentService — administración", () => {
  it("sin empresas autorizadas no consulta nada", async () => {
    const { prisma, incidents } = buildPrisma();
    const service = new DosaIncidentService(prisma as never);

    const result = await service.list({ companyIds: [] });

    expect(result).toEqual({ total: 0, items: [] });
    expect(incidents.findMany).not.toHaveBeenCalled();
  });

  it("rechaza un motivo de cierre fuera del catálogo", async () => {
    const { prisma, incidents } = buildPrisma();
    const service = new DosaIncidentService(prisma as never);

    const result = await service.close({
      incidentId: "inc-1",
      companyId: "company-a",
      resolution: "me lo pidió el cliente",
      actorUserId: "user-1",
    });

    expect(result).toEqual({ ok: false, blockedReason: "RESOLUTION_NOT_ALLOWED" });
    expect(incidents.updateMany).not.toHaveBeenCalled();
  });

  it("cierra con el motivo del catálogo y deja autor y fecha", async () => {
    const { prisma, incidents } = buildPrisma();
    const service = new DosaIncidentService(prisma as never);

    const result = await service.close({
      incidentId: "inc-1",
      companyId: "company-a",
      resolution: "FALSE_POSITIVE",
      actorUserId: "user-1",
    });

    expect(result).toEqual({ ok: true });
    const call = incidents.updateMany.mock.calls[0][0] as {
      where: { id: string; companyId: string };
      data: { resolution: string; resolvedByUserId: string; status: string };
    };
    expect(call.where).toMatchObject({ id: "inc-1", companyId: "company-a" });
    expect(call.data.resolution).toBe("FALSE_POSITIVE");
    expect(call.data.resolvedByUserId).toBe("user-1");
    expect(call.data.status).toBe(DOSA_INCIDENT_STATUS.CLOSED);
  });

  it("no puede cerrar una incidencia de otra empresa", async () => {
    const { prisma, incidents } = buildPrisma();
    incidents.updateMany.mockResolvedValueOnce({ count: 0 });
    const service = new DosaIncidentService(prisma as never);

    const result = await service.close({
      incidentId: "inc-1",
      companyId: "company-b",
      resolution: "FALSE_POSITIVE",
      actorUserId: "user-1",
    });

    expect(result).toEqual({ ok: false, blockedReason: "INCIDENT_NOT_OPEN" });
  });
});
