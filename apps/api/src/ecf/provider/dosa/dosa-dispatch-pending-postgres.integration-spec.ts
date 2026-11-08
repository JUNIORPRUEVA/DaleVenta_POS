import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../../ecf-local-target";
import { PrismaService } from "../../../prisma/prisma.service";
import type { TenantUser } from "../../../auth/tenant-context";
import { EcfEmissionService } from "../../documents/ecf-emission.service";
import { DosaEmissionService } from "./dosa-emission.service";
import { DosaEmissionDispatchService } from "./dosa-emission-dispatch.service";
import { validE32Simple } from "../../fiscal-core/ecf-fixtures";

// Opt-in suite on the ephemeral test database. Lo que se prueba es la garantía
// de NO DUPLICAR: recuperar un comprobante pendiente es seguro precisamente
// porque el envío exige cero intentos previos. No hay red ni emisión real.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("recuperación de despachos pendientes (sin duplicados) on PostgreSQL", () => {
  let prisma: PrismaService;
  let service: DosaEmissionDispatchService;
  let userId: string;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_DISPATCH_PENDING_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    service = new DosaEmissionDispatchService(
      prisma,
      new DosaEmissionService(prisma),
      new EcfEmissionService(prisma),
    );
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-pending-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic Pending Dispatch User",
        telefono: "0000000000",
        edad: 30,
        role: "ADMIN",
      },
    });
  });

  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: userId } });
    await prisma?.$disconnect();
  });

  async function tenant() {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name: "Synthetic pending", slug: `ecf-pending-${companyId}` },
    });
    return { companyId, user: { id: userId, role: "ADMIN", companyId } as TenantUser };
  }

  /** Comprobante preparado con su resumen de emisión, sin ningún intento de envío. */
  async function preparedDocument(
    companyId: string,
    options: { withAttempt?: boolean; status?: string } = {},
  ) {
    const encf = `E32${String(Math.floor(Math.random() * 1e10)).padStart(10, "0")}`;
    const document = await prisma.ecfElectronicDocument.create({
      data: {
        companyId,
        documentType: "E32",
        status: options.status ?? "LOCAL_VALIDATED",
        idempotencyKey: `synthetic-pending-${randomUUID()}`,
        payloadFingerprint: "e".repeat(64),
        fiscalDocument: { ...validE32Simple } as never,
        payloadSummary: {
          type: "E32",
          emission: { encf, senderTaxId: "101000001", fingerprint: "f".repeat(64), payload: {} },
        } as never,
      },
    });
    if (options.withAttempt) {
      await prisma.ecfElectronicDocumentAttempt.create({
        data: {
          companyId,
          documentId: document.id,
          operation: "SEND_TO_PROVIDER",
          idempotencyKey: document.idempotencyKey,
          requestFingerprint: "f".repeat(64),
          statusBefore: "LOCAL_VALIDATED",
          statusAfter: "SEND_IN_PROGRESS",
          createdByUserId: userId,
        },
      });
    }
    return document;
  }

  it("lista un comprobante preparado que nunca se envió", async () => {
    const { companyId, user } = await tenant();
    const document = await preparedDocument(companyId);

    const pending = await service.pending(user);

    expect(pending.items.map((row) => row.id)).toEqual([document.id]);
  });

  it("NO lista un comprobante que ya tiene intento de envío", async () => {
    const { companyId, user } = await tenant();
    const sent = await preparedDocument(companyId, { withAttempt: true });
    const untouched = await preparedDocument(companyId);

    const pending = await service.pending(user);

    // El que ya salió queda fuera: reintentarlo duplicaría el comprobante.
    expect(pending.items.map((row) => row.id)).not.toContain(sent.id);
    expect(pending.items.map((row) => row.id)).toEqual([untouched.id]);
  });

  it("no ve los pendientes de otra empresa", async () => {
    const a = await tenant();
    const b = await tenant();
    await preparedDocument(a.companyId);

    expect((await service.pending(b.user)).items).toEqual([]);
  });

  it("dispatchPending no crea un segundo intento ni envío duplicado", async () => {
    const { companyId, user } = await tenant();
    const pendingDoc = await preparedDocument(companyId);
    const sentDoc = await preparedDocument(companyId, { withAttempt: true });

    const first = await service.dispatchPending(user);
    const second = await service.dispatchPending(user);

    // El documento pendiente se intentó recuperar; el que ya tenía intento
    // nunca entra en la lista, así que no puede volver a enviarse.
    expect(first.items.map((item) => item.documentId)).toEqual([pendingDoc.id]);
    expect(second.items.map((item) => item.documentId)).toEqual([pendingDoc.id]);
    expect(first.items.map((item) => item.documentId)).not.toContain(sentDoc.id);

    // Sin autorización fiscal no se llega a la red: cero intentos nuevos, y el
    // documento del segundo intento sigue sin intento previo (se reintenta sin
    // riesgo porque nunca salió).
    expect(
      await prisma.ecfElectronicDocumentAttempt.count({
        where: { companyId, operation: "SEND_TO_PROVIDER" },
      }),
    ).toBe(1);
    expect(
      await prisma.ecfElectronicDocumentAttempt.count({
        where: { companyId, documentId: pendingDoc.id, operation: "SEND_TO_PROVIDER" },
      }),
    ).toBe(0);
    // El estado no cambia: preparado y pendiente, nunca «enviado».
    expect(
      (await prisma.ecfElectronicDocument.findUniqueOrThrow({ where: { companyId_id: { companyId, id: pendingDoc.id } } })).status,
    ).toBe("LOCAL_VALIDATED");
  });

  it("un comprobante ya enviado nunca vuelve a la lista aunque su estado sea preparado", async () => {
    const { companyId, user } = await tenant();
    const document = await preparedDocument(companyId);
    // Se le marca un proveedor externo: señal de que el envío ocurrió.
    await prisma.ecfElectronicDocument.update({
      where: { companyId_id: { companyId, id: document.id } },
      data: { externalProviderId: "synthetic-provider-id" },
    });

    expect((await service.pending(user)).items).toEqual([]);
  });
});
