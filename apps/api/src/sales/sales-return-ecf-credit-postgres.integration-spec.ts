import { EcfDocumentQueryService } from "../ecf/documents/ecf-document-query.service";
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

uat("devolución de venta con comprobante aceptado E31/E32 (E34) on PostgreSQL", () => {
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
          environment: "SANDBOX",
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
   * Venta real con caja abierta y, opcionalmente, su comprobante aceptado
   * (E31 por defecto, o E32 cuando la venta fue de consumo).
   * `withAcceptedDocument: false` reproduce una venta sin e-CF (empresa que no
   * usa el flujo fiscal electrónico).
   */
  async function seededSale(
    options: { withAcceptedDocument?: boolean; documentType?: "E31" | "E32" } = {},
  ): Promise<Seeded> {
    const { companyId, user } = await tenant();
    const originalType = options.documentType ?? "E31";
    const encf = `${originalType}${String(Math.floor(Math.random() * 1e10)).padStart(10, "0")}`;

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
          environment: "SANDBOX",
          companyId,
          documentType: originalType,
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

  it("una devolución de un comprobante E32 de consumo también prepara su E34", async () => {
    // La venta por defecto del POS (cliente sin RNC) es E32: devolverla tiene que
    // producir la misma nota de crédito que un comprobante de crédito fiscal E31.
    const seeded = await seededSale({ documentType: "E32" });
    const result = await sales.returnSale(
      seeded.user,
      seeded.saleId,
      returnDto(seeded) as never,
    );

    const credit = (result as { ecfCreditNote?: { encf: string | null } })
      .ecfCreditNote;
    expect(credit).toBeTruthy();
    expect(credit?.encf).toMatch(/^E34\d{10}$/);
    expect(await e34Count(seeded.companyId)).toBe(1);

    const note = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId: seeded.companyId, documentType: "E34" },
      select: { originalDocumentId: true, fiscalDocument: true },
    });
    // La nota referencia el comprobante de CONSUMO original, no un E31.
    const reference = (
      note.fiscalDocument as {
        reference?: { originalType?: string; originalENcf?: string };
      }
    ).reference;
    expect(reference?.originalType).toBe("E32");
    expect(reference?.originalENcf).toBe(seeded.encf);

    const reservation = await prisma.ecfCreditReservation.findFirstOrThrow({
      where: { companyId: seeded.companyId },
    });
    expect(reservation.originalDocumentId).toBe(note.originalDocumentId);
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

  it("no permite devolver más cantidad de la facturada ni sobre-acreditar", async () => {
    const seeded = await seededSale();
    // La línea 1 tiene 2 unidades: devolverlas todas es el máximo legítimo.
    await sales.returnSale(
      seeded.user,
      seeded.saleId,
      returnDto(seeded, {
        items: [{ saleItemId: seeded.itemIds[0], qty: "2" }],
      }) as never,
    );

    await expect(
      sales.returnSale(
        seeded.user,
        seeded.saleId,
        returnDto(seeded, {
          items: [{ saleItemId: seeded.itemIds[0], qty: "1" }],
        }) as never,
      ),
    ).rejects.toThrow();

    // Solo existe la nota de la devolución válida y su reserva es la facturada.
    expect(await e34Count(seeded.companyId)).toBe(1);
    const reservations = await prisma.ecfCreditReservation.findMany({
      where: { companyId: seeded.companyId },
    });
    const reserved = reservations.reduce(
      (sum, row) => sum + Number(row.amount),
      0,
    );
    expect(reserved).toBeCloseTo(118, 2);
  });

  it("dos devoluciones simultáneas no duplican e-NCF ni sobrepasan el crédito", async () => {
    const seeded = await seededSale();
    // Misma línea (2 unidades facturadas) devuelta 1 + 1 EN PARALELO, más un
    // tercer intento que debe perder la carrera por cantidad.
    const attempt = () =>
      sales.returnSale(
        seeded.user,
        seeded.saleId,
        returnDto(seeded, {
          items: [{ saleItemId: seeded.itemIds[0], qty: "1" }],
        }) as never,
      );
    const results = await Promise.allSettled([attempt(), attempt(), attempt()]);
    const succeeded = results.filter((r) => r.status === "fulfilled").length;

    // Nunca se acredita más de lo facturado en la línea: 2 × 59.00.
    const reservations = await prisma.ecfCreditReservation.findMany({
      where: { companyId: seeded.companyId },
    });
    const reserved = reservations.reduce(
      (sum, row) => sum + Number(row.amount),
      0,
    );
    expect(reserved).toBeLessThanOrEqual(118.01);
    expect(reserved).toBeCloseTo(59 * succeeded, 2);
    expect(succeeded).toBeLessThanOrEqual(2);

    // Un e-NCF por nota: la numeración nunca se repite. El número autorizado
    // vive en el payload preparado (`payloadSummary.emission.encf`) hasta que la
    // DGII acepta; `externalDocumentNumber` solo se llena después, así que
    // comparar esa columna aquí mediría nulos, no numeración.
    const notes = await prisma.ecfElectronicDocument.findMany({
      where: { companyId: seeded.companyId, documentType: "E34" },
      select: { payloadSummary: true },
    });
    const numbers = notes
      .map((note) => {
        const emission = (note.payloadSummary as { emission?: { encf?: unknown } } | null)
          ?.emission;
        return typeof emission?.encf === "string" ? emission.encf : "";
      })
      .filter((encf) => encf.length > 0);
    expect(numbers).toHaveLength(notes.length);
    expect(numbers.every((encf) => /^E34\d{10}$/.test(encf))).toBe(true);
    expect(new Set(numbers).size).toBe(numbers.length);
  });

  it("partial then remaining refund each prepare their own exact E34 and replay the earlier note", async () => {
    const seeded = await seededSale(); const firstDto = returnDto(seeded, { items: [{saleItemId: seeded.itemIds[0], qty: "1"}] });
    const first = await sales.returnSale(seeded.user, seeded.saleId, firstDto as never);
    const remaining = await sales.returnSale(seeded.user, seeded.saleId, returnDto(seeded) as never);
    expect((remaining as any).ecfCreditNote.reservedAmount).toBe("118");
    const replay = await sales.returnSale(seeded.user, seeded.saleId, firstDto as never);
    expect((replay as any).ecfCreditNote.documentId).toBe((first as any).ecfCreditNote.documentId);
    const reservations = await prisma.ecfCreditReservation.findMany({where: {companyId: seeded.companyId}});
    expect(reservations.map(r=>r.amount.toFixed(2)).sort()).toEqual(["118.00", "59.00"]);
    expect(await e34Count(seeded.companyId)).toBe(2);
  });
  it("accepted electronic invoices cannot be cancelled through the ordinary delete route", async () => {
    const seeded = await seededSale();
    await expect(sales.remove(seeded.user, seeded.saleId)).rejects.toMatchObject({response: {code: "ECF_CANCELLATION_REQUIRES_CREDIT_NOTE"}});
    const original = await prisma.sale.findFirstOrThrow({where: {companyId: seeded.companyId, id: seeded.saleId}});
    expect(original.cancelledAt).toBeNull(); expect(original.isDeleted).toBe(false);
    expect(await e34Count(seeded.companyId)).toBe(0);
  });
  it("refund idempotency rejects another original sale instead of returning its financial result", async () => {
    const seeded = await seededSale(); const dto = returnDto(seeded);
    await sales.returnSale(seeded.user, seeded.saleId, dto as never);
    await expect(sales.returnSale(seeded.user, randomUUID(), dto as never)).rejects.toThrow("SALE_RETURN_IDEMPOTENCY_ORIGINAL_MISMATCH");
    expect(await e34Count(seeded.companyId)).toBe(1);
  });
  it("failed E34 preparation is visible and recovers without another financial refund", async () => {
    const seeded = await seededSale();
    await prisma.ecfSequence.updateMany({where: {companyId: seeded.companyId, documentType: "E34"}, data: {active:false}});
    const refund = await sales.returnSale(seeded.user, seeded.saleId, returnDto(seeded) as never);
    expect((refund as any).ecfCreditPending.code).toBeTruthy(); expect((refund as any).ecfCreditNote).toBeUndefined();
    await prisma.ecfSequence.updateMany({where: {companyId: seeded.companyId, documentType: "E34"}, data: {active:true}});
    const recovered = await sales.retryRefundFiscal(seeded.user, seeded.saleId, refund.id);
    const again = await sales.retryRefundFiscal(seeded.user, seeded.saleId, refund.id);
    expect((recovered as any).ecfCreditNote.documentId).toBe((again as any).ecfCreditNote.documentId);
    expect(await prisma.sale.count({where: {companyId: seeded.companyId, refundedSaleId: seeded.saleId, kind:"refund"}})).toBe(1);
    expect(await e34Count(seeded.companyId)).toBe(1);
    await expect(sales.retryRefundFiscal({...seeded.user, companyId: randomUUID()}, seeded.saleId, refund.id)).rejects.toThrow("Devolución no encontrada");
  });
  it("fiscal history projects original and notes with company and cashier boundaries", async () => {
    const seeded = await seededSale();
    await sales.returnSale(seeded.user, seeded.saleId, returnDto(seeded) as never);
    const query = new EcfDocumentQueryService(prisma);
    const summary = await query.salesFiscal(seeded.user, [seeded.saleId]);
    expect(summary.items[0].documents[0]).toMatchObject({documentType: "E31", status:"DGII_ACCEPTED"});
    expect(summary.items[0].creditNotes).toHaveLength(1); expect(summary.items[0].pendingRefundIds).toEqual([]);
    expect(summary.items[0].creditNotes[0].encf).toMatch(/^E34\d{10}$/);
    expect(JSON.stringify(summary)).not.toMatch(/payloadSummary|fiscalSnapshot|apiKey|idempotencyKey/);
    expect((await query.salesFiscal({...seeded.user, companyId: randomUUID()},[seeded.saleId])).items).toEqual([]);
    expect((await query.salesFiscal({...seeded.user, id: randomUUID(), role:"CASHIER" as never},[seeded.saleId])).items).toEqual([]);
  });
  it("a return beyond the automatic tax window remains explicit and never creates an unreviewed E34", async () => {
    const seeded = await seededSale();
    await prisma.ecfElectronicDocument.updateMany({where:{companyId:seeded.companyId,sourceId:seeded.saleId},
      data:{fiscalDocument:{issueDate:"2020-01-01"}}});
    const dto=returnDto(seeded);
    const refund=await sales.returnSale(seeded.user,seeded.saleId,dto as never);
    expect((refund as any).ecfCreditPending.code).toBe("ECF_CREDIT_TAX_REVIEW_REQUIRED");
    const replay=await sales.returnSale(seeded.user,seeded.saleId,dto as never);
    expect(replay.id).toBe(refund.id);
    expect(await e34Count(seeded.companyId)).toBe(0);
    expect(await prisma.sale.count({where:{companyId:seeded.companyId,refundedSaleId:seeded.saleId,kind:"refund"}})).toBe(1);
  });
  it("ambiguous legacy originals are displayed for review and never credited blindly", async () => {
    const seeded=await seededSale();
    await prisma.ecfElectronicDocument.create({data:{companyId:seeded.companyId,environment:"SANDBOX",documentType:"E32",
      sourceType:"SALE",sourceId:seeded.saleId,status:"LOCAL_DRAFT",idempotencyKey:randomUUID(),payloadFingerprint:"c".repeat(64)}});
    const result=await sales.returnSale(seeded.user,seeded.saleId,returnDto(seeded) as never);
    expect((result as any).ecfCreditPending.code).toBe("ECF_CREDIT_MULTIPLE_ORIGINALS_REVIEW");
    expect(await e34Count(seeded.companyId)).toBe(0);
    const summary=await new EcfDocumentQueryService(prisma).salesFiscal(seeded.user,[seeded.saleId]);
    expect(summary.items[0].requiresReview).toBe(true);
    expect(summary.items[0].documents).toHaveLength(2);
  });

});
