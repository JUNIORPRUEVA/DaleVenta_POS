import { BadRequestException } from "@nestjs/common";
import { ProductSource, PurchaseOrderStatus, Role } from "@prisma/client";
import { PurchasesService } from "./purchases.service";

describe("PurchasesService transaction product identity", () => {
  const user = {
    id: "user-a",
    role: Role.ADMIN,
    companyId: "11111111-1111-1111-1111-111111111111",
  };

  function serviceWith(prisma: Record<string, unknown>) {
    return new PurchasesService(
      prisma as never,
      { get: jest.fn().mockReturnValue("") } as never,
      {} as never,
    );
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
          createInventoryProductOnReceipt: false,
        },
      ],
    };
    const prisma = {
      purchaseOrder: {
        findFirst: jest.fn().mockResolvedValue(order),
        update: jest.fn(),
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
});
