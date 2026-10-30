import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { validE31WithItbis } from "../fiscal-core/ecf-fixtures";
import { EcfEmissionService } from "./ecf-emission.service";
import { EcfSimulatedDispatchService } from "./ecf-simulated-dispatch.service";

// Opt-in suite against an authorized LOCAL target only.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

function configWith(values: Record<string, string>): ConfigService {
  return { get: (key: string) => values[key] } as unknown as ConfigService;
}

const LOCAL_UAT = configWith({
  APP_ENV: "uat",
  UAT_LOCAL_ONLY: "true",
  ALANUBE_ENABLE_REAL_CALLS: "false",
  ALANUBE_HTTP_TRANSPORT_ENABLED: "false",
});

/**
 * CONCURRENCIA REAL sobre PostgreSQL.
 *
 * Las solicitudes se lanzan a la vez (`Promise.allSettled`) para que compitan de
 * verdad por la fila: no es una ejecución secuencial disfrazada. Lo que se mide
 * es el efecto observable —intentos de envío, recibos de evidencia y estado—
 * porque el modelo conserva legítimamente un historial de intentos.
 */
uat("E-CF simulated dispatch — real concurrency", () => {
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
      throw new Error("ECF_CONCURRENCY_UAT_REFUSED");
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
      data: { id: companyId, name, slug: `ecf-conc-${companyId}` },
    });
    return {
      companyId,
      user: { id: actor, role: "ADMIN", companyId } as TenantUser,
    };
  }

  async function prepared(user: TenantUser) {
    return emission.prepare(user, {
      document: validE31WithItbis,
      metadata: {
        encf: nextEncf(),
        sequenceDueDate: "2026-12-31",
        incomeType: 1,
        paymentType: 1,
      },
      clientRequestId: randomUUID(),
    });
  }

  const sendAttempts = (companyId: string, documentId: string) =>
    prisma.ecfElectronicDocumentAttempt.count({
      where: { companyId, documentId, operation: "SEND_TO_PROVIDER" },
    });
  const receipts = (companyId: string, documentId: string) =>
    prisma.ecfEvidenceReceipt.count({ where: { companyId, documentId } });
  const stored = (companyId: string, id: string) =>
    prisma.ecfElectronicDocument.findFirstOrThrow({ where: { companyId, id } });

  it("dos despachos SIMULTÁNEOS del mismo comprobante: solo uno gana", async () => {
    const { companyId, user } = await tenant("Synthetic concurrent same doc");
    const document = await prepared(user);

    const results = await Promise.allSettled([
      service.dispatch(user, document.id, "PROVIDER_ACCEPTED"),
      service.dispatch(user, document.id, "PROVIDER_ACCEPTED"),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");

    expect(fulfilled).toHaveLength(1);
    expect(rejected).toHaveLength(1);

    // El perdedor no puede haber enviado nada: un solo intento de envío.
    expect(await sendAttempts(companyId, document.id)).toBe(1);
    // Y un solo recibo de evidencia: no se duplica la prueba fiscal.
    expect(await receipts(companyId, document.id)).toBe(1);

    const row = await stored(companyId, document.id);
    expect(row.status).toBe("HUMAN_REVIEW_REQUIRED");
    // Nunca aceptación fiscal, ni siquiera cuando el ganador correlacionó.
    expect(
      await prisma.ecfElectronicDocument.count({
        where: {
          companyId,
          status: { in: ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] },
        },
      }),
    ).toBe(0);
  });

  it("dos empresas distintas despachando a la vez quedan aisladas", async () => {
    const a = await tenant("Synthetic concurrent A");
    const b = await tenant("Synthetic concurrent B");
    const documentA = await prepared(a.user);
    const documentB = await prepared(b.user);

    const results = await Promise.allSettled([
      service.dispatch(a.user, documentA.id, "PROVIDER_ACCEPTED"),
      service.dispatch(b.user, documentB.id, "PROVIDER_ACCEPTED"),
    ]);

    expect(results.every((r) => r.status === "fulfilled")).toBe(true);
    expect(await sendAttempts(a.companyId, documentA.id)).toBe(1);
    expect(await sendAttempts(b.companyId, documentB.id)).toBe(1);
    // Ninguna empresa ve el comprobante de la otra.
    expect(
      await prisma.ecfElectronicDocument.count({
        where: { companyId: a.companyId, id: documentB.id },
      }),
    ).toBe(0);
    expect(
      await prisma.ecfElectronicDocument.count({
        where: { companyId: b.companyId, id: documentA.id },
      }),
    ).toBe(0);
  });

  it("un timeout no habilita una segunda emisión: el reintento se rechaza", async () => {
    const { companyId, user } = await tenant("Synthetic concurrent retry");
    const document = await prepared(user);

    const first = await service.dispatch(user, document.id, "TIMEOUT");
    expect(first.correlated).toBe(false);
    expect(await sendAttempts(companyId, document.id)).toBe(1);

    // Reintento tras un resultado desconocido: se rechaza. Nunca un segundo POST.
    await expect(
      service.dispatch(user, document.id, "PROVIDER_ACCEPTED"),
    ).rejects.toThrow(/ECF_EMISSION/);

    expect(await sendAttempts(companyId, document.id)).toBe(1);
    expect(await receipts(companyId, document.id)).toBe(0);
    expect((await stored(companyId, document.id)).status).not.toBe(
      "DGII_ACCEPTED",
    );
  });

  it("N despachos simultáneos sobre el mismo comprobante: sigue habiendo uno", async () => {
    const { companyId, user } = await tenant("Synthetic concurrent N");
    const document = await prepared(user);

    const results = await Promise.allSettled(
      Array.from({ length: 5 }, () =>
        service.dispatch(user, document.id, "PROVIDER_ACCEPTED"),
      ),
    );

    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(await sendAttempts(companyId, document.id)).toBe(1);
    expect(await receipts(companyId, document.id)).toBe(1);
  });
});
