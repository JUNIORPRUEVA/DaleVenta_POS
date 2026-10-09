#!/usr/bin/env node

/* eslint-disable no-console */

const { PrismaClient, Prisma } = require('@prisma/client');
const { createHash } = require('node:crypto');

const prisma = new PrismaClient();

function arg(name, fallback = null) {
  const prefix = `--${name}=`;
  const found = process.argv.find((item) => item.startsWith(prefix));
  return found ? found.slice(prefix.length) : fallback;
}

function hasFlag(name) {
  return process.argv.includes(`--${name}`);
}

function intArg(name, fallback) {
  const parsed = Number(arg(name, fallback));
  if (!Number.isFinite(parsed) || parsed < 0) {
    throw new Error(`Invalid --${name}`);
  }
  return Math.trunc(parsed);
}

function scaleFromProfile() {
  const profile = (arg('profile', '') ?? '').toLowerCase();
  if (!profile) return null;
  if (profile === '1k' || profile === '1000') return 1000;
  if (profile === '10k' || profile === '10000') return 10000;
  if (profile === '50k' || profile === '50000') return 50000;
  throw new Error('Invalid --profile. Use 1k, 10k or 50k.');
}

function assertWriteAllowed() {
  if (!hasFlag('execute')) return;
  const appEnv = (process.env.APP_ENV ?? '').toLowerCase();
  const uatLocal = (process.env.UAT_LOCAL_ONLY ?? '').toLowerCase() === 'true';
  const explicit = process.env.LARGE_DATA_GENERATOR_ALLOW_WRITE === 'true';
  if (appEnv !== 'uat' && !uatLocal && !explicit) {
    throw new Error(
      'Refusing writes. Set APP_ENV=uat, UAT_LOCAL_ONLY=true, or LARGE_DATA_GENERATOR_ALLOW_WRITE=true for disposable local/UAT only.',
    );
  }
  const databaseUrl = process.env.DATABASE_URL ?? '';
  if (/prod|production|gcdndd|easypanel/i.test(databaseUrl)) {
    throw new Error('Refusing writes against a protected-looking DATABASE_URL.');
  }
}

function chunk(items, size) {
  const chunks = [];
  for (let index = 0; index < items.length; index += size) {
    chunks.push(items.slice(index, index + size));
  }
  return chunks;
}

async function createMany(model, rows, batchSize = 1000) {
  let count = 0;
  for (const batch of chunk(rows, batchSize)) {
    await model.createMany({ data: batch, skipDuplicates: true });
    count += batch.length;
  }
  return count;
}

async function main() {
  const companyId = arg('company-id');
  const userId = arg('user-id');
  const scale = intArg('scale', scaleFromProfile() ?? 1000);
  const products = Math.max(10, intArg('products', Math.ceil(scale / 25)));
  const clients = Math.max(10, intArg('clients', Math.ceil(scale / 10)));
  const datasetKey = arg('dataset-key', 'default');
  const datasetSlug = slugifyDatasetKey(datasetKey);
  const datasetDigits = numericDatasetToken(datasetKey, companyId);
  const baseDate = parseBaseDate(arg('base-date', '2026-10-08T00:00:00.000Z'));
  const execute = hasFlag('execute');

  if (!companyId || !userId) {
    throw new Error('Required: --company-id=<uuid> --user-id=<uuid>');
  }
  assertWriteAllowed();

  const plan = {
    execute,
    companyId,
    userId,
    profile: arg('profile', null),
    datasetKey,
    baseDate: baseDate.toISOString(),
    clients,
    products,
    sales: scale,
    saleItems: scale * 2,
    creditPayments: Math.floor(scale / 5),
    refunds: Math.floor(scale / 20),
    cashMovements: Math.floor(scale / 10),
    suppliers: Math.max(5, Math.ceil(scale / 1000)),
    purchases: Math.max(10, Math.ceil(scale / 20)),
    purchaseItems: Math.max(10, Math.ceil(scale / 10)),
    inventoryMovements: Math.max(10, Math.ceil(scale / 10)),
    quotes: Math.max(10, Math.ceil(scale / 15)),
    quoteItems: Math.max(20, Math.ceil(scale / 8)),
    serviceOrders: Math.max(10, Math.ceil(scale / 25)),
  };
  console.log(JSON.stringify({ largeDataPlan: plan }, null, 2));
  if (!execute) {
    console.log('DRY_RUN: no database writes. Add --execute only for disposable UAT/local.');
    return;
  }

  const [company, user] = await Promise.all([
    prisma.company.findUnique({ where: { id: companyId }, select: { id: true } }),
    prisma.user.findUnique({ where: { id: userId }, select: { id: true } }),
  ]);
  if (!company) throw new Error(`Company not found: ${companyId}`);
  if (!user) throw new Error(`User not found: ${userId}`);

  await prisma.unitOfMeasure.upsert({
    where: { id: 'UNIT' },
    update: { active: true },
    create: {
      id: 'UNIT',
      companyId: null,
      code: 'UNIT',
      name: 'Unidad',
      symbol: 'u',
      category: 'COUNT',
      allowDecimals: false,
      precision: 0,
      active: true,
    },
  });

  const stamp = datasetSlug;
  const clientRows = Array.from({ length: clients }, (_, index) => ({
    id: deterministicUuid(datasetKey, companyId, 'client', index),
    companyId,
    ownerId: userId,
    nombre: `LD Cliente ${stamp}-${index}`,
    telefono: `809${datasetDigits}${String(index).padStart(4, '0')}`,
    phoneNormalized: `809${datasetDigits}${String(index).padStart(4, '0')}`,
    notas: `large-data-generator:${datasetSlug}`,
  }));
  await createMany(prisma.client, clientRows);

  const productRows = Array.from({ length: products }, (_, index) => ({
    id: deterministicUuid(datasetKey, companyId, 'product', index),
    companyId,
    nombre: `LD Producto ${stamp}-${index}`,
    categoria: index % 3 === 0 ? 'Bebidas' : index % 3 === 1 ? 'Panaderia' : 'Sin categoria',
    costo: new Prisma.Decimal(10 + (index % 20)),
    precio: new Prisma.Decimal(20 + (index % 40)),
    stock: new Prisma.Decimal(100000),
    trackInventory: true,
  }));
  await createMany(prisma.product, productRows);

  const warehouse = await prisma.warehouse.upsert({
    where: { companyId_code: { companyId, code: 'LD-UAT' } },
    update: { isActive: true },
    create: {
      id: deterministicUuid(datasetKey, companyId, 'warehouse', 0),
      companyId,
      name: 'Large Data UAT',
      code: 'LD-UAT',
      isDefault: false,
      isActive: true,
    },
  });

  const cashSessionId = deterministicUuid(datasetKey, companyId, 'cash-session', 0);
  const cashSession = await prisma.cashSession.upsert({
    where: { id: cashSessionId },
    update: {},
    create: {
      id: cashSessionId,
      companyId,
      openedByUserId: userId,
      userName: 'Large Data UAT',
      openedAt: baseDate,
      initialAmount: new Prisma.Decimal(1000),
      status: 'OPEN',
    },
  });

  const saleRows = [];
  const itemRows = [];
  const creditRows = [];
  const refundRows = [];
  const now = baseDate.getTime();
  for (let index = 0; index < scale; index++) {
    const saleId = deterministicUuid(datasetKey, companyId, 'sale', index);
    const client = clientRows[index % clientRows.length];
    const isCredit = index % 5 === 0;
    const sold = new Prisma.Decimal(100 + (index % 50));
    const cost = new Prisma.Decimal(60 + (index % 25));
    saleRows.push({
      id: saleId,
      companyId,
      userId,
      customerId: client.id,
      cashSessionId: cashSession.id,
      saleDate: new Date(now - index * 60_000),
      paymentMethod: isCredit ? 'credit' : index % 2 === 0 ? 'cash' : 'card',
      paymentCashAmount: isCredit ? new Prisma.Decimal(30) : sold,
      paymentTransferAmount: isCredit ? new Prisma.Decimal(0) : new Prisma.Decimal(0),
      creditAmount: isCredit ? sold.minus(30) : new Prisma.Decimal(0),
      creditPaidAmount: isCredit ? new Prisma.Decimal(20) : new Prisma.Decimal(0),
      creditBalance: isCredit ? sold.minus(50) : new Prisma.Decimal(0),
      creditStatus: isCredit ? 'partial' : 'none',
      kind: 'invoice',
      status: 'PAID',
      totalSold: sold,
      totalCost: cost,
      totalProfit: sold.minus(cost),
      commissionAmount: sold.mul(0.1),
    });
    for (let line = 0; line < 2; line++) {
      const product = productRows[(index + line) % productRows.length];
      itemRows.push({
        id: deterministicUuid(datasetKey, companyId, `sale-item-${line}`, index),
        saleId,
        productId: product.id,
        productSource: 'LOCAL',
        sourceProductId: product.id,
        productNameSnapshot: product.nombre,
        qty: new Prisma.Decimal(1),
        priceSoldUnit: sold.div(2),
        costUnitSnapshot: cost.div(2),
        subtotalSold: sold.div(2),
        subtotalCost: cost.div(2),
        profit: sold.minus(cost).div(2),
      });
    }
    if (isCredit) {
      creditRows.push({
        id: deterministicUuid(datasetKey, companyId, 'credit-payment', index),
        companyId,
        saleId,
        userId,
        cashSessionId: cashSession.id,
        operationId: `ld-credit-${datasetSlug}-${index}`,
        amount: new Prisma.Decimal(20),
        cashAmount: new Prisma.Decimal(20),
        transferAmount: new Prisma.Decimal(0),
        paidAt: new Date(now - index * 30_000),
      });
    }
    if (index > 0 && index % 20 === 0) {
      refundRows.push({
        id: deterministicUuid(datasetKey, companyId, 'refund', index),
        companyId,
        userId,
        customerId: client.id,
        cashSessionId: cashSession.id,
        refundedSaleId: saleId,
        saleDate: new Date(now - index * 60_000 + 10_000),
        paymentMethod: 'refund',
        kind: 'refund',
        status: 'REFUNDED',
        totalSold: sold.negated(),
        totalCost: cost.negated(),
        totalProfit: sold.minus(cost).negated(),
        commissionAmount: new Prisma.Decimal(0),
      });
    }
  }

  await createMany(prisma.sale, saleRows, 1000);
  await createMany(prisma.saleItem, itemRows, 1000);
  await createMany(prisma.saleCreditPayment, creditRows, 1000);
  await createMany(prisma.sale, refundRows, 1000);

  const movementRows = Array.from({ length: plan.cashMovements }, (_, index) => ({
    id: deterministicUuid(datasetKey, companyId, 'cash-movement', index),
    companyId,
    sessionId: cashSession.id,
    operationId: `ld-cash-${datasetSlug}-${index}`,
    type: index % 2 === 0 ? 'IN' : 'OUT',
    amount: new Prisma.Decimal(5 + (index % 30)),
    movementType: index % 2 === 0 ? 'income' : 'expense',
    affectsProfit: index % 3 !== 0,
    userId,
    createdAt: new Date(now - index * 45_000),
  }));
  await createMany(prisma.cashMovement, movementRows, 1000);

  const supplierRows = Array.from({ length: plan.suppliers }, (_, index) => ({
    id: deterministicUuid(datasetKey, companyId, 'supplier', index),
    companyId,
    commercialName: `LD Suplidor ${stamp}-${index}`,
    contactName: `Contacto ${index}`,
    phone: `829${datasetDigits}${String(index).padStart(4, '0')}`,
    notes: `large-data-generator:${datasetSlug}`,
  }));
  await createMany(prisma.supplier, supplierRows, 500);

  const purchaseRows = [];
  const purchaseItemRows = [];
  const invoiceRows = [];
  for (let index = 0; index < plan.purchases; index++) {
    const purchaseId = deterministicUuid(datasetKey, companyId, 'purchase-order', index);
    const supplier = supplierRows[index % supplierRows.length];
    const total = new Prisma.Decimal(250 + (index % 100));
    purchaseRows.push({
      id: purchaseId,
      companyId,
      orderNumber: `LD-PO-${stamp}-${index}`,
      supplierId: supplier.id,
      status: index % 3 === 0 ? 'RECEIVED' : 'APPROVED',
      orderDate: new Date(now - index * 120_000),
      subtotal: total,
      total,
      createdById: userId,
      approvedById: userId,
      approvedAt: new Date(now - index * 120_000 + 1_000),
      notes: `large-data-generator:${datasetSlug}`,
    });
    for (let line = 0; line < 2; line++) {
      const product = productRows[(index + line) % productRows.length];
      const quantity = new Prisma.Decimal(3 + (line % 3));
      const unitCost = new Prisma.Decimal(15 + (index % 10));
      purchaseItemRows.push({
        id: deterministicUuid(datasetKey, companyId, `purchase-item-${line}`, index),
        purchaseOrderId: purchaseId,
        productId: product.id,
        productSource: 'LOCAL',
        sourceProductId: product.id,
        productNameSnapshot: product.nombre,
        quantity,
        receivedQuantity: index % 3 === 0 ? quantity : new Prisma.Decimal(0),
        pendingQuantity: index % 3 === 0 ? new Prisma.Decimal(0) : quantity,
        unitCost,
        subtotal: quantity.mul(unitCost),
        supplierId: supplier.id,
      });
    }
    if (index % 4 === 0) {
      invoiceRows.push({
        id: deterministicUuid(datasetKey, companyId, 'purchase-invoice', index),
        companyId,
        supplierId: supplier.id,
        purchaseOrderId: purchaseId,
        invoiceNumber: `LD-INV-${stamp}-${index}`,
        invoiceDate: new Date(now - index * 120_000 + 2_000),
        amount: total,
        fileName: `ld-invoice-${index}.pdf`,
        fileUrl: `uat://large-data/invoice-${index}.pdf`,
        storageKey: `large-data/${datasetSlug}/invoice-${index}.pdf`,
        mimeType: 'application/pdf',
        fileSize: 1024,
        uploadedById: userId,
      });
    }
  }
  await createMany(prisma.purchaseOrder, purchaseRows, 500);
  await createMany(prisma.purchaseOrderItem, purchaseItemRows, 1000);
  await createMany(prisma.purchaseInvoice, invoiceRows, 500);

  const inventoryRows = Array.from({ length: plan.inventoryMovements }, (_, index) => {
    const product = productRows[index % productRows.length];
    const quantity = new Prisma.Decimal(1 + (index % 5));
    return {
      id: deterministicUuid(datasetKey, companyId, 'inventory-movement', index),
      companyId,
      productId: product.id,
      warehouseId: warehouse.id,
      type: index % 2 === 0 ? 'ADJUSTMENT_IN' : 'ADJUSTMENT_OUT',
      quantityDelta: index % 2 === 0 ? quantity : quantity.negated(),
      previousQuantity: new Prisma.Decimal(100000),
      resultingQuantity: index % 2 === 0
        ? new Prisma.Decimal(100000).plus(quantity)
        : new Prisma.Decimal(100000).minus(quantity),
      unitCodeSnapshot: 'UNIT',
      unitNameSnapshot: 'Unidad',
      unitSymbolSnapshot: 'u',
      unitPrecisionSnapshot: 0,
      sourceType: 'large_data_generator',
      reason: `large-data-generator:${datasetSlug}`,
      createdByUserId: userId,
      createdAt: new Date(now - index * 75_000),
    };
  });
  await createMany(prisma.inventoryMovement, inventoryRows, 1000);

  const quoteRows = [];
  const quoteItemRows = [];
  for (let index = 0; index < plan.quotes; index++) {
    const quoteId = deterministicUuid(datasetKey, companyId, 'quote', index);
    const client = clientRows[index % clientRows.length];
    const subtotal = new Prisma.Decimal(180 + (index % 80));
    quoteRows.push({
      id: quoteId,
      companyId,
      createdByUserId: userId,
      customerId: client.id,
      customerName: client.nombre,
      customerPhone: client.telefono,
      customerPhoneNormalized: client.phoneNormalized,
      note: `large-data-generator:${datasetSlug}`,
      subtotal,
      subtotalCost: subtotal.mul(0.6),
      itbisAmount: new Prisma.Decimal(0),
      totalCost: subtotal.mul(0.6),
      total: subtotal,
      totalProfit: subtotal.mul(0.4),
    });
    for (let line = 0; line < 2; line++) {
      const product = productRows[(index + line) % productRows.length];
      const lineTotal = subtotal.div(2);
      quoteItemRows.push({
        id: deterministicUuid(datasetKey, companyId, `quote-item-${line}`, index),
        cotizacionId: quoteId,
        productId: product.id,
        productSource: 'LOCAL',
        sourceProductId: product.id,
        productNameSnapshot: product.nombre,
        qty: new Prisma.Decimal(1),
        unitPrice: lineTotal,
        costUnitSnapshot: lineTotal.mul(0.6),
        subtotalCost: lineTotal.mul(0.6),
        lineTotal,
        profit: lineTotal.mul(0.4),
      });
    }
  }
  await createMany(prisma.cotizacion, quoteRows, 500);
  await createMany(prisma.cotizacionItem, quoteItemRows, 1000);

  const serviceOrderRows = Array.from({ length: plan.serviceOrders }, (_, index) => ({
    id: deterministicUuid(datasetKey, companyId, 'service-order', index),
    clientId: clientRows[index % clientRows.length].id,
    quotationId: quoteRows[index % quoteRows.length]?.id ?? null,
    category: index % 2 === 0 ? 'CAMARA' : 'PUNTO_VENTA',
    serviceType: index % 3 === 0 ? 'MANTENIMIENTO' : 'INSTALACION',
    status: index % 7 === 0 ? 'CANCELADO' : index % 5 === 0 ? 'EN_PROCESO' : 'PENDIENTE',
    technicalNote: `large-data-generator:${datasetSlug}`,
    createdById: userId,
    assignedToId: userId,
    lastStatusChangedAt: new Date(now - index * 90_000),
    lastStatusChangedByUserId: userId,
  }));
  await createMany(prisma.serviceOrder, serviceOrderRows, 500);

  console.log(JSON.stringify({
    inserted: {
      clients: clientRows.length,
      products: productRows.length,
      sales: saleRows.length,
      saleItems: itemRows.length,
      creditPayments: creditRows.length,
      refunds: refundRows.length,
      cashMovements: movementRows.length,
      suppliers: supplierRows.length,
      purchases: purchaseRows.length,
      purchaseItems: purchaseItemRows.length,
      purchaseInvoices: invoiceRows.length,
      inventoryMovements: inventoryRows.length,
      quotes: quoteRows.length,
      quoteItems: quoteItemRows.length,
      serviceOrders: serviceOrderRows.length,
      cashSessionId: cashSession.id,
      warehouseId: warehouse.id,
    },
  }, null, 2));
}

function slugifyDatasetKey(datasetKey) {
  return String(datasetKey || 'default')
    .replace(/[^a-zA-Z0-9_-]/g, '-')
    .replace(/-+/g, '-')
    .slice(0, 40) || 'default';
}

function numericDatasetToken(datasetKey, companyId) {
  const hex = createHash('sha256')
    .update(`fullpos-large-data:${companyId}:${datasetKey}`)
    .digest('hex');
  return String(parseInt(hex.slice(0, 8), 16) % 1000).padStart(3, '0');
}

function deterministicUuid(datasetKey, companyId, kind, index) {
  const hex = createHash('sha256')
    .update(`fullpos-large-data:${companyId}:${datasetKey}:${kind}:${index}`)
    .digest('hex');
  const variant = ((parseInt(hex.slice(16, 18), 16) & 0x3f) | 0x80)
    .toString(16)
    .padStart(2, '0');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-${variant}${hex.slice(18, 20)}-${hex.slice(20, 32)}`;
}

function parseBaseDate(value) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw new Error(`Invalid --base-date=${value}`);
  }
  return parsed;
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
