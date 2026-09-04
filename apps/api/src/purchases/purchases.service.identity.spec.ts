import { BadRequestException } from "@nestjs/common";
import { Prisma, ProductSource, PurchaseOrderStatus, Role } from "@prisma/client";
import { PurchasesService } from "./purchases.service";

describe("PurchasesService transaction product identity", () => {
  const user = {
    id: "user-a",
    role: Role.ADMIN,
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  function serviceWith(
    prisma: Record<string, unknown>,
    inventory?: Record<string, unknown>,
  ) {
    return new PurchasesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      {} as never,
      inventory as never,
    );
  }

  function sequenceTx({
    storedCurrent = 0,
    historicalCurrent = 0,
  }: {
    storedCurrent?: number;
    historicalCurrent?: number;
  }) {
    return {
      $executeRaw: jest.fn().mockResolvedValue(1),
      $queryRaw: jest.fn((strings: TemplateStringsArray) => {
        const sql = strings.join("");
        if (sql.includes("SELECT next_value")) {
          return Promise.resolve([{ next_value: storedCurrent }]);
        }
        if (sql.includes("MAX(substring(order_number")) {
          return Promise.resolve([{ highest: historicalCurrent }]);
        }
        return Promise.resolve([]);
      }),
      purchaseOrderSequence: {
        update: jest.fn().mockResolvedValue({}),
      },
    };
  }

  async function nextOrderNumber(
    service: PurchasesService,
    tx: Record<string, unknown>,
    companyId = user.companyId,
  ) {
    return (service as any).nextOrderNumber(tx, companyId);
  }

  it("stores LOCAL identity for local purchase order lines", async () => {
    const product = {
      id: "11111111-1111-4111-8111-111111111111",
      nombre: "Cable local",
      codigo: "CAB",
      descripcion: null,
      imagen: null,
      costo: 20,
      unitOfMeasure: {
        code: "UNIT",
        name: "Unidad",
        symbol: "u",
        allowDecimals: false,
        precision: 0,
      },
    };
    const prisma = {
      product: { findMany: jest.fn().mockResolvedValue([product]) },
      supplier: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    const [item] = await (service as any).normalizeItems(user.companyId, [
      {
        productId: product.id,
        productName: "Ignorado",
        quantity: 2,
        unitCost: 15,
      },
    ]);

    expect(item.data).toMatchObject({
      productId: product.id,
      productSource: "LOCAL",
      sourceProductId: product.id,
      productNameSnapshot: "Cable local",
    });
  });

  it("creates OC-000001 for the first purchase order", async () => {
    const service = serviceWith({});
    const tx = sequenceTx({});

    await expect(nextOrderNumber(service, tx)).resolves.toBe("OC-000001");
    expect(tx.purchaseOrderSequence.update).toHaveBeenCalledWith({
      where: { scope: user.companyId },
      data: { nextValue: 1 },
    });
  });

  it("advances stale sequence when OC-000001 already exists", async () => {
    const service = serviceWith({});
    const tx = sequenceTx({ storedCurrent: 0, historicalCurrent: 1 });

    await expect(nextOrderNumber(service, tx)).resolves.toBe("OC-000002");
    expect(tx.purchaseOrderSequence.update).toHaveBeenCalledWith({
      where: { scope: user.companyId },
      data: { nextValue: 2 },
    });
  });

  it("uses the highest valid historical OC number across gaps", async () => {
    const service = serviceWith({});
    const tx = sequenceTx({ storedCurrent: 2, historicalCurrent: 5 });

    await expect(nextOrderNumber(service, tx)).resolves.toBe("OC-000006");
    expect(tx.purchaseOrderSequence.update).toHaveBeenCalledWith({
      where: { scope: user.companyId },
      data: { nextValue: 6 },
    });
  });

  it("uses stored sequence when it is higher than existing orders", async () => {
    const service = serviceWith({});
    const tx = sequenceTx({ storedCurrent: 10, historicalCurrent: 5 });

    await expect(nextOrderNumber(service, tx)).resolves.toBe("OC-000011");
    expect(tx.purchaseOrderSequence.update).toHaveBeenCalledWith({
      where: { scope: user.companyId },
      data: { nextValue: 11 },
    });
  });

  it("keeps purchase order numbers company scoped", async () => {
    const service = serviceWith({});
    const firstCompanyTx = sequenceTx({ storedCurrent: 4, historicalCurrent: 4 });
    const secondCompanyTx = sequenceTx({ storedCurrent: 0, historicalCurrent: 0 });

    await expect(
      nextOrderNumber(service, firstCompanyTx, "11111111-1111-1111-1111-111111111111"),
    ).resolves.toBe("OC-000005");
    await expect(
      nextOrderNumber(service, secondCompanyTx, "22222222-2222-2222-2222-222222222222"),
    ).resolves.toBe("OC-000001");
  });

  it("ignores custom/nonstandard historical numbers through the SQL filter", async () => {
    const service = serviceWith({});
    const tx = sequenceTx({ storedCurrent: 0, historicalCurrent: 3 });

    await expect(nextOrderNumber(service, tx)).resolves.toBe("OC-000004");
    expect(tx.$queryRaw).toHaveBeenCalledWith(
      expect.arrayContaining([
        expect.stringContaining("order_number ~ '^OC-[0-9]{6}$'"),
      ]),
      user.companyId,
    );
  });

  it("retries purchase order creation after a concurrent order-number collision", async () => {
    const product = {
      id: "11111111-1111-4111-8111-111111111111",
      nombre: "Cable local",
      codigo: "CAB",
      descripcion: null,
      imagen: null,
      costo: 20,
      unitOfMeasure: {
        code: "UNIT",
        name: "Unidad",
        symbol: "u",
        allowDecimals: false,
        precision: 0,
      },
    };
    const conflict = new Prisma.PrismaClientKnownRequestError("duplicate", {
      code: "P2002",
      clientVersion: "5.22.0",
      meta: { target: ["company_id", "order_number"] },
    });
    const tx = {
      $executeRaw: jest.fn().mockResolvedValue(1),
      $queryRaw: jest
        .fn()
        .mockResolvedValueOnce([{ next_value: 1 }])
        .mockResolvedValueOnce([{ highest: 1 }]),
      purchaseOrderSequence: { update: jest.fn().mockResolvedValue({}) },
      purchaseOrder: {
        create: jest.fn().mockResolvedValue({ id: "order-b", orderNumber: "OC-000002" }),
      },
    };
    const prisma = {
      product: { findMany: jest.fn().mockResolvedValue([product]) },
      supplier: { findMany: jest.fn().mockResolvedValue([]) },
      $transaction: jest
        .fn()
        .mockRejectedValueOnce(conflict)
        .mockImplementationOnce((callback) => callback(tx)),
    };
    const service = serviceWith(prisma);

    await expect(
      service.createOrder(user, {
        items: [
          {
            productId: product.id,
            productName: "Cable local",
            quantity: 1,
            unitCost: 20,
          },
        ],
      }),
    ).resolves.toMatchObject({ orderNumber: "OC-000002" });
    expect(prisma.$transaction).toHaveBeenCalledTimes(2);
  });

  it("preserves FULLPOS identity on purchase order lines", async () => {
    const prisma = {
      product: { findMany: jest.fn().mockResolvedValue([]) },
      supplier: { findMany: jest.fn().mockResolvedValue([]) },
    };
    const service = serviceWith(prisma);

    const [item] = await (service as any).normalizeItems(user.companyId, [
      {
        productSource: "FULLPOS",
        sourceProductId: "same-remote-id",
        productName: "Producto externo",
        quantity: 2.375,
        unitCost: 15,
      },
    ]);

    expect(item.data).toMatchObject({
      productId: undefined,
      productSource: "FULLPOS",
      sourceProductId: "same-remote-id",
      productNameSnapshot: "Producto externo",
    });
  });

  it("blocks FULLPOS purchase inventory increments until writable stock is proven", async () => {
    const order = {
      id: "order-a",
      companyId: user.companyId,
      status: PurchaseOrderStatus.APPROVED,
      items: [
        {
          id: "item-a",
          productId: null,
          productSource: ProductSource.FULLPOS,
          sourceProductId: "same-remote-id",
          productNameSnapshot: "Producto externo",
          pendingQuantity: 5,
          quantity: 5,
          receivedQuantity: 0,
          unitCodeSnapshot: "UNIT",
          unitNameSnapshot: "Unidad",
          unitSymbolSnapshot: "u",
          unitPrecisionSnapshot: 0,
          createInventoryProductOnReceipt: true,
        },
      ],
    };
    const prisma = {
      purchaseOrder: {
        findFirst: jest.fn().mockResolvedValue(order),
        update: jest.fn(),
      },
      company: {
        findUnique: jest.fn().mockResolvedValue({ inventoryEnabled: true }),
      },
      purchaseReceipt: {
        create: jest.fn().mockResolvedValue({ id: "receipt-a", items: [] }),
      },
      $transaction: jest.fn((callback) =>
        callback({
          purchaseReceipt: {
            create: jest.fn().mockResolvedValue({ id: "receipt-a", items: [] }),
          },
          purchaseOrderItem: { update: jest.fn(), findMany: jest.fn() },
          purchaseOrder: { update: jest.fn() },
          product: { updateMany: jest.fn(), create: jest.fn() },
        }),
      ),
    };
    const service = serviceWith(prisma);

    await expect(
      service.receiveOrder(user, "order-a", {
        updateInventory: true,
        items: [
          {
            purchaseOrderItemId: "item-a",
            quantityReceived: 1,
            unitCost: 15,
          },
        ],
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it("updates inventory only for tracked products in a mixed receipt", async () => {
    const items = [
      {
        id: "item-tracked",
        productId: "tracked-product",
        productSource: ProductSource.LOCAL,
        sourceProductId: "tracked-product",
        productNameSnapshot: "Harina",
        pendingQuantity: 10,
        quantity: 10,
        receivedQuantity: 0,
        unitCodeSnapshot: "UNIT",
        unitNameSnapshot: "Unidad",
        unitSymbolSnapshot: "u",
        unitPrecisionSnapshot: 0,
        createInventoryProductOnReceipt: false,
        product: { itemType: "PRODUCT", trackInventory: true },
      },
      {
        id: "item-non-inventory",
        productId: "non-inventory-product",
        productSource: ProductSource.LOCAL,
        sourceProductId: "non-inventory-product",
        productNameSnapshot: "Garantia extendida",
        pendingQuantity: 5,
        quantity: 5,
        receivedQuantity: 0,
        unitCodeSnapshot: "UNIT",
        unitNameSnapshot: "Unidad",
        unitSymbolSnapshot: "u",
        unitPrecisionSnapshot: 0,
        createInventoryProductOnReceipt: false,
        product: { itemType: "PRODUCT", trackInventory: false },
      },
      {
        id: "item-service",
        productId: "service-product",
        productSource: ProductSource.LOCAL,
        sourceProductId: "service-product",
        productNameSnapshot: "Instalacion",
        pendingQuantity: 1,
        quantity: 1,
        receivedQuantity: 0,
        unitCodeSnapshot: "UNIT",
        unitNameSnapshot: "Unidad",
        unitSymbolSnapshot: "u",
        unitPrecisionSnapshot: 0,
        createInventoryProductOnReceipt: false,
        product: { itemType: "SERVICE", trackInventory: false },
      },
    ];
    const order = {
      id: "order-mixed",
      companyId: user.companyId,
      status: PurchaseOrderStatus.APPROVED,
      items,
    };
    const receiptItems: any[] = [];
    const tx = {
      warehouse: {
        findFirst: jest.fn().mockResolvedValue({
          id: "warehouse-main",
          name: "Principal",
          code: "MAIN",
        }),
      },
      purchaseReceipt: {
        create: jest.fn().mockResolvedValue({ id: "receipt-mixed" }),
        findUniqueOrThrow: jest
          .fn()
          .mockResolvedValue({ id: "receipt-mixed", items: receiptItems }),
      },
      purchaseOrderItem: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn(),
        findMany: jest
          .fn()
          .mockResolvedValue(items.map((item) => ({ ...item, pendingQuantity: 0, receivedQuantity: item.quantity }))),
      },
      product: { updateMany: jest.fn(), create: jest.fn() },
      purchaseReceiptItem: {
        create: jest.fn(async (args: any) => {
          const row = {
            id: `receipt-item-${receiptItems.length + 1}`,
            ...args.data,
          };
          receiptItems.push(row);
          return row;
        }),
        update: jest.fn(),
      },
      warehouseStock: { upsert: jest.fn() },
      purchaseOrder: { update: jest.fn().mockResolvedValue(order) },
    };
    const prisma = {
      purchaseOrder: {
        findFirst: jest.fn().mockResolvedValue(order),
      },
      company: {
        findUnique: jest.fn().mockResolvedValue({ inventoryEnabled: true }),
      },
      purchaseReceipt: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const inventory = {
      increaseStockInTransaction: jest
        .fn()
        .mockResolvedValue({ movementId: "movement-tracked" }),
    };
    const service = serviceWith(prisma, inventory);

    const result = await service.receiveOrder(user, "order-mixed", {
      updateInventory: true,
      items: [
        {
          purchaseOrderItemId: "item-tracked",
          quantityReceived: 10,
          unitCost: 100,
        },
        {
          purchaseOrderItemId: "item-non-inventory",
          quantityReceived: 5,
          unitCost: 20,
        },
        {
          purchaseOrderItemId: "item-service",
          quantityReceived: 1,
          unitCost: 50,
        },
      ],
    });

    expect(result.receipt.items).toHaveLength(3);
    expect(inventory.increaseStockInTransaction).toHaveBeenCalledTimes(1);
    expect(tx.warehouseStock.upsert).toHaveBeenCalledTimes(1);
    expect(tx.purchaseReceiptItem.update).toHaveBeenCalledTimes(1);
    expect(tx.purchaseReceiptItem.create).toHaveBeenCalledTimes(3);
  });

  it("does not update inventory when company inventory is off", async () => {
    const items = [
      {
        id: "item-tracked",
        productId: "tracked-product",
        productSource: ProductSource.LOCAL,
        sourceProductId: "tracked-product",
        productNameSnapshot: "Harina",
        pendingQuantity: 2,
        quantity: 2,
        receivedQuantity: 0,
        unitCodeSnapshot: "UNIT",
        unitNameSnapshot: "Unidad",
        unitSymbolSnapshot: "u",
        unitPrecisionSnapshot: 0,
        createInventoryProductOnReceipt: false,
        product: { itemType: "PRODUCT", trackInventory: true },
      },
    ];
    const order = {
      id: "order-inventory-off",
      companyId: user.companyId,
      status: PurchaseOrderStatus.APPROVED,
      items,
    };
    const receiptItems: any[] = [];
    const tx = {
      warehouse: {
        findFirst: jest.fn().mockResolvedValue({
          id: "warehouse-main",
          name: "Principal",
          code: "MAIN",
        }),
      },
      purchaseReceipt: {
        create: jest.fn().mockResolvedValue({ id: "receipt-off" }),
        findUniqueOrThrow: jest
          .fn()
          .mockResolvedValue({ id: "receipt-off", items: receiptItems }),
      },
      purchaseOrderItem: {
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn(),
        findMany: jest
          .fn()
          .mockResolvedValue(items.map((item) => ({ ...item, pendingQuantity: 0, receivedQuantity: item.quantity }))),
      },
      product: { updateMany: jest.fn(), create: jest.fn() },
      purchaseReceiptItem: {
        create: jest.fn(async (args: any) => {
          const row = { id: `receipt-item-${receiptItems.length + 1}`, ...args.data };
          receiptItems.push(row);
          return row;
        }),
        update: jest.fn(),
      },
      warehouseStock: { upsert: jest.fn() },
      purchaseOrder: { update: jest.fn().mockResolvedValue(order) },
    };
    const prisma = {
      purchaseOrder: {
        findFirst: jest.fn().mockResolvedValue(order),
      },
      company: {
        findUnique: jest.fn().mockResolvedValue({ inventoryEnabled: false }),
      },
      purchaseReceipt: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const inventory = {
      increaseStockInTransaction: jest.fn(),
    };
    const service = serviceWith(prisma, inventory);

    const result = await service.receiveOrder(user, "order-inventory-off", {
      updateInventory: true,
      items: [
        {
          purchaseOrderItemId: "item-tracked",
          quantityReceived: 2,
          unitCost: 100,
        },
      ],
    });

    expect(result.receipt.items).toHaveLength(1);
    expect(inventory.increaseStockInTransaction).not.toHaveBeenCalled();
    expect(tx.warehouseStock.upsert).not.toHaveBeenCalled();
    expect(tx.purchaseReceiptItem.update).not.toHaveBeenCalled();
  });
});
