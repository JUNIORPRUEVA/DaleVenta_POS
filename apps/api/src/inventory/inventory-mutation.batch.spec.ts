import { NotFoundException } from "@nestjs/common";
import { Prisma, ProductSource } from "@prisma/client";
import { InventoryMutationService } from "./inventory-mutation.service";

const COMPANY_A = "11111111-1111-4111-8111-111111111111";
const COMPANY_B = "99999999-9999-4999-8999-999999999999";
const WAREHOUSE = "33333333-3333-4333-8333-333333333333";
const SALE = "77777777-7777-4777-8777-777777777777";

type ProductRow = {
  id: string;
  nombre: string;
  stock: Prisma.Decimal;
  companyId: string;
  productSource?: ProductSource | null;
  unitOfMeasure?: {
    code: string;
    name: string;
    symbol: string;
    precision: number;
    allowDecimals: boolean;
  };
};

/**
 * `tx` mínimo que respeta el scope de empresa, igual que lo haría PostgreSQL:
 * `product.findMany({ companyId, id: { in } })` sólo devuelve productos de la
 * empresa pedida. Así el test demuestra aislamiento multi-tenant real del lote.
 */
function buildTx(options: {
  products: ProductRow[];
  warehouseActive?: boolean;
  calls?: Record<string, number>;
}) {
  const calls = options.calls ?? {};
  const count = (key: string) => {
    calls[key] = (calls[key] ?? 0) + 1;
  };
  const tx: any = {
    warehouse: {
      findFirst: jest.fn(async (args: any) => {
        count("warehouse.findFirst");
        if (options.warehouseActive === false) return null;
        if (args?.where?.companyId !== COMPANY_A) return null;
        return { id: WAREHOUSE, name: "Principal", code: "MAIN" };
      }),
    },
    product: {
      findMany: jest.fn(async (args: any) => {
        count("product.findMany");
        const companyId = args?.where?.companyId;
        const ids: string[] = args?.where?.id?.in ?? [];
        return options.products
          .filter(
            (product) =>
              product.companyId === companyId && ids.includes(product.id),
          )
          .map((product) => ({
            id: product.id,
            nombre: product.nombre,
            stock: product.stock,
            unitOfMeasure: product.unitOfMeasure ?? {
              code: "UNIT",
              name: "Unidad",
              symbol: "u",
              precision: 0,
              allowDecimals: false,
            },
            company: { productSource: product.productSource ?? null },
          }));
      }),
      updateMany: jest.fn(async () => {
        count("product.updateMany");
        return { count: 1 };
      }),
      findFirstOrThrow: jest.fn(async (args: any) => {
        count("product.findFirstOrThrow");
        return {
          stock: new Prisma.Decimal(
            String(
              options.products.find((p) => p.id === args?.where?.id)?.stock ??
                "0",
            ),
          ),
        };
      }),
    },
    inventoryMovement: {
      create: jest.fn(async ({ data }: any) => {
        count("inventoryMovement.create");
        return { id: `movement-${calls["inventoryMovement.create"]}`, ...data };
      }),
    },
    $queryRaw: jest.fn(async () => {
      count("$queryRaw");
      return [{ product_stock: "10", warehouse_total: "10" }];
    }),
  };
  const prisma = { $transaction: jest.fn(async (fn: any) => fn(tx)) };
  const service = new InventoryMutationService(prisma as any);
  jest
    .spyOn(service as any, "updateWarehouseStockByDelta")
    .mockImplementation(async () => {
      count("warehouseStock.update");
      return [{ previous_quantity: "10.000000", resulting_quantity: "7.000000" }];
    });
  return { service, tx, calls };
}

describe("InventoryMutationService.decreaseStockForSaleInTransaction (lote)", () => {
  it("resuelve productos y almacén UNA vez para N líneas", async () => {
    const { service, tx, calls } = buildTx({
      products: [
        { id: "p-1", nombre: "Producto 1", stock: new Prisma.Decimal("10"), companyId: COMPANY_A },
        { id: "p-2", nombre: "Producto 2", stock: new Prisma.Decimal("10"), companyId: COMPANY_A },
      ],
    });

    const results = await service.decreaseStockForSaleInTransaction(tx, {
      companyId: COMPANY_A,
      warehouseId: WAREHOUSE,
      saleId: SALE,
      items: [
        { productId: "p-1", quantity: "1", sourceItemId: "item-1" },
        { productId: "p-2", quantity: "2", sourceItemId: "item-2" },
        { productId: "p-1", quantity: "3", sourceItemId: "item-3" },
      ],
    });

    expect(results).toHaveLength(3);

    // ANTES del lote: 1 `product.findFirst` + 1 `warehouse.findFirst` por
    // línea (3 y 3). AHORA: exactamente 1 de cada, sin importar las líneas.
    expect(tx.product.findMany).toHaveBeenCalledTimes(1);
    expect(tx.warehouse.findFirst).toHaveBeenCalledTimes(1);

    // Los productos del lote se piden SIEMPRE con `companyId`.
    expect(tx.product.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: COMPANY_A, id: { in: ["p-1", "p-2"] } },
      }),
    );

    // Cada línea conserva su movimiento inmutable con el `sourceItemId` real.
    expect(tx.inventoryMovement.create).toHaveBeenCalledTimes(3);
    expect(
      tx.inventoryMovement.create.mock.calls.map((call: any[]) => call[0].data),
    ).toEqual([
      expect.objectContaining({
        companyId: COMPANY_A,
        productId: "p-1",
        sourceId: SALE,
        sourceItemId: "item-1",
        type: "SALE",
      }),
      expect.objectContaining({
        productId: "p-2",
        sourceItemId: "item-2",
        type: "SALE",
      }),
      expect.objectContaining({
        productId: "p-1",
        sourceItemId: "item-3",
        type: "SALE",
      }),
    ]);

    // 3 líneas → 6 consultas de inventario + 1 lote de productos + 1 almacén.
    expect(calls["product.findMany"]).toBe(1);
    expect(calls["warehouse.findFirst"]).toBe(1);
    expect(calls["product.updateMany"]).toBe(3);
    expect(calls["inventoryMovement.create"]).toBe(3);
  });

  it("no muta inventario de un producto de OTRA empresa", async () => {
    const { service, tx, calls } = buildTx({
      products: [
        {
          id: "p-ajeno",
          nombre: "Producto de B",
          stock: new Prisma.Decimal("10"),
          companyId: COMPANY_B,
        },
      ],
    });

    await expect(
      service.decreaseStockForSaleInTransaction(tx, {
        companyId: COMPANY_A,
        warehouseId: WAREHOUSE,
        saleId: SALE,
        items: [{ productId: "p-ajeno", quantity: "1" }],
      }),
    ).rejects.toBeInstanceOf(NotFoundException);

    expect(calls["inventoryMovement.create"]).toBeUndefined();
    expect(calls["product.updateMany"]).toBeUndefined();
    expect(tx.product.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { companyId: COMPANY_A, id: { in: ["p-ajeno"] } },
      }),
    );
  });

  it("rechaza el lote completo si el almacén no pertenece a la empresa o está inactivo", async () => {
    const { service, tx, calls } = buildTx({
      products: [
        { id: "p-1", nombre: "Producto 1", stock: new Prisma.Decimal("10"), companyId: COMPANY_A },
      ],
      warehouseActive: false,
    });

    await expect(
      service.decreaseStockForSaleInTransaction(tx, {
        companyId: COMPANY_A,
        warehouseId: WAREHOUSE,
        saleId: SALE,
        items: [{ productId: "p-1", quantity: "1" }],
      }),
    ).rejects.toMatchObject({ status: 409 });

    expect(calls["product.findMany"]).toBeUndefined();
    expect(calls["inventoryMovement.create"]).toBeUndefined();
  });

  it("mantiene la validación de precisión de unidad por línea", async () => {
    const { service, tx, calls } = buildTx({
      products: [
        {
          id: "p-unit",
          nombre: "Unidad entera",
          stock: new Prisma.Decimal("10"),
          companyId: COMPANY_A,
        },
      ],
    });

    await expect(
      service.decreaseStockForSaleInTransaction(tx, {
        companyId: COMPANY_A,
        warehouseId: WAREHOUSE,
        saleId: SALE,
        items: [{ productId: "p-unit", quantity: "1.5" }],
      }),
    ).rejects.toMatchObject({ status: 400 });

    expect(calls["inventoryMovement.create"]).toBeUndefined();
  });

  it("no ejecuta ninguna consulta con lista vacía", async () => {
    const { service, tx } = buildTx({ products: [] });

    const results = await service.decreaseStockForSaleInTransaction(tx, {
      companyId: COMPANY_A,
      warehouseId: WAREHOUSE,
      saleId: SALE,
      items: [],
    });

    expect(results).toEqual([]);
    expect(tx.product.findMany).not.toHaveBeenCalled();
    expect(tx.warehouse.findFirst).not.toHaveBeenCalled();
  });
});
