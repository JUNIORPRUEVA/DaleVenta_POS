import { Prisma, PrismaClient, Role } from "@prisma/client";
import { InventoryMutationService } from "../src/inventory/inventory-mutation.service";
import { CashService } from "../src/cash/cash.service";
import { SalesService } from "../src/sales/sales.service";
import { TerminalResolutionService } from "../src/terminals/terminal-resolution.service";

const prisma = new PrismaClient();
const marker = "w8-terminal-fixture";
const d = (value: Prisma.Decimal.Value) => new Prisma.Decimal(value);

function taxService() {
  return {
    getCompanyFiscalSettings: async () => ({
      taxEnabled: false,
      defaultTaxRate: d(0),
      pricesIncludeTax: false,
      ncfEnabled: false,
    }),
    resolvePriceMode: () => "NO_TAX",
    calculatorService: {
      calculate: (input: any) => {
        const lines = input.lines.map((line: any, index: number) => {
          const grossAmount = new Prisma.Decimal(line.quantity).mul(line.unitPrice);
          return {
            index,
            grossAmount,
            discountAmount: d(0),
            taxableBase: d(0),
            taxRate: d(0),
            taxAmount: d(0),
            exemptAmount: grossAmount,
            taxIncluded: false,
            taxExempt: true,
            lineTotal: grossAmount,
          };
        });
        return {
          total: lines.reduce(
            (sum: Prisma.Decimal, line: any) => sum.plus(line.lineTotal),
            d(0),
          ),
          taxableBase: d(0),
          taxAmount: d(0),
          exemptAmount: lines.reduce(
            (sum: Prisma.Decimal, line: any) => sum.plus(line.lineTotal),
            d(0),
          ),
          discountAmount: d(0),
          lines,
        };
      },
      validateFiscalCustomer: () => undefined,
    },
  };
}

function salesService() {
  const terminals = new TerminalResolutionService(prisma as any);
  return new SalesService(
    prisma as any,
    { get: () => "" } as any,
    { emitCompany: () => undefined } as any,
    taxService() as any,
    {
      normalizeType: () => null,
      reserveNextNcf: async () => null,
      markIssued: async () => undefined,
    } as any,
    new InventoryMutationService(prisma as any),
    terminals,
  );
}

function cashService() {
  return new CashService(
    prisma as any,
    { emitCompany: () => undefined } as any,
    new TerminalResolutionService(prisma as any),
  );
}

async function cleanup(slugs: string[]) {
  const companies = await prisma.company.findMany({
    where: { slug: { in: slugs } },
    select: { id: true },
  });
  const companyIds = companies.map((company) => company.id);
  if (companyIds.length) {
    await prisma.inventoryMovement.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.sale.deleteMany({ where: { companyId: { in: companyIds } } });
    await prisma.cashSession.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.inventoryZeroConfigState.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.warehouseStock.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.terminal.deleteMany({ where: { companyId: { in: companyIds } } });
    await prisma.warehouse.deleteMany({
      where: { companyId: { in: companyIds } },
    });
    await prisma.product.deleteMany({ where: { companyId: { in: companyIds } } });
  }
  await prisma.company.deleteMany({ where: { slug: { in: slugs } } });
  await prisma.user.deleteMany({
    where: { email: { in: slugs.map((slug) => `${slug}@example.com`) } },
  });
}

async function createCompany(slug: string) {
  return prisma.company.create({ data: { name: slug, slug } });
}

async function createUser(companyId: string, email: string) {
  return prisma.user.create({
    data: {
      companyId,
      email,
      passwordHash: "w8-validation",
      nombreCompleto: "W8 Validator",
      telefono: "000",
      edad: 30,
      role: Role.ADMIN,
    },
  });
}

async function createWarehouse(companyId: string, code: string, isDefault = false) {
  return prisma.warehouse.create({
    data: { companyId, name: `${code} Warehouse`, code, isDefault, isActive: true },
  });
}

async function createTerminal(input: {
  companyId: string;
  defaultWarehouseId: string;
  code: string;
  isDefault?: boolean;
  isActive?: boolean;
  deviceFingerprint?: string | null;
}) {
  return prisma.terminal.create({
    data: {
      companyId: input.companyId,
      name: `${input.code} Terminal`,
      code: input.code,
      defaultWarehouseId: input.defaultWarehouseId,
      isDefault: input.isDefault ?? false,
      isActive: input.isActive ?? true,
      deviceFingerprint: input.deviceFingerprint ?? null,
    },
  });
}

async function createProduct(companyId: string, stock: Prisma.Decimal.Value) {
  return prisma.product.create({
    data: {
      companyId,
      nombre: `${marker}-product`,
      categoria: "W8",
      costo: d(10),
      precio: d(100),
      stock: d(stock),
      unitOfMeasureId: "UNIT",
    },
  });
}

async function seedStock(
  companyId: string,
  productId: string,
  warehouseId: string,
  quantity: Prisma.Decimal.Value,
) {
  await prisma.warehouseStock.create({
    data: { companyId, productId, warehouseId, quantity: d(quantity) },
  });
}

async function openCash(companyId: string, userId: string) {
  return prisma.cashSession.create({
    data: {
      companyId,
      openedByUserId: userId,
      userName: "W8 Validator",
      status: "OPEN",
      initialAmount: d(0),
    },
  });
}

async function sale(input: {
  companyId: string;
  userId: string;
  productId: string;
  terminalId?: string;
  deviceFingerprint?: string;
  warehouseId?: string;
  clientRequestId: string;
  qty?: number;
}) {
  return salesService().create(
    { id: input.userId, companyId: input.companyId, role: Role.ADMIN } as any,
    {
      clientRequestId: input.clientRequestId,
      terminalId: input.terminalId,
      deviceFingerprint: input.deviceFingerprint,
      warehouseId: input.warehouseId,
      items: [
        {
          productId: input.productId,
          qty: input.qty ?? 1,
          priceSoldUnit: 100,
        },
      ],
    },
  );
}

async function productState(companyId: string, productId: string) {
  const product = await prisma.product.findFirstOrThrow({
    where: { id: productId, companyId },
    select: { stock: true },
  });
  const stocks = await prisma.warehouseStock.findMany({
    where: { companyId, productId },
    orderBy: { warehouseId: "asc" },
    select: { warehouseId: true, quantity: true },
  });
  return {
    product: product.stock.toFixed(6),
    stocks: stocks.map((stock) => ({
      warehouseId: stock.warehouseId,
      quantity: stock.quantity.toFixed(6),
    })),
  };
}

async function main() {
  const slugs = [
    `${marker}-main`,
    `${marker}-ambiguous`,
    `${marker}-other-company`,
    `${marker}-device-other`,
    `${marker}-cash`,
    `${marker}-concurrent`,
  ];
  await cleanup(slugs);

  try {
    const company = await createCompany(slugs[0]);
    const user = await createUser(company.id, `${slugs[0]}@example.com`);
    await openCash(company.id, user.id);
    const mainWarehouse = await createWarehouse(company.id, "MAIN", true);
    const branchWarehouse = await createWarehouse(company.id, "BRANCH");
    const defaultTerminal = await createTerminal({
      companyId: company.id,
      code: "MAIN-POS",
      defaultWarehouseId: mainWarehouse.id,
      isDefault: true,
    });
    const branchTerminal = await createTerminal({
      companyId: company.id,
      code: "BRANCH-POS",
      defaultWarehouseId: branchWarehouse.id,
      deviceFingerprint: "install-branch",
    });
    const inactiveTerminal = await createTerminal({
      companyId: company.id,
      code: "INACTIVE-POS",
      defaultWarehouseId: mainWarehouse.id,
      isActive: false,
    });
    const product = await createProduct(company.id, "100");
    await seedStock(company.id, product.id, mainWarehouse.id, "50");
    await seedStock(company.id, product.id, branchWarehouse.id, "50");

    const legacySale = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      clientRequestId: "w8-legacy-default",
    });
    const explicitSale = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      terminalId: branchTerminal.id,
      clientRequestId: "w8-explicit-branch",
    });
    const deviceSale = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      deviceFingerprint: "install-branch",
      clientRequestId: "w8-device-branch",
    });
    const unknownDeviceSale = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      deviceFingerprint: "install-unknown",
      clientRequestId: "w8-device-default",
    });
    const mismatchRejected = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      terminalId: branchTerminal.id,
      warehouseId: mainWarehouse.id,
      clientRequestId: "w8-mismatch",
    }).then(
      () => false,
      () => true,
    );
    const inactiveRejected = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      terminalId: inactiveTerminal.id,
      clientRequestId: "w8-inactive",
    }).then(
      () => false,
      () => true,
    );

    const historicalBranchWarehouse = explicitSale.items[0].warehouseId;
    await prisma.terminal.update({
      where: { id: branchTerminal.id },
      data: { defaultWarehouseId: mainWarehouse.id },
    });
    const afterWarehouseChangeSale = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      terminalId: branchTerminal.id,
      clientRequestId: "w8-after-terminal-warehouse-change",
    });
    await prisma.terminal.update({
      where: { id: branchTerminal.id },
      data: { isActive: false, deactivatedAt: new Date() },
    });
    const deactivatedHistory = await prisma.sale.findFirstOrThrow({
      where: { id: explicitSale.id, companyId: company.id },
      select: {
        terminalId: true,
        terminalNameSnapshot: true,
        terminalCodeSnapshot: true,
        items: { select: { warehouseId: true, warehouseCodeSnapshot: true } },
      },
    });
    const deactivatedRejected = await sale({
      companyId: company.id,
      userId: user.id,
      productId: product.id,
      terminalId: branchTerminal.id,
      clientRequestId: "w8-deactivated-reject",
    }).then(
      () => false,
      () => true,
    );

    const otherCompany = await createCompany(slugs[2]);
    const otherUser = await createUser(otherCompany.id, `${slugs[2]}@example.com`);
    await openCash(otherCompany.id, otherUser.id);
    const otherWarehouse = await createWarehouse(otherCompany.id, "MAIN", true);
    await createTerminal({
      companyId: otherCompany.id,
      code: "MAIN-POS",
      defaultWarehouseId: otherWarehouse.id,
      isDefault: true,
    });
    const otherProduct = await createProduct(otherCompany.id, "10");
    await seedStock(otherCompany.id, otherProduct.id, otherWarehouse.id, "10");
    const crossCompanyTerminalRejected = await sale({
      companyId: otherCompany.id,
      userId: otherUser.id,
      productId: otherProduct.id,
      terminalId: defaultTerminal.id,
      clientRequestId: "w8-cross-terminal",
    }).then(
      () => false,
      () => true,
    );

    const ambiguousCompany = await createCompany(slugs[1]);
    const ambiguousWarehouse = await createWarehouse(ambiguousCompany.id, "MAIN");
    await createTerminal({
      companyId: ambiguousCompany.id,
      code: "A",
      defaultWarehouseId: ambiguousWarehouse.id,
    });
    await createTerminal({
      companyId: ambiguousCompany.id,
      code: "B",
      defaultWarehouseId: ambiguousWarehouse.id,
    });
    const ambiguousRejected = await new TerminalResolutionService(
      prisma as any,
    ).resolveForSale(prisma as any, { companyId: ambiguousCompany.id }).then(
      () => false,
      () => true,
    );

    const cashCompany = await createCompany(slugs[4]);
    const cashUser = await createUser(cashCompany.id, `${slugs[4]}@example.com`);
    const cashWarehouse = await createWarehouse(cashCompany.id, "MAIN", true);
    const cashTerminal = await createTerminal({
      companyId: cashCompany.id,
      code: "CASH-POS",
      defaultWarehouseId: cashWarehouse.id,
      deviceFingerprint: "cash-install",
    });
    const cashSession = await cashService().startSession(
      { id: cashUser.id, companyId: cashCompany.id, role: Role.ADMIN } as any,
      { openingAmount: 25, deviceFingerprint: "cash-install" },
    );

    const deviceOtherCompany = await createCompany(slugs[3]);
    const deviceOtherUser = await createUser(
      deviceOtherCompany.id,
      `${slugs[3]}@example.com`,
    );
    await openCash(deviceOtherCompany.id, deviceOtherUser.id);
    const deviceOtherWarehouse = await createWarehouse(
      deviceOtherCompany.id,
      "MAIN",
      true,
    );
    const deviceOtherTerminal = await createTerminal({
      companyId: deviceOtherCompany.id,
      code: "OTHER-POS",
      defaultWarehouseId: deviceOtherWarehouse.id,
      deviceFingerprint: "install-branch",
      isDefault: true,
    });
    const deviceOtherProduct = await createProduct(deviceOtherCompany.id, "10");
    await seedStock(
      deviceOtherCompany.id,
      deviceOtherProduct.id,
      deviceOtherWarehouse.id,
      "10",
    );
    const deviceOtherSale = await sale({
      companyId: deviceOtherCompany.id,
      userId: deviceOtherUser.id,
      productId: deviceOtherProduct.id,
      deviceFingerprint: "install-branch",
      clientRequestId: "w8-device-per-company",
    });

    const concurrentCompany = await createCompany(slugs[5]);
    const concurrentUser = await createUser(
      concurrentCompany.id,
      `${slugs[5]}@example.com`,
    );
    await openCash(concurrentCompany.id, concurrentUser.id);
    const concurrentWarehouse = await createWarehouse(
      concurrentCompany.id,
      "MAIN",
      true,
    );
    const concurrentTerminal = await createTerminal({
      companyId: concurrentCompany.id,
      code: "MAIN-POS",
      defaultWarehouseId: concurrentWarehouse.id,
      isDefault: true,
    });
    const concurrentProduct = await createProduct(concurrentCompany.id, "20");
    await seedStock(
      concurrentCompany.id,
      concurrentProduct.id,
      concurrentWarehouse.id,
      "20",
    );
    const concurrentResults = await Promise.allSettled([
      sale({
        companyId: concurrentCompany.id,
        userId: concurrentUser.id,
        productId: concurrentProduct.id,
        terminalId: concurrentTerminal.id,
        clientRequestId: "w8-concurrent-a",
      }),
      sale({
        companyId: concurrentCompany.id,
        userId: concurrentUser.id,
        productId: concurrentProduct.id,
        terminalId: concurrentTerminal.id,
        clientRequestId: "w8-concurrent-b",
      }),
    ]);

    const state = await productState(company.id, product.id);
    const concurrentState = await productState(
      concurrentCompany.id,
      concurrentProduct.id,
    );
    console.log(
      JSON.stringify(
        {
          legacyDefault: {
            terminalId: legacySale.terminalId,
            terminalCodeSnapshot: legacySale.terminalCodeSnapshot,
            warehouseId: legacySale.items[0].warehouseId,
            ok:
              legacySale.terminalId === defaultTerminal.id &&
              legacySale.items[0].warehouseId === mainWarehouse.id,
          },
          explicitTerminal: {
            terminalId: explicitSale.terminalId,
            terminalCodeSnapshot: explicitSale.terminalCodeSnapshot,
            warehouseId: explicitSale.items[0].warehouseId,
            ok:
              explicitSale.terminalId === branchTerminal.id &&
              explicitSale.items[0].warehouseId === branchWarehouse.id,
          },
          boundDevice: {
            terminalId: deviceSale.terminalId,
            ok: deviceSale.terminalId === branchTerminal.id,
          },
          unknownDeviceFallback: {
            terminalId: unknownDeviceSale.terminalId,
            ok: unknownDeviceSale.terminalId === defaultTerminal.id,
          },
          rejection: {
            mismatchRejected,
            inactiveRejected,
            crossCompanyTerminalRejected,
            ambiguousRejected,
            deactivatedRejected,
          },
          defaultWarehouseChange: {
            historicalWarehouseUnchanged:
              historicalBranchWarehouse === branchWarehouse.id &&
              deactivatedHistory.items[0].warehouseId === branchWarehouse.id,
            futureWarehouse:
              afterWarehouseChangeSale.items[0].warehouseId === mainWarehouse.id,
          },
          cashSession: {
            terminalId: cashSession.terminalId,
            terminalCode: cashSession.terminalCode,
            ok: cashSession.terminalId === cashTerminal.id,
          },
          multiCompanyDevice: {
            terminalId: deviceOtherSale.terminalId,
            ok: deviceOtherSale.terminalId === deviceOtherTerminal.id,
          },
          concurrency: {
            fulfilled: concurrentResults.filter((r) => r.status === "fulfilled")
              .length,
            rejected: concurrentResults.filter((r) => r.status === "rejected")
              .length,
            state: concurrentState,
          },
          productState: state,
        },
        null,
        2,
      ),
    );
  } finally {
    await cleanup(slugs);
    await prisma.$disconnect();
  }
}

main().catch(async (error) => {
  console.error(error);
  await prisma.$disconnect();
  process.exit(1);
});
