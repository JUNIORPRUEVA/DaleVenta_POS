import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf/ecf-local-target";
import { PrismaService } from "../prisma/prisma.service";
import type { TenantUser } from "../auth/tenant-context";
import { EcfSequenceService } from "../ecf/documents/ecf-sequence.service";
import { SalesService } from "./sales.service";

// Suite opt-in sobre la base efímera. Comprueba el cableado REAL entre la
// devolución de una venta y la nota de crédito E34: reserva de numeración,
// reserva de crédito fiscal, idempotencia y ausencia total de emisión.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

/** Doble tolerante: cualquier método del colaborador existe y no hace nada. */
const inert = () =>
  new Proxy({}, { get: () => () => undefined }) as never;

uat("devolución de venta con comprobante E31 aceptado (E34) on PostgreSQL", () => {
  let prisma: PrismaService;
  let sales: SalesService;
  let userId: string;
  let unitId: string;

  beforeAll(async () => {
    if (
      !isEcfLocalTarget() ||
      process.env.ALANUBE_ENABLE_REAL_CALLS !== "false"
    ) {
      throw new Error("ECF_SALE_RETURN_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    sales = new SalesService(prisma, inert(), inert(), inert());
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-return-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic Return User",
        telefono: "0000000000",
        edad: 30,
        role: "ADMIN",
      },
    });
    unitId = `UNIT_${randomUUID().slice(0, 8)}`;
    await prisma.unitOfMeasure.create({
      data: {
        id: unitId,
        code: unitId,
        name: "Unidad",
        symbol: "u",
        category: "COUNT",
      },
    });
  });

  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: userId } });
    await prisma?.$disconnect();
  });

  type Seeded = {
    companyId: string;
    user: TenantUser;
    saleId: string;
    itemIds: string[];
    cashSessionId: string;
    encf: string;
  };

  /** Empresa con e-CF habilitado, numeración autorizada y caja abierta. */
  async function tenant(): Promise<{ companyId: string; user: TenantUser }> {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name: "Synthetic Return", slug: `ecf-ret-${companyId}` },
    });
    await prisma.ecfCompanyConfiguration.create({
      data: {
        companyId,
        enabled: true,
        environment: "SANDBOX",
        allowedTypes: ["E31", "E34"],
      },
    });
    const user = { id: userId, role: "ADMIN", companyId } as TenantUser;
    for (const documentType of ["E31", "E34"]) {
      await prisma.ecfDgiiAuthorizedSequence.create({
        data: {
          companyId,
          documentType,
          authorizationNumber: `SYNTH-${documentType}`,
          rangeFrom: 1,
          rangeTo: 10_000,
          approvedQuantity: 10_000,
          declarationVersion: "v1",
          declaredByUserId: userId,
        },
      });
      await new EcfSequenceService(prisma).register(user, {
        documentType,
        startNumber: 1,
        endNumber: 20,
      });
    }
    return { companyId, user };
  }

  /**
   * Venta real con caja abierta y, opcionalmente, su comprobante E31 aceptado.
   * `withAcceptedDocument: false` reproduce una venta sin e-CF (empresa que no
   * usa el flujo fiscal electrónico).
   */
  async function seededSale(
    options: { withAcceptedDocument?: boolean } = {},
  ): Promise<Seeded> {
    const { companyId, user } = await tenant();
    const encf = `E31${String(Math.floor(Math.random() * 1e10)).padStart(10, "0")}`;

    const cashSession = await prisma.cashSession.create({
      data: {
        companyId,
        openedByUserId: userId,
        status: "OPEN",
        initialAmount: "0.00",
      },
    });

    const sale = await prisma.sale.create({
      data: {
        companyId,
        userId,
        cashSessionId: cashSession.id,
        kind: "invoice",
        status: "COMPLETED",
        totalSold: "177.00",
        totalCost: "2.00",
        totalProfit: "175.00",
        commissionAmount: "0.00",
        taxableBase: "150.00",
        exemptAmount: "0.00",
        taxAmount: "27.00",
        fiscalTaxEnabled: true,
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1",
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
      },
    });

    const itemIds: string[] = [];
    for (const line of [
      { name: "Gravado A", qty: "2", unitPrice: "50.00", base: "100.00", tax: "18.00" },
      { name: "Gravado B", qty: "1", unitPrice: "50.00", base: "50.00", tax: "9.00" },
    ]) {
      const product = await prisma.product.create({
        data: {
          companyId,
          nombre: line.name,
          codigo: `SKU-${randomUUID().slice(0, 8)}`,
          categoria: "General",
          costo: "1.00",
          precio: line.unitPrice,
          unitOfMeasureId: unitId,
          itemType: "PRODUCT",
        },
      });
      const item = await prisma.saleItem.create({
        data: {
          saleId: sale.id,
          productId: product.id,
          productNameSnapshot: line.name,
          qty: line.qty,
          priceSoldUnit: line.unitPrice,
          grossAmount: (Number(line.qty) * Number(line.unitPrice)).toFixed(2),
          lineDiscountAmount: "0.00",
          taxableBase: line.base,
          taxRate: "0.1800",
          taxAmount: line.tax,
          exemptAmount: "0.00",
          taxExempt: false,
          costUnitSnapshot: "1.00",
          subtotalSold: line.base,
          subtotalCost: "1.00",
          profit: "0.00",
          itemTypeSnapshot: "PRODUCT",
        },
      });
      itemIds.push(item.id);
    }

    if (options.withAcceptedDocument !== false) {
      const evidenceRef = `uat://synthetic-not-dgii/${randomUUID()}`;
      const evidenceHash = "a".repeat(64);
      const original = await prisma.ecfElectronicDocument.create({
        data: {
          companyId,
          documentType: "E31",
          status: "DGII_ACCEPTED",
          sourceType: "SALE",
          sourceId: sale.id,
          externalDocumentNumber: encf,
          externalProviderId: `synthetic-${randomUUID()}`,
          idempotencyKey: `synthetic-original-${randomUUID()}`,
          payloadFingerprint: "b".repeat(64),
          fiscalSnapshot: {
            total: "177.00",
            currency: "DOP",
            issueDate: "2026-10-14",
            issuerRnc: "101000001",
            encf,
            evidenceRef,
            evidenceHash,
          },
        },
      });
      // La nota de crédito exige evidencia del RESULTADO del original, no solo
      // su estado: sin este rastro la preparación se rechaza a propósito.
      await prisma.ecfElectronicDocumentStatusLog.create({
        data: {
          companyId,
          documentId: original.id,
          statusAfter: "DGII_ACCEPTED",
          reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII",
          metadata: { evidenceRef, evidenceHash },
        },
      });
    }

    return {
      companyId,
      user,
      saleId: sale.id,
      itemIds,
      cashSessionId: cashSession.id,
      encf,
    };
  }

  function returnDto(
    seeded: Seeded,
    overrides: Record<string, unknown> = {},
  ) {
    return {
      clientRequestId: `ret-${randomUUID()}`,
      restoreInventory: false,
      originalSaleCashSessionId: seeded.cashSessionId,
      operationCashSessionId: seeded.cashSessionId,
      operationOccurredAt: new Date().toISOString(),
      reason: "Devolución sintética de prueba",
      ...overrides,
    };
  }

  const e34Count = (companyId: string) =>
    prisma.ecfElectronicDocument.count({
      where: { companyId, documentType: "E34" },
    });

  it("una devolución parcial prepara su nota E34 con e-NCF autorizado", async () => {
    const seeded = await seededSale();
    const result = await sales.returnSale(
      seeded.user,
      seeded.saleId,
      returnDto(seeded, {
        items: [{ saleItemId: seeded.itemIds[0], qty: "1" }],
      }) as never,
    );

    const credit = (result as { ecfCreditNote?: { encf: string | null } })
      .ecfCreditNote;
    expect(credit).toBeTruthy();
    expect(credit?.encf).toMatch(/^E34\d{10}$/);
    expect(await e34Count(seeded.companyId)).toBe(1);

    const reservation = await prisma.ecfCreditReservation.findFirstOrThrow({
      where: { companyId: seeded.companyId },
    });
    expect(reservation.state).toBe("RESERVED");
    // Una unidad del producto de 50.00 con 18% de ITBIS.
    expect(reservation.amount.toFixed(2)).toBe("59.00");
  });

  it("dos devoluciones parciales dejan su propia nota y suman reserva", async () => {
    const seeded = await seededSale();
    const first = await sales.returnSale(
      seeded.user,
      seeded.saleId,
      returnDto(seeded, {
        items: [{ saleItemId: seeded.itemIds[0], qty: "1" }],
      }) as never,
    );
    const second = await sales.returnSale(
      seeded.user,
      seeded.saleId,
      returnDto(seeded, {
        items: [{ saleItemId: seeded.itemIds[1], qty: "1" }],
      }) as never,
    );

    const firstEncf = (first as { ecfCreditNote?: { encf: string | null } })
      .ecfCreditNote?.encf;
    const secondEncf = (second as { ecfCreditNote?: { encf: string | null } })
      .ecfCreditNote?.encf;
    expect(firstEncf).toMatch(/^E34\d{10}$/);
    expect(secondEncf).toMatch(/^E34\d{10}$/);
    expect(firstEncf).not.toBe(secondEncf);
    expect(await e34Count(seeded.companyId)).toBe(2);
  });

  it("devolver todo el comprobante genera una sola nota TOTAL", async () => {
    const seeded = await seededSale();
    const result = await sales.returnSale(
      seeded.user,
      seeded.saleId,
      returnDto(seeded) as never,
    );
    const credit = (result as { ecfCreditNote?: { encf: string | null } })
      .ecfCreditNote;
    expect(credit?.encf).toMatch(/^E34\d{10}$/);
    expect(await e34Count(seeded.companyId)).toBe(1);

    const reservation = await prisma.ecfCreditReservation.findFirstOrThrow({
      where: { companyId: seeded.companyId },
    });
    // Total del comprobante original: 150.00 + 27.00 de ITBIS.
    expect(reservation.amount.toFixed(2)).toBe("177.00");
  });

  it("reintentar la misma devolución reutiliza la nota, no la duplica", async () => {
    const seeded = await seededSale();
    const dto = returnDto(seeded, {
      items: [{ saleItemId: seeded.itemIds[0], qty: "1" }],
    });
    const first = await sales.returnSale(seeded.user, seeded.saleId, dto as never);
    const retry = await sales.returnSale(seeded.user, seeded.saleId, dto as never);

    const firstEncf = (first as { ecfCreditNote?: { encf: string | null } })
      .ecfCreditNote?.encf;
    const retryEncf = (retry as { ecfCreditNote?: { encf: string | null } })
      .ecfCreditNote?.encf;
    expect(firstEncf).toBeTruthy();
    expect(retryEncf).toBe(firstEncf);
    expect(await e34Count(seeded.companyId)).toBe(1);
  });

  it("una venta sin comprobante electrónico no genera nota alguna", async () => {
    const seeded = await seededSale({ withAcceptedDocument: false });
    const result = await sales.returnSale(
      seeded.user,
      seeded.saleId,
      returnDto(seeded) as never,
    );

    expect(
      (result as { ecfCreditNote?: unknown }).ecfCreditNote ?? null,
    ).toBeNull();
    expect(await e34Count(seeded.companyId)).toBe(0);
  });
});
