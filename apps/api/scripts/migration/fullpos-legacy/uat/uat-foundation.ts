/**
 * UAT foundation seed: creates the LOCKED tenant identity in a disposable local
 * UAT database so the migration can be rehearsed against the real Cloud schema.
 *
 * Rules:
 *  - idempotent (upsert by locked ids, no duplicate rows)
 *  - local UAT only: the caller MUST have already passed the environment guard
 *  - never copies production users/credentials; the owner password is either taken
 *    from UAT_OWNER_PASSWORD or generated locally and never printed
 *  - optional DECOY tenant (a second, unrelated company with its own rows) used to
 *    prove that the import cannot touch another tenant's data
 */

import { randomBytes } from 'node:crypto';
import bcrypt from 'bcryptjs';
import type { PrismaClient } from '@prisma/client';
import {
  TARGET_COMPANY_ID,
  TARGET_COMPANY_NAME,
  TARGET_OWNER_USER_ID,
  TARGET_TERMINAL_ID,
  TARGET_WAREHOUSE_ID,
  UNIT_OF_MEASURE_CODE,
} from '../constants';

export const UAT_OWNER_EMAIL = 'uat.owner@daleventa.local';

/** Unrelated tenant used as an isolation canary. Never touched by the migration. */
export const UAT_DECOY = {
  companyId: '1b2c3d4e-5f60-4711-8223-334455667788',
  warehouseId: '1b2c3d4e-5f60-4711-8223-334455667789',
  terminalId: '1b2c3d4e-5f60-4711-8223-334455667790',
  userId: '1b2c3d4e-5f60-4711-8223-334455667791',
  productId: '1b2c3d4e-5f60-4711-8223-334455667792',
  cashSessionId: '1b2c3d4e-5f60-4711-8223-334455667793',
  saleId: '1b2c3d4e-5f60-4711-8223-334455667794',
  saleItemId: '1b2c3d4e-5f60-4711-8223-334455667795',
  companyName: 'UAT Decoy Tenant',
  slug: 'uat-decoy-tenant',
  email: 'uat.decoy@daleventa.local',
} as const;

export type SeedOptions = {
  ownerPassword?: string | null;
  includeDecoy?: boolean;
  now?: Date;
};

export type SeedSummary = {
  companyId: string;
  warehouseId: string;
  terminalId: string;
  ownerUserId: string;
  ownerEmail: string;
  passwordGenerated: boolean;
  decoy: boolean;
};

function passwordFor(options: SeedOptions): { password: string; generated: boolean } {
  const fromEnv = options.ownerPassword ?? process.env.UAT_OWNER_PASSWORD ?? null;
  if (fromEnv && fromEnv.trim().length > 0) {
    return { password: fromEnv, generated: false };
  }
  return { password: randomBytes(24).toString('base64url'), generated: true };
}

export async function seedUatFoundation(
  prisma: PrismaClient,
  options: SeedOptions = {},
): Promise<SeedSummary> {
  const now = options.now ?? new Date();
  const trialEndsAt = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000);
  const { password, generated } = passwordFor(options);
  const passwordHash = bcrypt.hashSync(password, 10);

  await prisma.company.upsert({
    where: { id: TARGET_COMPANY_ID },
    update: {},
    create: {
      id: TARGET_COMPANY_ID,
      name: TARGET_COMPANY_NAME,
      slug: 'cafeteria-la-bomba-uat',
      status: 'ACTIVE',
      plan: 'STANDARD',
      licenseStatus: 'TRIAL',
      trialStartedAt: now,
      trialEndsAt,
      maxUsers: 2,
      maxProducts: 100,
      taxEnabled: false,
      ncfEnabled: false,
      pricesIncludeTax: false,
      inventoryEnabled: true,
      measurementUnitsEnabled: false,
      multiWarehouseEnabled: false,
      productSource: null,
    },
  });

  await prisma.warehouse.upsert({
    where: { id: TARGET_WAREHOUSE_ID },
    update: {},
    create: {
      id: TARGET_WAREHOUSE_ID,
      companyId: TARGET_COMPANY_ID,
      name: 'Almacén principal',
      code: 'MAIN',
      isDefault: true,
      isActive: true,
    },
  });

  await prisma.terminal.upsert({
    where: { id: TARGET_TERMINAL_ID },
    update: {},
    create: {
      id: TARGET_TERMINAL_ID,
      companyId: TARGET_COMPANY_ID,
      name: 'Caja principal',
      code: 'DEFAULT',
      defaultWarehouseId: TARGET_WAREHOUSE_ID,
      isDefault: true,
      isActive: true,
    },
  });

  await prisma.user.upsert({
    where: { id: TARGET_OWNER_USER_ID },
    update: {},
    create: {
      id: TARGET_OWNER_USER_ID,
      companyId: TARGET_COMPANY_ID,
      email: UAT_OWNER_EMAIL,
      passwordHash,
      nombreCompleto: 'UAT Owner',
      telefono: '0000000000',
      edad: 30,
      role: 'ADMIN',
      userPermissions: {},
      blocked: false,
    },
  });

  await prisma.companyMember.upsert({
    where: { userId_companyId: { userId: TARGET_OWNER_USER_ID, companyId: TARGET_COMPANY_ID } },
    update: {},
    create: {
      userId: TARGET_OWNER_USER_ID,
      companyId: TARGET_COMPANY_ID,
      role: 'OWNER',
      status: 'ACTIVE',
      invitedBy: null,
      joinedAt: now,
    },
  });

  if (options.includeDecoy) {
    await seedDecoyTenant(prisma, now);
  }

  return {
    companyId: TARGET_COMPANY_ID,
    warehouseId: TARGET_WAREHOUSE_ID,
    terminalId: TARGET_TERMINAL_ID,
    ownerUserId: TARGET_OWNER_USER_ID,
    ownerEmail: UAT_OWNER_EMAIL,
    passwordGenerated: generated,
    decoy: options.includeDecoy === true,
  };
}

/**
 * Second tenant with its own rows. Its rows must be byte-identical before and after
 * the import/rollback: that is the cross-tenant contamination canary.
 */
async function seedDecoyTenant(prisma: PrismaClient, now: Date): Promise<void> {
  const decoyHash = bcrypt.hashSync(randomBytes(24).toString('base64url'), 10);

  await prisma.company.upsert({
    where: { id: UAT_DECOY.companyId },
    update: {},
    create: {
      id: UAT_DECOY.companyId,
      name: UAT_DECOY.companyName,
      slug: UAT_DECOY.slug,
      status: 'ACTIVE',
      plan: 'STANDARD',
      licenseStatus: 'TRIAL',
      trialStartedAt: now,
      trialEndsAt: new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000),
      maxUsers: 2,
      maxProducts: 100,
    },
  });

  await prisma.warehouse.upsert({
    where: { id: UAT_DECOY.warehouseId },
    update: {},
    create: {
      id: UAT_DECOY.warehouseId,
      companyId: UAT_DECOY.companyId,
      name: 'Decoy warehouse',
      code: 'DECOY',
      isDefault: true,
      isActive: true,
    },
  });

  await prisma.terminal.upsert({
    where: { id: UAT_DECOY.terminalId },
    update: {},
    create: {
      id: UAT_DECOY.terminalId,
      companyId: UAT_DECOY.companyId,
      name: 'Decoy terminal',
      code: 'DECOY',
      defaultWarehouseId: UAT_DECOY.warehouseId,
      isDefault: true,
      isActive: true,
    },
  });

  await prisma.user.upsert({
    where: { id: UAT_DECOY.userId },
    update: {},
    create: {
      id: UAT_DECOY.userId,
      companyId: UAT_DECOY.companyId,
      email: UAT_DECOY.email,
      passwordHash: decoyHash,
      nombreCompleto: 'UAT Decoy Owner',
      telefono: '0000000001',
      edad: 30,
      role: 'ADMIN',
      userPermissions: {},
      blocked: false,
    },
  });

  await prisma.companyMember.upsert({
    where: { userId_companyId: { userId: UAT_DECOY.userId, companyId: UAT_DECOY.companyId } },
    update: {},
    create: {
      userId: UAT_DECOY.userId,
      companyId: UAT_DECOY.companyId,
      role: 'OWNER',
      status: 'ACTIVE',
      joinedAt: now,
    },
  });

  await prisma.product.upsert({
    where: { id: UAT_DECOY.productId },
    update: {},
    create: {
      id: UAT_DECOY.productId,
      companyId: UAT_DECOY.companyId,
      unitOfMeasureId: UNIT_OF_MEASURE_CODE,
      nombre: 'DECOY PRODUCT',
      codigo: 'DECOY-001',
      categoria: 'Decoy',
      costo: '1.00',
      precio: '2.00',
      stock: '5.00',
    },
  });

  await prisma.warehouseStock.upsert({
    where: {
      companyId_warehouseId_productId: {
        companyId: UAT_DECOY.companyId,
        warehouseId: UAT_DECOY.warehouseId,
        productId: UAT_DECOY.productId,
      },
    },
    update: {},
    create: {
      companyId: UAT_DECOY.companyId,
      warehouseId: UAT_DECOY.warehouseId,
      productId: UAT_DECOY.productId,
      quantity: '5.00',
    },
  });

  await prisma.cashSession.upsert({
    where: { id: UAT_DECOY.cashSessionId },
    update: {},
    create: {
      id: UAT_DECOY.cashSessionId,
      companyId: UAT_DECOY.companyId,
      openedByUserId: UAT_DECOY.userId,
      terminalId: UAT_DECOY.terminalId,
      userName: 'DECOY',
      status: 'CLOSED',
      openedAt: now,
      closedAt: now,
      initialAmount: '0.00',
      closingAmount: '0.00',
      expectedAmount: '2.00',
      difference: '-2.00',
      businessDate: now.toISOString().slice(0, 10),
    },
  });

  await prisma.sale.upsert({
    where: { id: UAT_DECOY.saleId },
    update: {},
    create: {
      id: UAT_DECOY.saleId,
      companyId: UAT_DECOY.companyId,
      userId: UAT_DECOY.userId,
      terminalId: UAT_DECOY.terminalId,
      cashSessionId: UAT_DECOY.cashSessionId,
      clientRequestId: 'DECOY-SALE-1',
      saleDate: now,
      paymentMethod: 'cash',
      paymentCashAmount: '2.00',
      totalSold: '2.00',
      totalCost: '1.00',
      totalProfit: '1.00',
      commissionRate: '0.0000',
      commissionAmount: '0.00',
      status: 'PAID',
    },
  });

  await prisma.saleItem.upsert({
    where: { id: UAT_DECOY.saleItemId },
    update: {},
    create: {
      id: UAT_DECOY.saleItemId,
      saleId: UAT_DECOY.saleId,
      productId: UAT_DECOY.productId,
      productSource: 'LOCAL',
      productNameSnapshot: 'DECOY PRODUCT',
      qty: '1.000000',
      priceSoldUnit: '2.00',
      grossAmount: '2.00',
      costUnitSnapshot: '1.00',
      subtotalSold: '2.00',
      subtotalCost: '1.00',
      profit: '1.00',
      inventoryTrackedSnapshot: false,
    },
  });
}

/** Row counts of the decoy tenant (isolation canary). */
export async function readDecoyState(prisma: PrismaClient): Promise<Record<string, number>> {
  const companyId = UAT_DECOY.companyId;
  const [products, warehouseStocks, cashSessions, sales, saleItems, companies, users] =
    await Promise.all([
      prisma.product.count({ where: { companyId } }),
      prisma.warehouseStock.count({ where: { companyId } }),
      prisma.cashSession.count({ where: { companyId } }),
      prisma.sale.count({ where: { companyId } }),
      prisma.saleItem.count({ where: { sale: { companyId } } }),
      prisma.company.count({}),
      prisma.user.count({ where: { companyId } }),
    ]);
  return { products, warehouseStocks, cashSessions, sales, saleItems, companies, users };
}
