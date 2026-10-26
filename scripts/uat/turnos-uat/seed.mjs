/**
 * Seed FICTICIO para el UAT aislado de blindaje de turnos.
 *
 * Solo se ejecuta contra una base de datos local dedicada
 * (`daleventa_uat_local` en 127.0.0.1:55432). Nunca contra producción: la API
 * además aplica `assertSafeUatEnvironment` (fail-closed) con `APP_ENV=uat`.
 *
 * Datos: 1 empresa, 1 almacén, 2 terminales (una compartida), 3 empleados
 * (ADMIN + 2 CAJEROS) y 3 productos sin control de inventario (para que el UAT
 * se centre en caja/turnos).
 */
import { PrismaClient } from "@prisma/client";
import bcrypt from "bcryptjs";

const prisma = new PrismaClient();

const COMPANY_ID = "aaaaaaaa-0000-4000-8000-000000000001";
const WAREHOUSE_ID = "cccccccc-0000-4000-8000-000000000001";
const TERMINAL_1 = "dddddddd-0000-4000-8000-000000000001";
const TERMINAL_2 = "dddddddd-0000-4000-8000-000000000002";

export const USERS = {
  admin: {
    id: "bbbbbbbb-0000-4000-8000-00000000000a",
    email: "admin.uat@fullpos.local",
    name: "Admin UAT",
    role: "ADMIN",
    memberRole: "OWNER",
  },
  cajero1: {
    id: "bbbbbbbb-0000-4000-8000-00000000000b",
    email: "cajero1.uat@fullpos.local",
    name: "Cajero Uno",
    role: "CAJERO",
    memberRole: "CASHIER",
  },
  cajero2: {
    id: "bbbbbbbb-0000-4000-8000-00000000000c",
    email: "cajero2.uat@fullpos.local",
    name: "Cajero Dos",
    role: "CAJERO",
    memberRole: "CASHIER",
  },
};

export const PASSWORD = "Uat-1234!";
export const IDS = {
  companyId: COMPANY_ID,
  warehouseId: WAREHOUSE_ID,
  terminal1: TERMINAL_1,
  terminal2: TERMINAL_2,
};

const COMPANY_B_ID = "aaaaaaaa-0000-4000-8000-000000000002";
const WAREHOUSE_B_ID = "cccccccc-0000-4000-8000-000000000002";
const TERMINAL_B1 = "dddddddd-0000-4000-8000-0000000000b1";
const PRODUCT_B1_ID = "eeeeeeee-0000-4000-8000-0000000000b1";

async function main() {
  const passwordHash = await bcrypt.hash(PASSWORD, 10);

  await prisma.company.upsert({
    where: { id: COMPANY_ID },
    update: {},
    create: {
      id: COMPANY_ID,
      name: "Antonio Celulares UAT",
      slug: "antonio-celulares-uat",
      status: "ACTIVE",
      plan: "STANDARD",
      licenseStatus: "ACTIVE",
      licenseActivatedAt: new Date(),
      licenseExpiresAt: new Date(Date.now() + 365 * 86_400_000),
      maxUsers: 10,
      maxProducts: 1000,
      taxEnabled: false,
      ncfEnabled: false,
      inventoryEnabled: true,
      multiWarehouseEnabled: false,
      measurementUnitsEnabled: false,
    },
  });

  await prisma.unitOfMeasure.upsert({
    where: { companyId_code: { companyId: COMPANY_ID, code: "UNIT" } },
    update: {},
    create: {
      id: `uum-${COMPANY_ID}`,
      companyId: COMPANY_ID,
      code: "UNIT",
      name: "Unidad",
      symbol: "u",
      category: "COUNT",
      allowDecimals: false,
      precision: 0,
      active: true,
    },
  });

  await prisma.warehouse.upsert({
    where: { companyId_id: { companyId: COMPANY_ID, id: WAREHOUSE_ID } },
    update: {},
    create: {
      id: WAREHOUSE_ID,
      companyId: COMPANY_ID,
      name: "Almacén UAT",
      code: "WH1",
      isDefault: true,
      isActive: true,
    },
  });

  for (const terminal of [
    {
      id: TERMINAL_1,
      code: "T1",
      name: "Caja 1",
      deviceFingerprint: "device-A",
      isDefault: true,
    },
    {
      id: TERMINAL_2,
      code: "T2",
      name: "Caja 2",
      deviceFingerprint: "device-B",
      isDefault: false,
    },
  ]) {
    await prisma.terminal.upsert({
      where: { companyId_code: { companyId: COMPANY_ID, code: terminal.code } },
      update: {},
      create: {
        id: terminal.id,
        companyId: COMPANY_ID,
        name: terminal.name,
        code: terminal.code,
        defaultWarehouseId: WAREHOUSE_ID,
        isDefault: terminal.isDefault,
        isActive: true,
        deviceFingerprint: terminal.deviceFingerprint,
      },
    });
  }

  for (const user of Object.values(USERS)) {
    await prisma.user.upsert({
      where: { email: user.email },
      update: { passwordHash, blocked: false },
      create: {
        id: user.id,
        companyId: COMPANY_ID,
        email: user.email,
        passwordHash,
        nombreCompleto: user.name,
        telefono: '8090000000',
        edad: 30,
        role: user.role,
        blocked: false,
      },
    });
    await prisma.companyMember.upsert({
      where: {
        userId_companyId: { userId: user.id, companyId: COMPANY_ID },
      },
      update: { role: user.memberRole, status: "ACTIVE" },
      create: {
        userId: user.id,
        companyId: COMPANY_ID,
        role: user.memberRole,
        status: "ACTIVE",
        joinedAt: new Date(),
      },
    });
  }

  const products = [
    { id: "eeeeeeee-0000-4000-8000-000000000001", nombre: "Funda UAT", precio: 250, costo: 100 },
    { id: "eeeeeeee-0000-4000-8000-000000000002", nombre: "Cargador UAT", precio: 450, costo: 200 },
    { id: "eeeeeeee-0000-4000-8000-000000000003", nombre: "Audífonos UAT", precio: 800, costo: 400 },
  ];
  for (const product of products) {
    await prisma.product.upsert({
      where: { id: product.id },
      update: {},
      create: {
        id: product.id,
        companyId: COMPANY_ID,
        unitOfMeasureId: `uum-${COMPANY_ID}`,
        nombre: product.nombre,
        codigo: product.nombre.slice(0, 3).toUpperCase(),
        categoria: "UAT",
        costo: product.costo,
        precio: product.precio,
        stock: 0,
        trackInventory: false,
        itemType: "PRODUCT",
        taxTreatment: "INHERIT",
      },
    });
  }

  // ---------------------------------------------------------------------------
  // Segunda empresa FICTICIA: sirve para probar aislamiento multiempresa
  // (ninguna operación de A puede verse ni tocarse desde B).
  // ---------------------------------------------------------------------------
  await prisma.company.upsert({
    where: { id: COMPANY_B_ID },
    update: {},
    create: {
      id: COMPANY_B_ID,
      name: "Ferretería UAT B",
      slug: "ferreteria-uat-b",
      status: "ACTIVE",
      plan: "STANDARD",
      licenseStatus: "ACTIVE",
      licenseActivatedAt: new Date(),
      licenseExpiresAt: new Date(Date.now() + 365 * 86_400_000),
      maxUsers: 10,
      maxProducts: 1000,
      taxEnabled: false,
      ncfEnabled: false,
      inventoryEnabled: true,
      multiWarehouseEnabled: false,
      measurementUnitsEnabled: false,
    },
  });

  await prisma.unitOfMeasure.upsert({
    where: { companyId_code: { companyId: COMPANY_B_ID, code: "UNIT" } },
    update: {},
    create: {
      id: `uum-${COMPANY_B_ID}`,
      companyId: COMPANY_B_ID,
      code: "UNIT",
      name: "Unidad",
      symbol: "u",
      category: "COUNT",
      allowDecimals: false,
      precision: 0,
      active: true,
    },
  });

  await prisma.warehouse.upsert({
    where: { companyId_id: { companyId: COMPANY_B_ID, id: WAREHOUSE_B_ID } },
    update: {},
    create: {
      id: WAREHOUSE_B_ID,
      companyId: COMPANY_B_ID,
      name: "Almacén B",
      code: "WHB",
      isDefault: true,
      isActive: true,
    },
  });

  await prisma.terminal.upsert({
    where: { companyId_code: { companyId: COMPANY_B_ID, code: "TB1" } },
    update: {},
    create: {
      id: TERMINAL_B1,
      companyId: COMPANY_B_ID,
      name: "Caja B1",
      code: "TB1",
      defaultWarehouseId: WAREHOUSE_B_ID,
      isDefault: true,
      isActive: true,
      deviceFingerprint: "device-B1",
    },
  });

  const userB = {
    id: "bbbbbbbb-0000-4000-8000-0000000000b1",
    email: "cajero.uat.b@fullpos.local",
    name: "Cajero Empresa B",
  };
  await prisma.user.upsert({
    where: { email: userB.email },
    update: { passwordHash, blocked: false },
    create: {
      id: userB.id,
      companyId: COMPANY_B_ID,
      email: userB.email,
      passwordHash,
      nombreCompleto: userB.name,
      telefono: "8090000001",
      edad: 30,
      role: "CAJERO",
      blocked: false,
    },
  });
  await prisma.companyMember.upsert({
    where: { userId_companyId: { userId: userB.id, companyId: COMPANY_B_ID } },
    update: { role: "CASHIER", status: "ACTIVE" },
    create: {
      userId: userB.id,
      companyId: COMPANY_B_ID,
      role: "CASHIER",
      status: "ACTIVE",
      joinedAt: new Date(),
    },
  });

  await prisma.product.upsert({
    where: { id: PRODUCT_B1_ID },
    update: {},
    create: {
      id: PRODUCT_B1_ID,
      companyId: COMPANY_B_ID,
      unitOfMeasureId: `uum-${COMPANY_B_ID}`,
      nombre: "Producto B",
      codigo: "PB1",
      categoria: "UAT",
      costo: 50,
      precio: 100,
      stock: 0,
      trackInventory: false,
      itemType: "PRODUCT",
      taxTreatment: "INHERIT",
    },
  });

  const counts = {
    companies: await prisma.company.count(),
    users: await prisma.user.count(),
    terminals: await prisma.terminal.count(),
    products: await prisma.product.count(),
  };
  console.log("[seed] OK", JSON.stringify({ ...counts, companyId: COMPANY_ID }));
}

main()
  .catch((error) => {
    console.error("[seed] FAILED", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
