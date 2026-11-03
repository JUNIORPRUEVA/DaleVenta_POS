import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfLineClassificationService } from "./ecf-line-classification.service";
import { EcfSaleFiscalAdapter } from "../pos/ecf-sale-fiscal.adapter";

/**
 * Clasificación fiscal supervisada (F1) — integración real con PostgreSQL.
 *
 * Opt-in: solo corre contra una base local autorizada (efímera de pruebas). No
 * contacta a ningún proveedor y no emite nada.
 *
 * Lo que se demuestra, que es lo que importa:
 *
 *  1. Una partida sin producto se queda SIN clasificación y el módulo se niega a
 *     preparar el comprobante en vez de adivinar.
 *  2. Un usuario autorizado confirma la clasificación y la partida deja de
 *     bloquear, **sin que la venta ni la partida se modifiquen**.
 *  3. `previousClassification` y la auditoría dejan rastro de cada decisión.
 *  4. Una vez que el comprobante salió del equipo, ya no se clasifica.
 *  5. Nada de esto cruza de una empresa a otra.
 */
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("F1 clasificación supervisada — PostgreSQL", () => {
  let prisma: PrismaService;
  let service: EcfLineClassificationService;
  let adapter: EcfSaleFiscalAdapter;
  const createdCompanies: string[] = [];

  beforeAll(async () => {
    if (!isEcfLocalTarget()) throw new Error("F1_UAT_REFUSED");
    prisma = new PrismaService();
    await prisma.$connect();
    service = new EcfLineClassificationService(prisma);
    adapter = new EcfSaleFiscalAdapter(prisma);
  });

  afterAll(async () => {
    // NO se borran las empresas: `ecf_line_classifications` es APPEND-ONLY y su
    // *trigger* impide el DELETE, así que el borrado en cascada de `companies`
    // también falla. Es intencionado (la tabla no se toca nunca) y esta base es
    // desechable: se destruye entera al terminar la ejecución.
    await prisma?.$disconnect();
  });

  async function tenant(name: string) {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name, slug: `f1-${companyId}` },
    });
    // `Sale.userId` es una clave foránea real: hace falta un usuario de verdad.
    const user = await prisma.user.create({
      data: {
        email: `f1-${randomUUID()}@example.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Operador F1",
        telefono: "8095550000",
        edad: 30,
        role: "ADMIN",
        companyId,
      },
    });
    createdCompanies.push(companyId);
    return {
      companyId,
      user: { id: user.id, role: "ADMIN", companyId } as TenantUser,
    };
  }

  /**
   * Venta con una partida SIN producto: es exactamente el caso que quedaba
   * bloqueado. La clasificación queda `NULL` y nadie la adivina.
   */
  async function saleWithoutProduct(companyId: string, userId: string) {
    const sale = await prisma.sale.create({
      data: {
        companyId,
        userId,
        totalSold: "100.00",
        totalCost: "0.00",
        totalProfit: "0.00",
        commissionAmount: "0.00",
        taxableBase: "100.00",
        exemptAmount: "0.00",
        discountAmount: "0.00",
        taxAmount: "0.00",
        fiscalTaxEnabled: true,
        // Emisor y receptor completos para que la compuerta que se prueba sea
        // la de CLASIFICACIÓN y no otra anterior.
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1, Santo Domingo",
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
      },
    });
    const item = await prisma.saleItem.create({
      data: {
        saleId: sale.id,
        productId: null,
        productNameSnapshot: "Servicio suelto",
        qty: "1",
        priceSoldUnit: "100.00",
        costUnitSnapshot: "0.00",
        subtotalSold: "100.00",
        subtotalCost: "0.00",
        profit: "100.00",
        grossAmount: "100.00",
        lineDiscountAmount: "0.00",
        taxableBase: "100.00",
        exemptAmount: "0.00",
        taxAmount: "0.00",
        taxRate: "0.0000",
        taxExempt: true,
        // La clave del caso: sin producto, sin clasificación.
        itemTypeSnapshot: null,
      },
    });
    return { sale, item };
  }

  it("sin clasificación, la partida bloquea y NO se adivina", async () => {
    const { companyId, user } = await tenant("F1 sin clasificar");
    const { sale } = await saleWithoutProduct(companyId, user.id);

    const pending = await service.listPending(user, sale.id);
    expect(pending.fiscallyFrozen).toBe(false);
    expect(pending.lines).toHaveLength(1);
    expect(pending.lines[0].frozenClassification).toBeNull();
    expect(pending.lines[0].supervisedClassification).toBeNull();
    expect(pending.lines[0].needsClassification).toBe(true);
    expect(pending.lines[0].canConfirm).toBe(true);

    // El adaptador la bloquea con el código de clasificación, no con otro.
    const blocked = await adapter.build(user, {
      saleId: sale.id,
      documentType: "E31",
    });
    expect(blocked.ok).toBe(false);
    if (blocked.ok) throw new Error("unreachable");
    expect(blocked.code).toBe("ECF_LINE_CLASSIFICATION_UNCONFIRMED");
  });

  it("confirmar la clasificación desbloquea sin tocar la venta ni la partida", async () => {
    const { companyId, user } = await tenant("F1 confirmar");
    const { sale, item } = await saleWithoutProduct(companyId, user.id);

    const before = await prisma.saleItem.findUniqueOrThrow({
      where: { id: item.id },
    });

    const result = await service.confirm(user, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "SERVICE",
      reason: "El operador verificó que es mano de obra",
    });
    expect(result.classification.classification).toBe("SERVICE");
    expect(result.classification.previousClassification).toBeNull();

    // La partida histórica NO se modificó: sigue sin clasificación congelada.
    const after = await prisma.saleItem.findUniqueOrThrow({
      where: { id: item.id },
    });
    expect(after.itemTypeSnapshot).toBeNull();
    expect(after.taxableBase.toString()).toBe(before.taxableBase.toString());
    expect(after.taxAmount.toString()).toBe(before.taxAmount.toString());
    expect(after.subtotalSold.toString()).toBe(before.subtotalSold.toString());
    expect(after.qty.toString()).toBe(before.qty.toString());

    // Y la venta tampoco.
    const saleAfter = await prisma.sale.findUniqueOrThrow({
      where: { id: sale.id },
    });
    expect(saleAfter.totalSold.toFixed(2)).toBe("100.00");

    // La partida ya no bloquea por clasificación: el adaptador pasa de esa
    // compuerta (fallará, si acaso, por otro dato que aquí no se preparó).
    const pending = await service.listPending(user, sale.id);
    expect(pending.lines[0].effectiveClassification).toBe("SERVICE");
    expect(pending.lines[0].needsClassification).toBe(false);
    expect(pending.lines[0].canConfirm).toBe(false);

    const afterClassification = await adapter.build(user, {
      saleId: sale.id,
      documentType: "E31",
    });
    if (!afterClassification.ok) {
      expect(afterClassification.code).not.toBe(
        "ECF_LINE_CLASSIFICATION_UNCONFIRMED",
      );
    }
  });

  it("cada decisión queda auditada con su valor anterior", async () => {
    const { companyId, user } = await tenant("F1 auditoria");
    const { sale, item } = await saleWithoutProduct(companyId, user.id);

    await service.confirm(user, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "Es mercancía según el operador",
    });
    // Corregir es AÑADIR: el valor anterior queda registrado.
    const corrected = await service.confirm(user, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "SERVICE",
      reason: "Se verificó con el cliente: es un servicio",
    });
    expect(corrected.classification.previousClassification).toBe("PRODUCT");

    // Dos filas: el historial no se reescribe.
    const rows = await prisma.ecfLineClassification.findMany({
      where: { companyId, saleItemId: item.id },
      orderBy: [{ decidedAt: "asc" }, { id: "asc" }],
    });
    expect(rows).toHaveLength(2);
    expect(rows[0].classification).toBe("PRODUCT");
    expect(rows[1].classification).toBe("SERVICE");
    expect(rows.every((row) => row.decidedByUserId === user.id)).toBe(true);
    expect(rows.every((row) => row.reason.trim().length > 0)).toBe(true);

    // La auditoría e-CF registra ambos hechos.
    const audit = await prisma.ecfAuditLog.findMany({
      where: { companyId, action: "LINE_CLASSIFICATION_CONFIRMED" },
    });
    expect(audit).toHaveLength(2);

    // Y la tabla es APPEND-ONLY: PostgreSQL impide reescribirla.
    await expect(
      prisma.ecfLineClassification.updateMany({
        where: { companyId, saleItemId: item.id },
        data: { classification: "PRODUCT" },
      }),
    ).rejects.toThrow(/ECF_LINE_CLASSIFICATION_IMMUTABLE/);
    await expect(
      prisma.$executeRawUnsafe(
        `DELETE FROM "ecf_line_classifications" WHERE company_id = '${companyId}'::uuid`,
      ),
    ).rejects.toThrow(/ECF_LINE_CLASSIFICATION_IMMUTABLE/);
  });

  it("no se clasifica una partida que ya tiene clasificación congelada", async () => {
    const { companyId, user } = await tenant("F1 congelada");
    const { sale, item } = await saleWithoutProduct(companyId, user.id);
    await prisma.saleItem.updateMany({
      where: { id: item.id },
      data: { itemTypeSnapshot: "PRODUCT" },
    });

    await expect(
      service.confirm(user, {
        saleId: sale.id,
        saleItemId: item.id,
        classification: "SERVICE",
        reason: "Intento de reclasificar una venta que ya declaró su tipo",
      }),
    ).rejects.toThrow(/clasificación congelada/);

    // La clasificación congelada manda: la supervisada no la movería.
    const pending = await service.listPending(user, sale.id);
    expect(pending.lines[0].effectiveClassification).toBe("PRODUCT");
  });

  it("una vez que el comprobante salió del equipo, ya no se clasifica", async () => {
    const { companyId, user } = await tenant("F1 congelada por envio");
    const { sale, item } = await saleWithoutProduct(companyId, user.id);

    // Un comprobante de esta venta que ya está en el proveedor.
    await prisma.ecfElectronicDocument.create({
      data: {
        companyId,
        documentType: "E31",
        status: "SEND_IN_PROGRESS",
        sourceType: "SALE",
        sourceId: sale.id,
        payloadFingerprint: "a".repeat(64),
        idempotencyKey: `f1-${randomUUID()}`,
      },
    });

    const pending = await service.listPending(user, sale.id);
    expect(pending.fiscallyFrozen).toBe(true);
    expect(pending.lines[0].canConfirm).toBe(false);

    await expect(
      service.confirm(user, {
        saleId: sale.id,
        saleItemId: item.id,
        classification: "PRODUCT",
        reason: "No debería poder: el comprobante ya salió",
      }),
    ).rejects.toThrow(/ya fue enviado o está en revisión/);
  });

  it("no cruza empresas: la partida de otra empresa no existe", async () => {
    const a = await tenant("F1 empresa A");
    const b = await tenant("F1 empresa B");
    const { sale, item } = await saleWithoutProduct(a.companyId, a.user.id);

    await expect(
      service.confirm(
        { id: randomUUID(), role: "ADMIN", companyId: b.companyId } as TenantUser,
        {
          saleId: sale.id,
          saleItemId: item.id,
          classification: "PRODUCT",
          reason: "Intento desde otra empresa",
        },
      ),
    ).rejects.toThrow(/Venta no encontrada/);

    await expect(
      service.listPending(
        { id: randomUUID(), role: "ADMIN", companyId: b.companyId } as TenantUser,
        sale.id,
      ),
    ).rejects.toThrow(/Venta no encontrada/);

    // Y no quedó ningún rastro en B.
    expect(
      await prisma.ecfLineClassification.count({ where: { companyId: b.companyId } }),
    ).toBe(0);
    expect(
      await prisma.ecfAuditLog.count({ where: { companyId: b.companyId } }),
    ).toBe(0);
  });

  it("un identificador manipulado no evade el aislamiento", async () => {
    const a = await tenant("F1 aislamiento A");
    const b = await tenant("F1 aislamiento B");
    const { sale, item } = await saleWithoutProduct(a.companyId, a.user.id);
    await service.confirm(a.user, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "Clasificación legítima de A",
    });

    // B conoce los identificadores reales de A y aun así no alcanza nada.
    for (const saleId of [sale.id, randomUUID()]) {
      await expect(
        service.listPending(
          { id: randomUUID(), role: "ADMIN", companyId: b.companyId } as TenantUser,
          saleId,
        ),
      ).rejects.toThrow(/Venta no encontrada/);
    }
    expect(
      await prisma.ecfLineClassification.count({ where: { companyId: b.companyId } }),
    ).toBe(0);
  });

  it("reintentar la misma confirmación no duplica el historial", async () => {
    const { companyId, user } = await tenant("F1 reintento");
    const { sale, item } = await saleWithoutProduct(companyId, user.id);
    const dto = {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT" as const,
      reason: "Confirmado por el operador",
    };

    await service.confirm(user, dto);
    await expect(service.confirm(user, dto)).rejects.toThrow(
      /ya tiene confirmada esa misma clasificación/,
    );
    expect(
      await prisma.ecfLineClassification.count({
        where: { companyId, saleItemId: item.id },
      }),
    ).toBe(1);
  });
});
