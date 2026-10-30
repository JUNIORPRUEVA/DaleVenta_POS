import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";
import { EcfEmissionService } from "./ecf-emission.service";
import { EcfSimulatedDispatchService } from "./ecf-simulated-dispatch.service";

// Opt-in suite. Runs ONLY against an authorized local target (ephemeral test or
// historical UAT database) and uses the SIMULATED provider: no real Alanube call,
// no real fiscal sequence, no DGII contact.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

/** Config fija para que la prueba no dependa del entorno ambiente. */
function configWith(values: Record<string, string>): ConfigService {
  return { get: (key: string) => values[key] } as unknown as ConfigService;
}

const LOCAL_UAT = configWith({
  APP_ENV: "uat",
  UAT_LOCAL_ONLY: "true",
  ALANUBE_ENABLE_REAL_CALLS: "false",
  ALANUBE_HTTP_TRANSPORT_ENABLED: "false",
});

uat("E-CF simulated dispatch — end to end (HTTP-reachable path)", () => {
  let prisma: PrismaService;
  let emission: EcfEmissionService;
  let service: EcfSimulatedDispatchService;
  const actor = randomUUID();
  let sequence = 0;
  const nextEncf = () => `E31${String(++sequence).padStart(10, "0")}`;

  beforeAll(async () => {
    if (
      !isEcfLocalTarget() ||
      process.env.ALANUBE_ENABLE_REAL_CALLS !== "false" ||
      process.env.ECF_EMISSION_ENABLED === "true"
    ) {
      throw new Error("ECF_SIMULATED_DISPATCH_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    emission = new EcfEmissionService(prisma);
    service = new EcfSimulatedDispatchService(LOCAL_UAT, emission);
  });
  afterAll(async () => {
    await prisma?.$disconnect();
  });

  async function tenant(name: string) {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name, slug: `ecf-sim-${companyId}` },
    });
    return {
      companyId,
      user: { id: actor, role: "ADMIN", companyId } as TenantUser,
    };
  }

  async function prepared(user: TenantUser) {
    const encf = nextEncf();
    const document = await emission.prepare(user, {
      document: validE31WithItbis,
      metadata: {
        encf,
        sequenceDueDate: "2026-12-31",
        incomeType: 1,
        paymentType: 1,
      },
      clientRequestId: randomUUID(),
    });
    return { encf, document };
  }

  const stored = (companyId: string, id: string) =>
    prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id } });
  const acceptedCount = (companyId: string) =>
    prisma.ecfElectronicDocument.count({
      where: {
        companyId,
        status: { in: ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] },
      },
    });
  const receipts = (companyId: string, documentId: string) =>
    prisma.ecfEvidenceReceipt.count({ where: { companyId, documentId } });

  it("aceptación simulada del proveedor: correlaciona, persiste y NO es aceptación fiscal", async () => {
    const { companyId, user } = await tenant("Synthetic simulated acceptance");
    const { encf, document } = await prepared(user);
    expect(document).toMatchObject({ documentType: "E31", status: "LOCAL_VALIDATED" });

    const outcome = await service.dispatch(user, document.id, "PROVIDER_ACCEPTED");

    expect(outcome).toMatchObject({
      simulated: true,
      officialFiscalAcceptance: false,
      scenario: "PROVIDER_ACCEPTED",
      correlated: true,
      documentType: "E31",
    });
    expect(outcome.observation.providerOutcome).toBe("ACCEPTED");

    const row = await stored(companyId, document.id);
    expect(row.status).toBe("HUMAN_REVIEW_REQUIRED");
    expect(row.externalDocumentNumber).toBe(encf);
    expect(row.externalProviderId).toBeTruthy();
    expect(await receipts(companyId, document.id)).toBe(1);
    // La regla de oro: un 2xx simulado NUNCA produce aceptación fiscal.
    expect(await acceptedCount(companyId)).toBe(0);
  });

  it("rechazo simulado del proveedor: se registra para revisión sin aceptación", async () => {
    const { companyId, user } = await tenant("Synthetic simulated rejection");
    const { document } = await prepared(user);

    const outcome = await service.dispatch(user, document.id, "PROVIDER_REJECTED");

    expect(outcome.correlated).toBe(true);
    expect(outcome.observation.providerOutcome).toBe("REJECTED");
    const row = await stored(companyId, document.id);
    expect(row.status).toBe("HUMAN_REVIEW_REQUIRED");
    expect(row.safeErrorCode).toBe("ECF_OBSERVED_REJECTED");
    expect(await acceptedCount(companyId)).toBe(0);
  });

  it("respuesta pendiente: queda en revisión sin consumir aceptación", async () => {
    const { companyId, user } = await tenant("Synthetic simulated pending");
    const { document } = await prepared(user);

    const outcome = await service.dispatch(user, document.id, "PENDING_RECOVERY");

    expect(outcome.observation.providerOutcome).toBe("PENDING");
    expect((await stored(companyId, document.id)).status).toBe(
      "HUMAN_REVIEW_REQUIRED",
    );
    expect(await acceptedCount(companyId)).toBe(0);
  });

  it("timeout: resultado desconocido, sin evidencia inventada ni aceptación", async () => {
    const { companyId, user } = await tenant("Synthetic simulated timeout");
    const { document } = await prepared(user);

    const outcome = await service.dispatch(user, document.id, "TIMEOUT");

    expect(outcome.correlated).toBe(false);
    expect(outcome.httpStatus).toBeNull();
    const row = await stored(companyId, document.id);
    expect(row.status).not.toBe("DGII_ACCEPTED");
    expect(await receipts(companyId, document.id)).toBe(0);
    expect(await acceptedCount(companyId)).toBe(0);
  });

  it("cuerpo malformado: falla cerrado y no correlaciona", async () => {
    const { companyId, user } = await tenant("Synthetic malformed");
    const { document } = await prepared(user);

    const outcome = await service.dispatch(user, document.id, "MALFORMED_RESPONSE");

    expect(outcome.correlated).toBe(false);
    expect(await receipts(companyId, document.id)).toBe(0);
    expect(await acceptedCount(companyId)).toBe(0);
  });

  it("segundo despacho del mismo comprobante: se rechaza (idempotencia)", async () => {
    const { user } = await tenant("Synthetic duplicate dispatch");
    const { document } = await prepared(user);

    await service.dispatch(user, document.id, "PROVIDER_ACCEPTED");

    await expect(
      service.dispatch(user, document.id, "PROVIDER_ACCEPTED"),
    ).rejects.toThrow(/ECF_EMISSION/);
  });

  it("se niega si el transporte real estaría activo y no toca el documento", async () => {
    const { companyId, user } = await tenant("Synthetic real transport refused");
    const { document } = await prepared(user);
    const realSelected = new EcfSimulatedDispatchService(
      configWith({
        APP_ENV: "uat",
        UAT_LOCAL_ONLY: "true",
        ALANUBE_ENABLE_REAL_CALLS: "true",
        ALANUBE_HTTP_TRANSPORT_ENABLED: "true",
        ALANUBE_ENV: "sandbox",
        // Configuración de sandbox COMPLETA: es lo que hace que el transporte
        // real esté realmente seleccionado (si faltara el token, la fábrica se
        // quedaría en el simulador y este caso no probaría nada).
        ALANUBE_BASE_URL: "https://sandbox.alanube.co/dom/v1",
        ALANUBE_TOKEN_SECRET_REF: "secret://alanube/sandbox-token",
      }),
      emission,
    );

    await expect(
      realSelected.dispatch(user, document.id, "PROVIDER_ACCEPTED"),
    ).rejects.toThrow(/ECF_SIMULATED_DISPATCH_REFUSED_REAL_TRANSPORT/);

    const row = await stored(companyId, document.id);
    expect(row.status).toBe("LOCAL_VALIDATED");
    // Ningún intento de ENVÍO: la negativa ocurre antes de tocar nada. (Preparar
    // sí registra su propio intento, que no es un envío al proveedor.)
    expect(
      await prisma.ecfElectronicDocumentAttempt.count({
        where: { companyId, documentId: document.id, operation: "SEND_TO_PROVIDER" },
      }),
    ).toBe(0);
  });

  it("se niega fuera de una UAT local", async () => {
    const { companyId, user } = await tenant("Synthetic non-uat refused");
    const { document } = await prepared(user);
    // Entorno NO local explícito: producción y sin marca de UAT local.
    const production = new EcfSimulatedDispatchService(
      configWith({
        APP_ENV: "production",
        UAT_LOCAL_ONLY: "false",
        ALANUBE_ENABLE_REAL_CALLS: "false",
        ALANUBE_HTTP_TRANSPORT_ENABLED: "false",
      }),
      emission,
    );

    await expect(
      production.dispatch(user, document.id, "PROVIDER_ACCEPTED"),
    ).rejects.toThrow(/ECF_SIMULATED_DISPATCH_REFUSED_NOT_LOCAL_UAT/);

    expect((await stored(companyId, document.id)).status).toBe("LOCAL_VALIDATED");
  });

  it("aislamiento: otra empresa no puede despachar el comprobante ajeno", async () => {
    const a = await tenant("Synthetic isolation A");
    const b = await tenant("Synthetic isolation B");
    const { document } = await prepared(a.user);

    await expect(
      service.dispatch(b.user, document.id, "PROVIDER_ACCEPTED"),
    ).rejects.toThrow(/ECF_EMISSION_DOCUMENT_NOT_FOUND/);

    expect((await stored(a.companyId, document.id)).status).toBe(
      "LOCAL_VALIDATED",
    );
  });
});
