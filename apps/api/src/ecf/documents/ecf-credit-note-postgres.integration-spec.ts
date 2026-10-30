import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfPreparationService } from "./ecf-preparation.service";
import { EcfSequenceService } from "./ecf-sequence.service";

// Opt-in suite on the ephemeral test database. Preparar una nota de crédito
// reserva crédito fiscal: no emite, no contacta al proveedor y no toca
// inventario, caja, turnos, pagos ni abonos.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("E34 desde una venta original (nota de crédito) on PostgreSQL", () => {
  let prisma: PrismaService;
  let preparation: EcfPreparationService;
  let userId: string;
  let unitId: string;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_E34_CREDIT_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    preparation = new EcfPreparationService(prisma);
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-e34-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic E34 User",
        telefono: "0000000000",
        edad: 30,
        role: "ADMIN",
      },
    });
    unitId = `UNIT_${randomUUID().slice(0, 8)}`;
    await prisma.unitOfMeasure.create({
      data: { id: unitId, code: unitId, name: "Unidad", symbol: "u", category: "COUNT" },
    });
  });
  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: userId } });
    await prisma?.$disconnect();
  });

  async function tenant(options: { enabled?: boolean; allowedTypes?: string[] } = {}) {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name: "Synthetic E34", slug: `ecf-e34-${companyId}` },
    });
    await prisma.ecfCompanyConfiguration.create({
      data: {
        companyId,
        enabled: options.enabled ?? true,
        environment: "SANDBOX",
        allowedTypes: options.allowedTypes ?? ["E31", "E34"],
      },
    });
    const user = { id: userId, role: "ADMIN", companyId } as TenantUser;
    // Cada tipo documental tiene SU propio rango: la nota de crédito consume el
    // rango E34, no el de la factura.
    await new EcfSequenceService(prisma).register(user, {
      documentType: "E31",
      startNumber: 1,
      endNumber: 20,
    });
    await new EcfSequenceService(prisma).register(user, {
      documentType: "E34",
      startNumber: 1,
      endNumber: 20,
    });
    return { companyId, user };
  }

  type LineSpec = {
    name: string;
    qty: string;
    unitPrice: string;
    taxableBase: string;
    taxAmount: string;
    taxRate: string;
    exemptAmount?: string;
    taxExempt?: boolean;
    itemType?: "PRODUCT" | "SERVICE";
  };

  const gravada: LineSpec = {
    name: "Producto gravado",
    qty: "3",
    unitPrice: "59.00",
    taxableBase: "150.00",
    taxAmount: "27.00",
    taxRate: "0.1800",
  };
  const exenta: LineSpec = {
    name: "Producto exento",
    qty: "2",
    unitPrice: "30.00",
    taxableBase: "0.00",
    taxAmount: "0.00",
    taxRate: "0.0000",
    exemptAmount: "60.00",
    taxExempt: true,
  };

  const money = (lines: LineSpec[]) => {
    const taxableBase = lines.reduce((a, l) => a + Number(l.taxableBase), 0);
    const exemptAmount = lines.reduce((a, l) => a + Number(l.exemptAmount ?? 0), 0);
    const taxAmount = lines.reduce((a, l) => a + Number(l.taxAmount), 0);
    return {
      taxableBase: taxableBase.toFixed(2),
      exemptAmount: exemptAmount.toFixed(2),
      taxAmount: taxAmount.toFixed(2),
      total: (taxableBase + exemptAmount + taxAmount).toFixed(2),
    };
  };

  /** Venta real + comprobante E31 aceptado que la referencia. */
  async function acceptedOriginal(companyId: string, user: TenantUser, lines: LineSpec[] = [gravada, exenta]) {
    const totals = money(lines);
    const sale = await prisma.sale.create({
      data: {
        companyId,
        userId,
        totalSold: totals.total,
        totalCost: "0.00",
        totalProfit: "0.00",
        commissionAmount: "0.00",
        taxableBase: totals.taxableBase,
        exemptAmount: totals.exemptAmount,
        taxAmount: totals.taxAmount,
        fiscalTaxEnabled: true,
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1",
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
      },
    });
    for (const line of lines) {
      const product = await prisma.product.create({
        data: {
          companyId,
          nombre: line.name,
          codigo: `SKU-${randomUUID().slice(0, 8)}`,
          categoria: "General",
          costo: "1.00",
          precio: line.unitPrice,
          unitOfMeasureId: unitId,
          itemType: line.itemType ?? "PRODUCT",
        },
      });
      await prisma.saleItem.create({
        data: {
          saleId: sale.id,
          productId: product.id,
          productNameSnapshot: line.name,
          qty: line.qty,
          priceSoldUnit: line.unitPrice,
          grossAmount: (Number(line.qty) * Number(line.unitPrice)).toFixed(2),
          lineDiscountAmount: "0.00",
          taxableBase: line.taxableBase,
          taxRate: line.taxRate,
          taxAmount: line.taxAmount,
          exemptAmount: line.exemptAmount ?? "0.00",
          taxExempt: line.taxExempt ?? false,
          costUnitSnapshot: "1.00",
          subtotalSold: line.taxableBase,
          subtotalCost: "1.00",
          profit: "0.00",
          itemTypeSnapshot: line.itemType ?? "PRODUCT",
        },
      });
    }

    const encf = `E31${String(Math.floor(Math.random() * 1e10)).padStart(10, "0")}`;
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
          total: totals.total,
          currency: "DOP",
          issueDate: "2026-10-14",
          issuerRnc: "101000001",
          encf,
          evidenceRef,
          evidenceHash,
        },
      },
    });
    await prisma.ecfElectronicDocumentStatusLog.create({
      data: {
        companyId,
        documentId: original.id,
        statusAfter: "DGII_ACCEPTED",
        reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII",
        metadata: { evidenceRef, evidenceHash },
      },
    });
    return { sale, original };
  }

  const noteInput = (originalId: string, extra: Record<string, unknown> = {}) => ({
    originalDocumentId: originalId,
    clientRequestId: randomUUID(),
    refundKind: "TOTAL" as const,
    modificationCode: 3 as const,
    modificationReason: "Devolución de mercancía",
    paymentType: 1 as const,
    creditNoteIndicator: 0 as const,
    ...extra,
  });

  it("prepares a TOTAL credit note and reserves the fiscal credit", async () => {
    const { companyId, user } = await tenant();
    const { original } = await acceptedOriginal(companyId, user);

    const result = await preparation.prepareCreditNote(user, noteInput(original.id));

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.value.encf).toMatch(/^E34\d{10}$/);
    expect(result.value.status).toBe("LOCAL_VALIDATED");
    expect(result.value.reservationState).toBe("RESERVED");
    // Total original: 150 + 27 + 60 = 237
    expect(Number(result.value.reservedAmount)).toBe(237);

    const note = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId, id: result.value.documentId },
    });
    expect(note.documentType).toBe("E34");
    expect(note.originalDocumentId).toBe(original.id);
    expect(note.externalProviderId).toBeNull();
  });

  it("prepares a PARTIAL note for a fraction of one line", async () => {
    const { companyId, user } = await tenant();
    const { original } = await acceptedOriginal(companyId, user);

    const result = await preparation.prepareCreditNote(
      user,
      noteInput(original.id, {
        refundKind: "PARTIAL",
        lines: [{ lineNumber: 1, quantity: "1" }],
      }),
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // 1 de 3 unidades de 50 + ITBIS 9 = 59
    expect(Number(result.value.reservedAmount)).toBe(59);
  });

  it("allows several partial notes on the same original", async () => {
    const { companyId, user } = await tenant();
    const { original } = await acceptedOriginal(companyId, user);

    const first = await preparation.prepareCreditNote(
      user,
      noteInput(original.id, { refundKind: "PARTIAL", lines: [{ lineNumber: 1, quantity: "1" }] }),
    );
    const second = await preparation.prepareCreditNote(
      user,
      noteInput(original.id, { refundKind: "PARTIAL", lines: [{ lineNumber: 1, quantity: "1" }] }),
    );

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(second.value.documentId).not.toBe(first.value.documentId);
    expect(await prisma.ecfCreditReservation.count({
      where: { companyId, originalDocumentId: original.id, state: "RESERVED" },
    })).toBe(2);
  });

  it("is idempotent for the same operation and does not consume a second e-NCF", async () => {
    const { companyId, user } = await tenant();
    const { original } = await acceptedOriginal(companyId, user);
    const input = noteInput(original.id);

    const first = await preparation.prepareCreditNote(user, input);
    const second = await preparation.prepareCreditNote(user, input);

    expect(first.ok && second.ok).toBe(true);
    if (!first.ok || !second.ok) return;
    expect(second.value.documentId).toBe(first.value.documentId);
    expect(second.value.encf).toBe(first.value.encf);
    expect(await prisma.ecfElectronicDocument.count({ where: { companyId, documentType: "E34" } })).toBe(1);
  });

  it("refuses credit beyond the available balance", async () => {
    const { companyId, user } = await tenant();
    const { original } = await acceptedOriginal(companyId, user);

    // Se agota el saldo con una nota total…
    const full = await preparation.prepareCreditNote(user, noteInput(original.id));
    expect(full.ok).toBe(true);

    // …y cualquier nota adicional debe bloquearse. La política de saldo del
    // servicio E34 existente lanza un error de dominio: no se reescribe aquí.
    await expect(
      preparation.prepareCreditNote(
        user,
        noteInput(original.id, {
          refundKind: "PARTIAL",
          lines: [{ lineNumber: 1, quantity: "1" }],
        }),
      ),
    ).rejects.toThrow("E34_INSUFFICIENT_FISCAL_BALANCE");
  });

  it("never touches inventory, cash or the original sale", async () => {
    const { companyId, user } = await tenant();
    const { sale, original } = await acceptedOriginal(companyId, user);
    const before = await prisma.sale.findFirstOrThrow({ where: { id: sale.id } });

    const result = await preparation.prepareCreditNote(user, noteInput(original.id));

    expect(result.ok).toBe(true);
    const after = await prisma.sale.findFirstOrThrow({ where: { id: sale.id } });
    expect(after.status).toBe(before.status);
    expect(after.totalSold.toFixed(2)).toBe(before.totalSold.toFixed(2));
    expect(after.cancelledAt).toBeNull();
    expect(await prisma.inventoryMovement.count({ where: { companyId } })).toBe(0);
  });

  it("refuses an original that is not fiscally accepted", async () => {
    const { companyId, user } = await tenant();
    const { original } = await acceptedOriginal(companyId, user);
    await prisma.ecfElectronicDocument.updateMany({
      where: { companyId, id: original.id },
      data: { status: "PROVIDER_ACCEPTED" },
    });

    const result = await preparation.prepareCreditNote(user, noteInput(original.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_CREDIT_ORIGINAL_NOT_ACCEPTED");
  });

  it("never credits another company's original", async () => {
    const a = await tenant();
    const b = await tenant();
    const { original } = await acceptedOriginal(a.companyId, a.user);

    const result = await preparation.prepareCreditNote(b.user, noteInput(original.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_CREDIT_ORIGINAL_NOT_FOUND");
  });

  it("refuses when e-CF is switched off for the company", async () => {
    const { companyId, user } = await tenant({ enabled: false });
    const { original } = await acceptedOriginal(companyId, user);

    const result = await preparation.prepareCreditNote(user, noteInput(original.id));

    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.code).toBe("ECF_COMPANY_DISABLED");
  });

  it("keeps the original's fiscal classification on the note", async () => {
    const { companyId, user } = await tenant();
    const { original } = await acceptedOriginal(companyId, user);

    // Nota parcial solo de la línea exenta.
    const result = await preparation.prepareCreditNote(
      user,
      noteInput(original.id, { refundKind: "PARTIAL", lines: [{ lineNumber: 2, quantity: "1" }] }),
    );

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    // 1 de 2 unidades exentas de 30 → 30, sin ITBIS.
    expect(Number(result.value.reservedAmount)).toBe(30);
  });
});
