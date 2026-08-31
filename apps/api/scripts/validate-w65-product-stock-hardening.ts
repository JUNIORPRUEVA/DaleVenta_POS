import {
  InventoryMovementType,
  Prisma,
  PrismaClient,
  ProductSource,
  Role,
} from "@prisma/client";
import { InventoryMutationService } from "../src/inventory/inventory-mutation.service";
import { ProductsService } from "../src/products/products.service";

const prisma = new PrismaClient();
const marker = "w65-product-fixture";
const d = (value: Prisma.Decimal.Value) => new Prisma.Decimal(value);

function productsService(source: ProductSource | null = null) {
  return new ProductsService(
    prisma as any,
    {} as any,
    {
      resolveForCompany: async (companyId: string) => ({
        companyId,
        source: source ?? "LOCAL",
        readOnly: source === ProductSource.FULLPOS || source === ProductSource.FULLPOS_DIRECT,
        fullposCompanyId: null,
        supportsDecimalStock: true,
        supportsNativeUom: true,
        supportsProductCreate: source !== ProductSource.FULLPOS,
        supportsProductEdit: source !== ProductSource.FULLPOS,
        supportsStockAdjustment: source !== ProductSource.FULLPOS,
        resolution: "w65-validation",
      }),
    } as any,
    { get: () => "" } as any,
    { assertCanCreateProduct: async () => undefined } as any,
    new InventoryMutationService(prisma as any),
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

async function createCompany(slug: string, source?: ProductSource) {
  return prisma.company.create({
    data: { name: slug, slug, productSource: source ?? null },
  });
}

async function createUser(companyId: string, email: string) {
  return prisma.user.create({
    data: {
      companyId,
      email,
      passwordHash: "w65-validation",
      nombreCompleto: "W65 Validator",
      telefono: "000",
      edad: 30,
      role: Role.ADMIN,
    },
  });
}

async function createWarehouse(companyId: string, code: string, isDefault = false) {
  return prisma.warehouse.create({
    data: { companyId, name: code, code, isDefault, isActive: true },
  });
}

async function state(companyId: string, productId: string, warehouseId: string) {
  const product = await prisma.product.findFirstOrThrow({
    where: { id: productId, companyId },
    select: { stock: true },
  });
  const warehouseStock = await prisma.warehouseStock.findFirstOrThrow({
    where: { companyId, productId, warehouseId },
    select: { quantity: true },
  });
  const movements = await prisma.inventoryMovement.findMany({
    where: { companyId, productId, warehouseId },
    orderBy: { createdAt: "asc" },
    select: {
      type: true,
      quantityDelta: true,
      sourceType: true,
      sourceId: true,
      reason: true,
    },
  });
  return {
    product: product.stock.toFixed(6),
    warehouse: warehouseStock.quantity.toFixed(6),
    movements: movements.map((movement) => ({
      ...movement,
      quantityDelta: movement.quantityDelta.toFixed(6),
    })),
  };
}

async function main() {
  const slugs = [
    `${marker}-main`,
    `${marker}-multi`,
    `${marker}-tenant`,
    `${marker}-fullpos`,
    `${marker}-lost`,
    `${marker}-rollback`,
  ];
  await cleanup(slugs);

  try {
    const service = productsService();
    const company = await createCompany(slugs[0]);
    const user = await createUser(company.id, `${slugs[0]}@example.com`);
    const warehouse = await createWarehouse(company.id, "MAIN", true);
    const actor = { id: user.id, companyId: company.id, role: Role.ADMIN };

    const initialProduct = await service.create(actor, {
      nombre: "W65 Initial 14.5",
      categoria: "W65",
      precio: 2,
      costo: 1,
      stock: 14.5,
      unitOfMeasureId: "YARD",
    });
    const initialState = await state(company.id, initialProduct.id, warehouse.id);

    const zeroProduct = await service.create(actor, {
      nombre: "W65 Zero",
      categoria: "W65",
      precio: 2,
      costo: 1,
      stock: 0,
      unitOfMeasureId: "YARD",
    });
    const zeroState = await state(company.id, zeroProduct.id, warehouse.id);

    await service.update(actor, initialProduct.id, {
      nombre: "W65 Initial Renamed",
      precio: 3,
      stock: 14.5,
    });
    const metadataState = await state(company.id, initialProduct.id, warehouse.id);
    const metadataStockChangeRejected = await service
      .update(actor, initialProduct.id, {
        nombre: "W65 Bad Stock Edit",
        stock: 99,
      })
      .then(
        () => false,
        () => true,
      );

    await service.adjustStock(actor, initialProduct.id, {
      delta: 7.625,
      reason: "W65 delta increase",
    });
    await service.adjustStock(actor, initialProduct.id, {
      delta: -0.125,
      reason: "W65 delta decrease",
    });
    await service.adjustStock(actor, initialProduct.id, {
      stock: 50.75,
      expectedCurrentStock: 22,
      reason: "W65 counted correction",
    });
    const adjustedState = await state(company.id, initialProduct.id, warehouse.id);

    const staleCountRejected = await service
      .adjustStock(actor, initialProduct.id, {
        stock: 7,
        expectedCurrentStock: 10,
      })
      .then(
        () => false,
        () => true,
      );

    const multiCompany = await createCompany(slugs[1]);
    const multiUser = await createUser(multiCompany.id, `${slugs[1]}@example.com`);
    const multiMain = await createWarehouse(multiCompany.id, "MAIN", true);
    const multiBranch = await createWarehouse(multiCompany.id, "BRANCH");
    const multiActor = {
      id: multiUser.id,
      companyId: multiCompany.id,
      role: Role.ADMIN,
    };
    const multiProduct = await productsService().create(multiActor, {
      nombre: "W65 Multi",
      categoria: "W65",
      precio: 2,
      costo: 1,
      stock: 10,
      unitOfMeasureId: "YARD",
      warehouseId: multiMain.id,
    });
    await prisma.warehouseStock.create({
      data: {
        companyId: multiCompany.id,
        warehouseId: multiBranch.id,
        productId: multiProduct.id,
        quantity: d(0),
      },
    });
    const ambiguousRejected = await service
      .adjustStock(multiActor, multiProduct.id, { stock: 9 })
      .then(
        () => false,
        () => true,
      );
    await service.adjustStock(multiActor, multiProduct.id, {
      warehouseId: multiMain.id,
      delta: 0.125,
    });
    const explicitState = await state(multiCompany.id, multiProduct.id, multiMain.id);

    const tenantCompany = await createCompany(slugs[2]);
    const tenantWarehouse = await createWarehouse(tenantCompany.id, "MAIN", true);
    const crossWarehouseRejected = await service
      .adjustStock(actor, initialProduct.id, {
        warehouseId: tenantWarehouse.id,
        delta: 1,
      })
      .then(
        () => false,
        () => true,
      );
    const crossProductRejected = await service
      .adjustStock(actor, multiProduct.id, { warehouseId: warehouse.id, delta: 1 })
      .then(
        () => false,
        () => true,
      );

    const fullposCompany = await createCompany(slugs[3], ProductSource.FULLPOS);
    const fullposUser = await createUser(
      fullposCompany.id,
      `${slugs[3]}@example.com`,
    );
    await createWarehouse(fullposCompany.id, "MAIN", true);
    const fullposRejected = await productsService(ProductSource.FULLPOS)
      .create(
        { id: fullposUser.id, companyId: fullposCompany.id, role: Role.ADMIN },
        {
          nombre: "W65 Fullpos",
          categoria: "W65",
          precio: 2,
          costo: 1,
          stock: 1,
        },
      )
      .then(
        () => false,
        () => true,
      );

    const lostCompany = await createCompany(slugs[4]);
    const lostUser = await createUser(lostCompany.id, `${slugs[4]}@example.com`);
    const lostWarehouse = await createWarehouse(lostCompany.id, "MAIN", true);
    const lostActor = { id: lostUser.id, companyId: lostCompany.id, role: Role.ADMIN };
    const lostProduct = await service.create(lostActor, {
      nombre: "W65 Lost Update",
      categoria: "W65",
      precio: 2,
      costo: 1,
      stock: 10,
      unitOfMeasureId: "YARD",
    });
    const inventory = new InventoryMutationService(prisma as any);
    await inventory.decreaseStock({
      companyId: lostCompany.id,
      productId: lostProduct.id,
      warehouseId: lostWarehouse.id,
      quantity: 2,
      type: InventoryMovementType.SALE,
      sourceType: "SALE",
      sourceId: lostProduct.id,
      reason: "W65 sale simulation",
      createdByUserId: lostUser.id,
    });
    const lostUpdateRejected = await service
      .adjustStock(lostActor, lostProduct.id, {
        stock: 7,
        expectedCurrentStock: 10,
      })
      .then(
        () => false,
        () => true,
      );
    const lostState = await state(lostCompany.id, lostProduct.id, lostWarehouse.id);

    const rollbackCompany = await createCompany(slugs[5]);
    const rollbackUser = await createUser(
      rollbackCompany.id,
      `${slugs[5]}@example.com`,
    );
    const rollbackWarehouse = await createWarehouse(rollbackCompany.id, "MAIN", true);
    const rollbackProduct = await prisma.product.create({
      data: {
        companyId: rollbackCompany.id,
        nombre: "W65 Drift",
        categoria: "W65",
        precio: d(2),
        costo: d(1),
        stock: d(10),
        unitOfMeasureId: "YARD",
      },
    });
    await prisma.warehouseStock.create({
      data: {
        companyId: rollbackCompany.id,
        warehouseId: rollbackWarehouse.id,
        productId: rollbackProduct.id,
        quantity: d(9),
      },
    });
    const driftRejected = await service
      .adjustStock(
        { id: rollbackUser.id, companyId: rollbackCompany.id, role: Role.ADMIN },
        rollbackProduct.id,
        { delta: 1 },
      )
      .then(
        () => false,
        () => true,
      );
    const rollbackMovementCount = await prisma.inventoryMovement.count({
      where: { companyId: rollbackCompany.id },
    });

    console.log(
      JSON.stringify(
        {
          productCreation: {
            initialState,
            initialMovementCount: initialState.movements.filter(
              (movement) => movement.type === InventoryMovementType.INITIAL_STOCK,
            ).length,
          },
          zeroStockProduct: {
            zeroState,
            noZeroMovement: zeroState.movements.length === 0,
          },
          productEdit: {
            metadataState,
            metadataStockChangeRejected,
          },
          adjustments: {
            adjustedState,
            staleCountRejected,
          },
          multiWarehouse: {
            ambiguousRejected,
            explicitState,
          },
          tenantSecurity: {
            crossWarehouseRejected,
            crossProductRejected,
          },
          fullposHandling: { fullposRejected },
          lostUpdate: {
            lostUpdateRejected,
            lostState,
          },
          rollback: {
            driftRejected,
            rollbackMovementCount,
          },
        },
        null,
        2,
      ),
    );
  } finally {
    await cleanup(slugs);
  }
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
