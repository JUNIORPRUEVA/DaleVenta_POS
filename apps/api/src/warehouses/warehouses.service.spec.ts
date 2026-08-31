import {
  BadRequestException,
  ConflictException,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { WarehousesService } from "./warehouses.service";

const userA = { id: "user-a", companyId: "company-a", role: "ADMIN" };
const userB = { id: "user-b", companyId: "company-b", role: "ADMIN" };

function row(overrides: Record<string, any>) {
  const now = new Date("2026-08-31T00:00:00.000Z");
  return { createdAt: now, updatedAt: now, deactivatedAt: null, ...overrides };
}

function buildService(source = "LOCAL") {
  const db = {
    warehouses: [
      row({
        id: "warehouse-main",
        companyId: "company-a",
        name: "Main Warehouse",
        code: "MAIN",
        isDefault: true,
        isActive: true,
      }),
      row({
        id: "warehouse-branch",
        companyId: "company-a",
        name: "Bavaro",
        code: "BAV",
        isDefault: false,
        isActive: true,
      }),
      row({
        id: "warehouse-other",
        companyId: "company-b",
        name: "Other",
        code: "OTH",
        isDefault: true,
        isActive: true,
      }),
    ],
    terminals: [
      row({
        id: "terminal-main",
        companyId: "company-a",
        name: "Caja Principal",
        code: "MAIN-POS",
        isDefault: true,
        isActive: true,
        defaultWarehouseId: "warehouse-main",
        deviceFingerprint: null,
      }),
    ],
    products: [
      {
        id: "product-a",
        companyId: "company-a",
        stock: new Prisma.Decimal(100),
      },
    ],
    warehouseStocks: [
      {
        id: "stock-main",
        companyId: "company-a",
        warehouseId: "warehouse-main",
        productId: "product-a",
        quantity: new Prisma.Decimal(70),
      },
      {
        id: "stock-branch",
        companyId: "company-a",
        warehouseId: "warehouse-branch",
        productId: "product-a",
        quantity: new Prisma.Decimal(30),
      },
    ],
    inventoryMovements: [] as any[],
  };

  const api = {
    warehouse: {
      findMany: jest.fn(async (args: any) =>
        db.warehouses
          .filter((warehouse) => warehouse.companyId === args.where.companyId)
          .map((warehouse) => ({
            ...warehouse,
            _count: args.include?._count
              ? {
                  defaultTerminals: db.terminals.filter(
                    (terminal) =>
                      terminal.companyId === warehouse.companyId &&
                      terminal.defaultWarehouseId === warehouse.id &&
                      terminal.isActive,
                  ).length,
                  stocks: db.warehouseStocks.filter(
                    (stock) =>
                      stock.companyId === warehouse.companyId &&
                      stock.warehouseId === warehouse.id,
                  ).length,
                }
              : undefined,
            stocks: args.include?.stocks
              ? db.warehouseStocks
                  .filter(
                    (stock) =>
                      stock.companyId === warehouse.companyId &&
                      stock.warehouseId === warehouse.id &&
                      stock.productId === args.include.stocks.where.productId,
                  )
                  .map((stock) => ({ quantity: stock.quantity }))
              : undefined,
          })),
      ),
      findFirst: jest.fn(
        async (args: any) =>
          db.warehouses.find((warehouse) =>
            Object.entries(args.where).every(([key, value]) => {
              if (key === "id") return warehouse.id === value;
              if (key === "companyId") return warehouse.companyId === value;
              if (key === "isActive") return warehouse.isActive === value;
              return true;
            }),
          ) ?? null,
      ),
      create: jest.fn(async (args: any) => {
        const item = row({
          id: `warehouse-${db.warehouses.length + 1}`,
          ...args.data,
        });
        db.warehouses.push(item);
        return item;
      }),
      update: jest.fn(async (args: any) => {
        const item = db.warehouses.find(
          (warehouse) => warehouse.id === args.where.id,
        );
        if (!item) throw new NotFoundException();
        Object.assign(item, args.data);
        return item;
      }),
      updateMany: jest.fn(async (args: any) => {
        let count = 0;
        for (const warehouse of db.warehouses) {
          const matches =
            warehouse.companyId === args.where.companyId &&
            (args.where.isDefault === undefined ||
              warehouse.isDefault === args.where.isDefault) &&
            (args.where.id?.not === undefined ||
              warehouse.id !== args.where.id.not);
          if (!matches) continue;
          Object.assign(warehouse, args.data);
          count += 1;
        }
        return { count };
      }),
    },
    warehouseStock: {
      count: jest.fn(
        async (args: any) =>
          db.warehouseStocks.filter(
            (stock) =>
              stock.companyId === args.where.companyId &&
              stock.warehouseId === args.where.warehouseId &&
              !stock.quantity.equals(0),
          ).length,
      ),
    },
    terminal: {
      count: jest.fn(
        async (args: any) =>
          db.terminals.filter(
            (terminal) =>
              terminal.companyId === args.where.companyId &&
              terminal.defaultWarehouseId === args.where.defaultWarehouseId &&
              terminal.isActive === args.where.isActive,
          ).length,
      ),
      findMany: jest.fn(async (args: any) =>
        db.terminals
          .filter((terminal) => terminal.companyId === args.where.companyId)
          .map((terminal) => ({
            ...terminal,
            defaultWarehouse: db.warehouses.find(
              (warehouse) => warehouse.id === terminal.defaultWarehouseId,
            ),
          })),
      ),
      findFirst: jest.fn(
        async (args: any) =>
          db.terminals.find(
            (terminal) =>
              terminal.id === args.where.id &&
              terminal.companyId === args.where.companyId,
          ) ?? null,
      ),
      update: jest.fn(async (args: any) => {
        const item = db.terminals.find(
          (terminal) => terminal.id === args.where.id,
        );
        if (!item) throw new NotFoundException();
        Object.assign(item, args.data);
        return {
          ...item,
          defaultWarehouse: db.warehouses.find(
            (warehouse) => warehouse.id === item.defaultWarehouseId,
          ),
        };
      }),
    },
    product: {
      findFirst: jest.fn(
        async (args: any) =>
          db.products.find(
            (product) =>
              product.id === args.where.id &&
              product.companyId === args.where.companyId,
          ) ?? null,
      ),
    },
    $transaction: jest.fn((fn: any) => fn(api)),
  };

  const resolver = {
    resolveForCompany: jest.fn(async () => ({
      source,
      readOnly: source !== "LOCAL",
    })),
  };

  return {
    service: new WarehousesService(api as any, resolver as any),
    db,
    api,
  };
}

describe("WarehousesService", () => {
  it("lists same-company warehouses only", async () => {
    const { service } = buildService();
    const result = await service.list(userA as any);
    expect(result.map((item) => item.id)).toEqual([
      "warehouse-main",
      "warehouse-branch",
    ]);
  });

  it("blocks cross-company warehouse metadata updates", async () => {
    const { service } = buildService();
    await expect(
      service.update(userA as any, "warehouse-other", { name: "Nope" }),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it("creates a second warehouse empty without stock or movements", async () => {
    const { service, db } = buildService();
    const beforeProductStock = db.products[0].stock.toString();
    const beforeStockRows = db.warehouseStocks.length;
    const beforeMovements = db.inventoryMovements.length;
    const created = await service.create(userA as any, {
      name: "Bávaro",
      code: "bavaro",
    });
    expect(created.isDefault).toBe(false);
    expect(created.isActive).toBe(true);
    expect(db.products[0].stock.toString()).toBe(beforeProductStock);
    expect(db.warehouseStocks).toHaveLength(beforeStockRows);
    expect(db.inventoryMovements).toHaveLength(beforeMovements);
  });

  it("sets exactly one default warehouse transactionally", async () => {
    const { service, db } = buildService();
    await service.setDefault(userA as any, "warehouse-branch");
    expect(
      db.warehouses.filter(
        (warehouse) =>
          warehouse.companyId === "company-a" && warehouse.isDefault,
      ),
    ).toHaveLength(1);
    expect(
      db.warehouses.find((item) => item.id === "warehouse-branch")?.isDefault,
    ).toBe(true);
  });

  it("rejects cross-company default change", async () => {
    const { service } = buildService();
    await expect(
      service.setDefault(userA as any, "warehouse-other"),
    ).rejects.toBeInstanceOf(NotFoundException);
  });

  it("blocks deactivation with non-zero stock", async () => {
    const { service } = buildService();
    await expect(
      service.deactivate(userA as any, "warehouse-branch"),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("blocks deactivation while active terminal uses warehouse", async () => {
    const { service, db } = buildService();
    db.warehouseStocks = [];
    await expect(
      service.deactivate(userA as any, "warehouse-main"),
    ).rejects.toBeInstanceOf(BadRequestException);
    db.warehouses.find((item) => item.id === "warehouse-main")!.isDefault =
      false;
    await expect(
      service.deactivate(userA as any, "warehouse-main"),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it("metadata edit preserves product stock and stock rows", async () => {
    const { service, db } = buildService();
    const beforeProductStock = db.products[0].stock.toString();
    const beforeStocks = db.warehouseStocks.map((stock) =>
      stock.quantity.toString(),
    );
    await service.update(userA as any, "warehouse-branch", {
      name: "Sucursal Bávaro",
      code: "BAV-2",
    });
    expect(db.products[0].stock.toString()).toBe(beforeProductStock);
    expect(
      db.warehouseStocks.map((stock) => stock.quantity.toString()),
    ).toEqual(beforeStocks);
  });

  it("stock breakdown totals reconcile", async () => {
    const { service } = buildService();
    const result = await service.productStockBreakdown(
      userA as any,
      "product-a",
    );
    expect(result.reconciled).toBe(true);
    expect(result.totalDecimal).toBe("100");
    expect(result.warehouseTotalDecimal).toBe("100");
    expect(
      result.warehouses.map((item) => item.quantityDecimal).sort(),
    ).toEqual(["30", "70"]);
  });

  it("returns safe read-only response for FULLPOS product source", async () => {
    const { service } = buildService("FULLPOS");
    const result = await service.productStockBreakdown(
      userA as any,
      "product-a",
    );
    expect(result.readOnly).toBe(true);
    expect(result.warehouses).toEqual([]);
  });

  it("reassigns terminal only to active same-company warehouse", async () => {
    const { service, db } = buildService();
    await service.updateTerminalWarehouse(userA as any, "terminal-main", {
      warehouseId: "warehouse-branch",
    });
    expect(db.terminals[0].defaultWarehouseId).toBe("warehouse-branch");
    await expect(
      service.updateTerminalWarehouse(userA as any, "terminal-main", {
        warehouseId: "warehouse-other",
      }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });
});
