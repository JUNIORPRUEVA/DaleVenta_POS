import { NotFoundException } from "@nestjs/common";
import { InventoryMovementType, Prisma, ProductSource } from "@prisma/client";
import { InventoryReportingService } from "./inventory-reporting.service";

const companyId = "11111111-1111-4111-8111-111111111111";
const otherCompanyProduct = "99999999-9999-4999-8999-999999999999";
const productId = "22222222-2222-4222-8222-222222222222";
const warehouseId = "33333333-3333-4333-8333-333333333333";
const destinationWarehouseId = "44444444-4444-4444-8444-444444444444";
const transferId = "55555555-5555-4555-8555-555555555555";
const saleId = "66666666-6666-4666-8666-666666666666";
const receiptId = "77777777-7777-4777-8777-777777777777";
const userId = "88888888-8888-4888-8888-888888888888";

function decimal(value: Prisma.Decimal.Value) {
  return new Prisma.Decimal(value);
}

function movement(overrides: Partial<any> = {}) {
  return {
    id: "movement-a",
    companyId,
    productId,
    warehouseId,
    type: InventoryMovementType.SALE,
    quantityDelta: decimal("-2.375"),
    previousQuantity: decimal("10"),
    resultingQuantity: decimal("7.625"),
    unitCodeSnapshot: "POUND",
    unitNameSnapshot: "Libra",
    unitSymbolSnapshot: "lb",
    unitPrecisionSnapshot: 3,
    sourceWarehouseId: warehouseId,
    destinationWarehouseId: null,
    sourceType: "SALE",
    sourceId: saleId,
    sourceItemId: "sale-item-a",
    reason: "SALE",
    createdByUserId: userId,
    createdAt: new Date("2026-08-31T10:00:00.000Z"),
    product: { id: productId, nombre: "Producto Peso UAT", codigo: "LB-1" },
    warehouse: {
      id: warehouseId,
      name: "Principal",
      code: "PRI",
      isActive: true,
    },
    sourceWarehouse: {
      id: warehouseId,
      name: "Principal",
      code: "PRI",
      isActive: true,
    },
    destinationWarehouse: null,
    createdBy: {
      id: userId,
      nombreCompleto: "Admin UAT",
      email: "uat@example.test",
    },
    ...overrides,
  };
}

function buildService(source: ProductSource = ProductSource.LOCAL) {
  const prisma: any = {
    $transaction: jest.fn(async (arg) => {
      if (Array.isArray(arg)) return Promise.all(arg);
      return arg(prisma);
    }),
    inventoryMovement: {
      count: jest.fn(async () => 1),
      findMany: jest.fn(async () => [movement()]),
    },
    product: {
      findFirst: jest.fn(async ({ where }) =>
        where.id === otherCompanyProduct ? null : { id: where.id },
      ),
      findMany: jest.fn(async () => [
        {
          id: productId,
          nombre: "Tela Azul",
          codigo: "YD-1",
          stock: decimal("20.5"),
          unitOfMeasure: {
            code: "YARD",
            name: "Yarda",
            symbol: "yd",
            precision: 3,
          },
          warehouseStocks: [
            { warehouseId, quantity: decimal("20.5") },
            { warehouseId: destinationWarehouseId, quantity: decimal("0") },
          ],
        },
      ]),
    },
    warehouse: {
      findFirst: jest.fn(async () => ({ id: warehouseId })),
      findMany: jest.fn(async () => [
        {
          id: warehouseId,
          name: "Principal",
          code: "PRI",
          isDefault: true,
          isActive: true,
        },
        {
          id: destinationWarehouseId,
          name: "Bavaro",
          code: "BAV",
          isDefault: false,
          isActive: false,
        },
      ]),
    },
    user: { findFirst: jest.fn(async () => ({ id: userId })) },
    warehouseTransfer: {
      findMany: jest.fn(async () => [
        {
          id: transferId,
          sourceWarehouseNameSnapshot: "Principal",
          destinationWarehouseNameSnapshot: "Bavaro",
        },
      ]),
    },
    sale: {
      findMany: jest.fn(async () => [
        { id: saleId, ncf: "B0200000001", kind: "invoice" },
      ]),
    },
    purchaseReceipt: {
      findMany: jest.fn(async () => [
        {
          id: receiptId,
          supplierInvoiceNumber: "SUP-1",
          purchaseOrder: { orderNumber: "PO-1" },
        },
      ]),
    },
  };
  const resolver = {
    resolveForCompany: jest.fn(async () => ({ source })),
  };
  return {
    prisma,
    resolver,
    service: new InventoryReportingService(prisma, resolver as any),
  };
}

describe("InventoryReportingService", () => {
  const user = { id: userId, role: "ADMIN", companyId };

  it("lists movements scoped to tenant with deterministic pagination", async () => {
    const { service, prisma } = buildService();

    const result = await service.listMovements(user, {
      take: "10",
      skip: "5",
    });

    expect(prisma.inventoryMovement.count).toHaveBeenCalledWith({
      where: { companyId },
    });
    expect(prisma.inventoryMovement.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId },
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: 10,
        skip: 5,
      }),
    );
    expect(result.items[0]).toMatchObject({
      label: "Venta",
      direction: "OUT",
      quantityDeltaDecimal: "-2.375",
      previousQuantityDecimal: "10",
      resultingQuantityDecimal: "7.625",
      reference: { label: "Venta B0200000001" },
    });
  });

  it("applies product, warehouse, type, date, source and user filters inside company scope", async () => {
    const { service, prisma } = buildService();

    await service.listMovements(user, {
      productId,
      warehouseId,
      type: "SALE",
      sourceType: "SALE",
      userId,
      from: "2026-08-31T00:00:00.000Z",
      to: "2026-08-31T23:59:59.999Z",
    });

    const where = prisma.inventoryMovement.findMany.mock.calls[0][0].where;
    expect(where).toMatchObject({
      companyId,
      productId,
      warehouseId,
      type: InventoryMovementType.SALE,
      sourceType: "SALE",
      createdByUserId: userId,
    });
    expect(where.createdAt.gte.toISOString()).toBe("2026-08-31T00:00:00.000Z");
    expect(where.createdAt.lte.toISOString()).toBe("2026-08-31T23:59:59.999Z");
  });

  it("blocks cross-tenant product filters before querying movements", async () => {
    const { service, prisma } = buildService();

    await expect(
      service.listMovements(user, { productId: otherCompanyProduct }),
    ).rejects.toBeInstanceOf(NotFoundException);
    expect(prisma.inventoryMovement.findMany).not.toHaveBeenCalled();
  });

  it("links transfer OUT/IN movements to the same readable transfer reference", async () => {
    const { service, prisma } = buildService();
    prisma.inventoryMovement.findMany.mockResolvedValue([
      movement({
        id: "out",
        type: InventoryMovementType.TRANSFER_OUT,
        sourceType: "WAREHOUSE_TRANSFER",
        sourceId: transferId,
        quantityDelta: decimal("-0.5"),
      }),
      movement({
        id: "in",
        type: InventoryMovementType.TRANSFER_IN,
        sourceType: "WAREHOUSE_TRANSFER",
        sourceId: transferId,
        quantityDelta: decimal("0.5"),
        warehouseId: destinationWarehouseId,
      }),
    ]);
    prisma.inventoryMovement.count.mockResolvedValue(2);

    const result = await service.listMovements(user, {});

    expect(result.items).toHaveLength(2);
    expect(result.items[0].reference.label).toBe(
      "Transferencia Principal -> Bavaro",
    );
    expect(result.items[1].reference.rawId).toBe(transferId);
  });

  it("keeps inactive warehouse stock visible and does not sum incompatible UoMs as total units", async () => {
    const { service } = buildService();

    const result = await service.stockReport(user);

    expect(result.incompatibleUnitsSummed).toBe(false);
    expect(result.warehouses).toContainEqual(
      expect.objectContaining({ id: destinationWarehouseId, isActive: false }),
    );
    expect(result.rows[0]).toMatchObject({
      companyTotalDecimal: "20.5",
      compatibilityStockDecimal: "20.5",
      reconciled: true,
    });
  });

  it("reports reconciliation drift without repairing inventory", async () => {
    const { service, prisma } = buildService();
    prisma.product.findMany.mockResolvedValue([
      {
        id: productId,
        nombre: "Tela Azul",
        codigo: "YD-1",
        stock: decimal("21"),
        unitOfMeasure: { symbol: "yd", precision: 3 },
        warehouseStocks: [{ quantity: decimal("20.5") }],
      },
    ]);

    const result = await service.reconciliation(user);

    expect(result.driftCount).toBe(1);
    expect(result.items[0]).toMatchObject({
      productStockDecimal: "21",
      warehouseTotalDecimal: "20.5",
      differenceDecimal: "0.5",
      reconciled: false,
    });
    expect(prisma.product.updateMany).toBeUndefined();
  });

  it("returns explicit external inventory behavior for FULLPOS", async () => {
    const { service, prisma } = buildService(ProductSource.FULLPOS);

    const result = await service.listMovements(user, {});

    expect(result).toMatchObject({
      source: ProductSource.FULLPOS,
      readOnly: true,
      externalInventory: true,
      items: [],
    });
    expect(prisma.inventoryMovement.findMany).not.toHaveBeenCalled();
  });
});
