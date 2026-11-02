import { ConfigService } from "@nestjs/config";

import { EcfAlanubeCertificationClient } from "../alanube/certification/ecf-alanube-certification.client";
import type {
  AlanubeHttpTransport,
  AlanubeSafeRequest,
  AlanubeTransportResult,
} from "../alanube/alanube-safe-http.types";
import { EcfCertificationAttemptsService } from "./certification/ecf-certification-attempts.service";
import {
  EcfCertificationOrchestratorService,
  type EcfOrchestratorPrisma,
} from "./ecf-certification-orchestrator.service";

class _Transport implements AlanubeHttpTransport {
  readonly calls: AlanubeSafeRequest[] = [];
  constructor(private readonly reply: (request: AlanubeSafeRequest) => AlanubeTransportResult) {}
  async execute(request: AlanubeSafeRequest): Promise<AlanubeTransportResult> {
    this.calls.push(request);
    return this.reply(request);
  }
}

function ok(body: unknown): AlanubeTransportResult {
  return {
    ok: true,
    response: { statusCode: 200, headers: {}, body, requestId: "r" },
  };
}

function timeout(): AlanubeTransportResult {
  return { ok: false, errorCode: "TIMEOUT", safeMessage: "sin respuesta", requestId: "r" };
}

const config = {
  get: (key: string) =>
    ({
      ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
      ALANUBE_TIMEOUT_MS: "5000",
      ECF_CERTIFICATION_SIMULATED_TOKEN: "token-simulado",
      ECF_CERTIFICATION_SET_TESTS_ID: "set-123",
    })[key],
} as unknown as ConfigService;

function prismaWith(alanubeCompanyId: string | null): EcfOrchestratorPrisma {
  return {
    ecfCompanyConfiguration: {
      findUnique: async () => ({ alanubeCompanyId }),
    },
  };
}

/** Intentos sobre un doble con la clave única simulada. */
function attempts() {
  const rows: Record<string, unknown>[] = [];
  const prisma = {
    ecfCertificationAttempt: {
      findUnique: async ({ where }: { where: { companyId_idempotencyKey: { companyId: string; idempotencyKey: string } } }) =>
        (rows.find(
          (row) =>
            row.idempotencyKey === where.companyId_idempotencyKey.idempotencyKey &&
            row.companyId === where.companyId_idempotencyKey.companyId,
        ) as never) ?? null,
      create: async ({ data }: { data: Record<string, unknown> }) => {
        const row = {
          id: `a${rows.length + 1}`,
          createdAt: new Date(),
          externalId: null,
          errorCode: null,
          ...data,
        };
        rows.push(row);
        return row as never;
      },
      update: async ({ where, data }: { where: { id: string }; data: Record<string, unknown> }) => {
        const row = rows.find((item) => item.id === where.id);
        if (!row) throw new Error("not found");
        Object.assign(row, data);
        return row as never;
      },
      findFirst: async ({
        where,
      }: {
        where: { companyId: string; operation: string; status: string };
      }) => {
        const matches = rows.filter(
          (row) =>
            row.companyId === where.companyId &&
            row.operation === where.operation &&
            row.status === where.status &&
            typeof row.externalId === "string",
        );
        const last = matches[matches.length - 1];
        return last ? ({ id: last.id, externalId: last.externalId } as never) : null;
      },
    },
  };
  return { service: new EcfCertificationAttemptsService(prisma as never), rows };
}

function orchestrator(
  transport: AlanubeHttpTransport,
  alanubeCompanyId: string | null = "company-1",
) {
  const attemptsDouble = attempts();
  const client = new EcfAlanubeCertificationClient(config, transport);
  return {
    service: new EcfCertificationOrchestratorService(
      config,
      client,
      attemptsDouble.service,
      prismaWith(alanubeCompanyId),
    ),
    attempts: attemptsDouble.rows,
  };
}

const input = { companyId: "c-uuid", stepKey: "SET_TESTS", actorUserId: "u1" };

describe("orquestador — sin asociación no se inventa nada", () => {
  it("bloquea con explicación y no llama al proveedor", async () => {
    const transport = new _Transport(() => ok({ id: "x" }));
    const { service } = orchestrator(transport, null);
    const outcome = await service.runProviderStep(input);
    expect(outcome.ok).toBe(false);
    expect(outcome.errorCode).toBe("ECF_CERTIFICATION_NO_COMPANY_ASSOCIATION");
    expect(outcome.blockedReason).toContain("custodia");
    expect(transport.calls).toHaveLength(0);
  });

  it("el XML de postulación no se inventa: queda como acción pendiente", async () => {
    const transport = new _Transport(() => ok({}));
    const { service } = orchestrator(transport);
    const outcome = await service.runProviderStep({
      ...input,
      stepKey: "XML_SIGNATURE",
    });
    expect(outcome.ok).toBe(false);
    expect(outcome.errorCode).toBe("ECF_CERTIFICATION_XML_NOT_AVAILABLE");
    expect(transport.calls).toHaveLength(0);
  });
});

describe("orquestador — ejecución simulada y sin duplicados", () => {
  it("genera el set de pruebas y no lo repite en la segunda llamada", async () => {
    const transport = new _Transport(() =>
      ok({ id: "set-abc", mark: "SIMULATED_NOT_OFFICIAL" }),
    );
    const { service, attempts: rows } = orchestrator(transport);

    const first = await service.runProviderStep(input);
    expect(first.ok).toBe(true);
    expect(first.simulated).toBe(true);
    expect(first.summary).toContain("set-abc");
    expect(transport.calls).toHaveLength(1);
    expect(rows).toHaveLength(1);
    expect(rows[0].status).toBe("SUCCEEDED");

    const second = await service.runProviderStep(input);
    expect(second.ok).toBe(true);
    expect(second.summary).toContain("Ya estaba completado");
    // Nunca se reenvía una operación ya aplicada.
    expect(transport.calls).toHaveLength(1);
  });

  it("un timeout deja el intento incierto y el siguiente intento NO reenvía", async () => {
    const transport = new _Transport(() => timeout());
    const { service, attempts: rows } = orchestrator(transport);

    const first = await service.runProviderStep(input);
    expect(first.ok).toBe(false);
    expect(first.summary).toBe("RESULTADO_INCIERTO");
    expect(rows[0].status).toBe("IN_PROGRESS");
    expect(rows[0].errorCode).toBe("ECF_PROVIDER_RESULT_UNKNOWN");

    const second = await service.runProviderStep(input);
    expect(second.ok).toBe(false);
    expect(second.errorCode).toBe("ECF_PROVIDER_RESULT_UNKNOWN");
    expect(second.blockedReason).toContain("reconciliar");
    // El transporte solo se llamó una vez: no hubo segundo envío.
    expect(transport.calls).toHaveLength(1);
  });

  it("la consulta del set usa el ID REAL persistido de la creación", async () => {
    const transport = new _Transport((request) =>
      request.method === "POST"
        ? ok({ id: "set-xyz" })
        : ok({ status: "IN_REVIEW" }),
    );
    const { service } = orchestrator(transport);

    const created = await service.runProviderStep(input);
    expect(created.ok).toBe(true);

    const status = await service.runProviderStep({
      ...input,
      stepKey: "SIMULATIONS",
    });
    expect(status.ok).toBe(true);
    expect(transport.calls[1].url).toBe(
      "https://sandbox.alanube.co/dom/v1/check-set-tests/set-xyz/idCompany/company-1",
    );
  });

  it("sin set creado, la consulta se detiene y no inventa un id", async () => {
    const transport = new _Transport(() => ok({ status: "IN_REVIEW" }));
    const { service } = orchestrator(transport);
    const outcome = await service.runProviderStep({
      ...input,
      stepKey: "SIMULATIONS",
    });
    expect(outcome.ok).toBe(false);
    expect(outcome.errorCode).toBe("ECF_CERTIFICATION_SET_TESTS_ID_MISSING");
    expect(transport.calls).toHaveLength(0);
  });

  it("una creación sin identificador deja la consulta bloqueada", async () => {
    const transport = new _Transport(() => ok({ id: null }));
    const { service, attempts: rows } = orchestrator(transport);
    const created = await service.runProviderStep(input);
    expect(created.ok).toBe(true);
    expect(rows[0].externalId).toBeNull();

    const status = await service.runProviderStep({
      ...input,
      stepKey: "SIMULATIONS",
    });
    expect(status.ok).toBe(false);
    expect(status.errorCode).toBe("ECF_CERTIFICATION_SET_TESTS_ID_MISSING");
    expect(transport.calls).toHaveLength(1);
  });

  it("un set de otra empresa no se usa como propio", async () => {
    const transport = new _Transport((request) =>
      request.method === "POST"
        ? ok({ id: "set-de-empresa-A" })
        : ok({ status: "IN_REVIEW" }),
    );
    const { service } = orchestrator(transport);
    await service.runProviderStep(input);
    // Otra empresa no hereda el set de la primera: se detiene sin consultar.
    const other = await service.runProviderStep({
      ...input,
      companyId: "empresa-B",
      stepKey: "SIMULATIONS",
    });
    expect(other.ok).toBe(false);
    expect(other.errorCode).toBe("ECF_CERTIFICATION_SET_TESTS_ID_MISSING");
  });

  it("la asociación existente se consulta sin enviar nada nuevo", async () => {
    const transport = new _Transport(() =>
      ok({ id: "company-1", name: "Empresa Demo", companyUrls: {} }),
    );
    const { service } = orchestrator(transport);
    const outcome = await service.runProviderStep({
      ...input,
      stepKey: "ALANUBE_REGISTRATION",
    });
    expect(outcome.ok).toBe(true);
    expect(transport.calls[0].method).toBe("GET");
    expect(transport.calls[0].url).toContain("/company/company-1");
  });

  it("cada empresa tiene su propio intento", async () => {
    const transport = new _Transport(() => ok({ id: "set-abc" }));
    const { service, attempts: rows } = orchestrator(transport);
    await service.runProviderStep(input);
    await service.runProviderStep({ ...input, companyId: "otra-empresa" });
    expect(rows).toHaveLength(2);
    expect(transport.calls).toHaveLength(2);
  });
});
