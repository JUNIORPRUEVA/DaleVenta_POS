import { Prisma } from "@prisma/client";
import {
  DEFAULT_TERMINAL_CODE,
  DEFAULT_WAREHOUSE_CODE,
  backfillZeroConfigInventoryForAllCompanies,
  backfillZeroConfigInventoryForCompany,
  provisionZeroConfigForNewCompany,
} from "./zero-config-inventory";

type Row = Record<string, any>;

function decimal(value: Prisma.Decimal.Value) {
  return new Prisma.Decimal(value);
}

function buildFakePrisma(seed: {
  companies: Row[];
  products?: Row[];
  warehouses?: Row[];
  terminals?: Row[];
  warehouseStocks?: Row[];
  states?: Row[];
}) {
  const db = {
    companies: [...seed.companies],
    products: [...(seed.products ?? [])],
    warehouses: [...(seed.warehouses ?? [])],
    terminals: [...(seed.terminals ?? [])],
    warehouseStocks: [...(seed.warehouseStocks ?? [])],
    states: [...(seed.states ?? [])],
  };
  let nextId = 1;
  const id = (prefix: string) => `${prefix}-${nextId++}`;

  const tx: any = {
    company: {
      findMany: jest.fn(async () => [...db.companies].sort((a, b) => a.id.localeCompare(b.id))),
      findUnique: jest.fn(async ({ where }) =>
        db.companies.find((row) => row.id === where.id) ?? null,
      ),
    },
    warehouse: {
      findUnique: jest.fn(async ({ where }) =>
        db.warehouses.find(
          (row) =>
            row.companyId === where.companyId_code.companyId &&
            row.code === where.companyId_code.code,
        ) ?? null,
      ),
      findFirst: jest.fn(async ({ where }) =>
        db.warehouses.find(
          (row) =>
            row.companyId === where.companyId &&
            row.isDefault === where.isDefault &&
            row.isActive === where.isActive,
        ) ?? null,
      ),
      create: jest.fn(async ({ data }) => {
        const row = { id: id("warehouse"), createdAt: new Date(), ...data };
        db.warehouses.push(row);
        return row;
      }),
      update: jest.fn(async ({ where, data }) => {
        const row = db.warehouses.find((item) => item.id === where.id);
        Object.assign(row, data);
        return row;
      }),
    },
    terminal: {
      findUnique: jest.fn(async ({ where }) =>
        db.terminals.find(
          (row) =>
            row.companyId === where.companyId_code.companyId &&
            row.code === where.companyId_code.code,
        ) ?? null,
      ),
      findFirst: jest.fn(async ({ where }) =>
        db.terminals.find(
          (row) =>
            row.companyId === where.companyId &&
            row.isDefault === where.isDefault &&
            row.isActive === where.isActive,
        ) ?? null,
      ),
      create: jest.fn(async ({ data }) => {
        const row = { id: id("terminal"), createdAt: new Date(), ...data };
        db.terminals.push(row);
        return row;
      }),
      update: jest.fn(async ({ where, data }) => {
        const row = db.terminals.find((item) => item.id === where.id);
        Object.assign(row, data);
        return row;
      }),
    },
    product: {
      findMany: jest.fn(async ({ where }) =>
        db.products
          .filter((row) => row.companyId === where.companyId)
          .sort((a, b) => a.id.localeCompare(b.id))
          .map((row) => ({ id: row.id, stock: row.stock })),
      ),
    },
    warehouseStock: {
      findMany: jest.fn(async ({ where }) =>
        db.warehouseStocks
          .filter(
            (row) =>
              row.companyId === where.companyId &&
              row.warehouseId === where.warehouseId &&
              where.productId.in.includes(row.productId),
          )
          .map((row) => ({ productId: row.productId, quantity: row.quantity })),
      ),
      create: jest.fn(async ({ data }) => {
        const row = { id: id("stock"), ...data };
        db.warehouseStocks.push(row);
        return row;
      }),
      createMany: jest.fn(async ({ data }) => {
        db.warehouseStocks.push(...data);
        return { count: data.length };
      }),
      count: jest.fn(async ({ where }) =>
        db.warehouseStocks.filter(
          (row) =>
            row.companyId === where.companyId &&
            row.warehouseId === where.warehouseId,
        ).length,
      ),
    },
    inventoryZeroConfigState: {
      findUnique: jest.fn(async ({ where }) =>
        db.states.find((row) => row.companyId === where.companyId) ?? null,
      ),
      upsert: jest.fn(async ({ where, create, update }) => {
        let row = db.states.find((item) => item.companyId === where.companyId);
        if (row) {
          Object.assign(row, update);
        } else {
          row = { ...create };
          db.states.push(row);
        }
        return row;
      }),
      update: jest.fn(async ({ where, data }) => {
        const row = db.states.find((item) => item.companyId === where.companyId);
        Object.assign(row, data);
        return row;
      }),
    },
  };

  return {
    db,
    prisma: {
      company: tx.company,
      $transaction: jest.fn(async (fn) => fn(tx)),
    } as any,
    tx,
  };
}

describe("W3 zero-config inventory backfill", () => {
  it("creates one default warehouse, terminal, and matching LOCAL stock per company", async () => {
    const { db, prisma } = buildFakePrisma({
      companies: [{ id: "company-a" }, { id: "company-b" }],
      products: [
        { id: "a-1", companyId: "company-a", stock: decimal("14.5"), productSource: null },
        { id: "a-2", companyId: "company-a", stock: decimal("7.625"), productSource: "LOCAL" },
        { id: "b-1", companyId: "company-b", stock: decimal("0.125") },
      ],
    });

    const summary = await backfillZeroConfigInventoryForAllCompanies(prisma);

    expect(summary.companyCount).toBe(2);
    expect(db.warehouses).toHaveLength(2);
    expect(db.terminals).toHaveLength(2);
    expect(db.warehouseStocks).toHaveLength(3);
    expect(db.warehouseStocks.map((row) => row.productId).sort()).toEqual([
      "a-1",
      "a-2",
      "b-1",
    ]);
    expect(db.warehouseStocks.map((row) => row.quantity.toFixed(6)).sort()).toEqual([
      "0.125000",
      "14.500000",
      "7.625000",
    ]);
    expect(db.warehouses.every((row) => row.code === DEFAULT_WAREHOUSE_CODE)).toBe(true);
    expect(db.terminals.every((row) => row.code === DEFAULT_TERMINAL_CODE)).toBe(true);
    expect(db.terminals.every((terminal) =>
      db.warehouses.some(
        (warehouse) =>
          warehouse.companyId === terminal.companyId &&
          warehouse.id === terminal.defaultWarehouseId,
      ),
    )).toBe(true);
  });

  it("does not create authoritative local stock for FULLPOS companies", async () => {
    const { db, prisma } = buildFakePrisma({
      companies: [{ id: "company-fullpos", productSource: "FULLPOS" }],
      products: [
        { id: "remote-1", companyId: "company-fullpos", stock: decimal("50.75") },
      ],
    });

    await backfillZeroConfigInventoryForAllCompanies(prisma);

    expect(db.warehouses).toHaveLength(1);
    expect(db.terminals).toHaveLength(1);
    expect(db.warehouseStocks).toHaveLength(0);
    expect(db.states[0]).toMatchObject({
      companyId: "company-fullpos",
      status: "COMPLETED",
      localProductCount: 0,
      warehouseStockCount: 0,
    });
  });

  it("is idempotent when run twice", async () => {
    const { db, prisma } = buildFakePrisma({
      companies: [{ id: "company-a" }],
      products: [
        { id: "a-1", companyId: "company-a", stock: decimal("50.75"), productSource: "LOCAL" },
      ],
    });

    await backfillZeroConfigInventoryForAllCompanies(prisma);
    const counts = {
      warehouses: db.warehouses.length,
      terminals: db.terminals.length,
      stocks: db.warehouseStocks.length,
      quantity: db.warehouseStocks[0].quantity.toFixed(6),
    };
    const second = await backfillZeroConfigInventoryForAllCompanies(prisma);

    expect(second.skipped).toBe(1);
    expect(db.warehouses).toHaveLength(counts.warehouses);
    expect(db.terminals).toHaveLength(counts.terminals);
    expect(db.warehouseStocks).toHaveLength(counts.stocks);
    expect(db.warehouseStocks[0].quantity.toFixed(6)).toBe(counts.quantity);
  });

  it("completes a partial retry without overwriting existing matching stock", async () => {
    const { db, tx } = buildFakePrisma({
      companies: [{ id: "company-a" }],
      products: [
        { id: "a-1", companyId: "company-a", stock: decimal("14.5"), productSource: "LOCAL" },
        { id: "a-2", companyId: "company-a", stock: decimal("7.625"), productSource: "LOCAL" },
      ],
      warehouses: [
        {
          id: "warehouse-existing",
          companyId: "company-a",
          code: DEFAULT_WAREHOUSE_CODE,
          isDefault: true,
          isActive: true,
          createdAt: new Date(),
        },
      ],
      warehouseStocks: [
        {
          id: "stock-existing",
          companyId: "company-a",
          warehouseId: "warehouse-existing",
          productId: "a-1",
          quantity: decimal("14.5"),
        },
      ],
      states: [{ companyId: "company-a", status: "IN_PROGRESS" }],
    });

    const result = await backfillZeroConfigInventoryForCompany(tx, "company-a");

    expect(result.createdWarehouseStocks).toBe(1);
    expect(db.warehouseStocks).toHaveLength(2);
    expect(
      db.warehouseStocks.find((stock) => stock.productId === "a-1")?.quantity.toFixed(6),
    ).toBe("14.500000");
  });

  it("refuses to overwrite stock that diverged after a partial run", async () => {
    const { tx } = buildFakePrisma({
      companies: [{ id: "company-a" }],
      products: [
        { id: "a-1", companyId: "company-a", stock: decimal("14.5"), productSource: "LOCAL" },
      ],
      warehouses: [
        {
          id: "warehouse-existing",
          companyId: "company-a",
          code: DEFAULT_WAREHOUSE_CODE,
          isDefault: true,
          isActive: true,
          createdAt: new Date(),
        },
      ],
      warehouseStocks: [
        {
          id: "stock-existing",
          companyId: "company-a",
          warehouseId: "warehouse-existing",
          productId: "a-1",
          quantity: decimal("1"),
        },
      ],
      states: [{ companyId: "company-a", status: "IN_PROGRESS" }],
    });

    await expect(
      backfillZeroConfigInventoryForCompany(tx, "company-a"),
    ).rejects.toThrow("refused to overwrite");
  });

  it("provisions new companies atomically with default warehouse and terminal", async () => {
    const { db, tx } = buildFakePrisma({
      companies: [{ id: "company-new" }],
    });

    await provisionZeroConfigForNewCompany(tx, "company-new");

    expect(db.warehouses).toHaveLength(1);
    expect(db.terminals).toHaveLength(1);
    expect(db.terminals[0].defaultWarehouseId).toBe(db.warehouses[0].id);
    expect(db.states[0]).toMatchObject({
      companyId: "company-new",
      status: "COMPLETED",
      localProductCount: 0,
      warehouseStockCount: 0,
    });
  });
});
