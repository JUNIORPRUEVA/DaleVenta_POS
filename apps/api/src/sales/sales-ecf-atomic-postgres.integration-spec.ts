import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaService } from "../prisma/prisma.service";
import { TaxService } from "../tax/tax.service";
import { TaxCalculationService } from "../tax/tax-calculation.service";
import { InventoryMutationService } from "../inventory/inventory-mutation.service";
import { EcfPreparationService } from "../ecf/documents/ecf-preparation.service";
import { isEcfEphemeralTestTarget } from "../ecf/ecf-local-target";
import { SalesService } from "./sales.service";
import * as fiscalMapper from "../ecf/fiscal-core/alanube-dom.mapper";

const local = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;
local("atomic electronic checkout on owned PostgreSQL, with no external emission", () => {
  let db: PrismaService;
  let sales: SalesService;
  const env = { ...process.env };
  beforeAll(async () => {
    if (!isEcfEphemeralTestTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") throw Error("OWNED_EPHEMERAL_DATABASE_REQUIRED");
    db = new PrismaService(); await db.$connect();
    sales = new SalesService(db, new ConfigService({}), { emitCompany: jest.fn() } as any,
      new TaxService(db, new TaxCalculationService()), new InventoryMutationService(db));
  });
  beforeEach(() => {
    process.env.DOSA_EMISSION_ENABLED = "true";
    process.env.DOSA_PRODUCTION_EMISSION_ENABLED = "true";
    process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED = "true";
  });
  afterAll(async () => { process.env = env; await db?.$disconnect(); });
  async function fixture(capacity = 10) {
    const companyId = randomUUID(), userId = randomUUID();
    await db.company.create({ data: { id: companyId, name: "Synthetic atomic checkout", slug: `atomic-${companyId}`, taxEnabled: true, defaultTaxRate: 0.18, pricesIncludeTax: false } });
    await db.appConfig.create({ data: { id: randomUUID(), companyId, companyName: "Synthetic issuer", rnc: "101000001", address: "Synthetic local address" } });
    await db.user.create({ data: { id: userId, companyId, email: `${userId}@synthetic.test`, passwordHash: "synthetic-unused-hash", nombreCompleto: "Synthetic operator", telefono: "0000000000", edad: 30, role: "ADMIN" } });
    const user = { id: userId, companyId, role: "ADMIN" };
    await db.ecfCompanyConfiguration.create({ data: { companyId, provider: "DOSA", enabled: true, environment: "PRODUCTION", productionEnabled: true, certificationStatus: "PRODUCTION_READY", allowedTypes: ["E31", "E32", "E34"] } });
    await db.ecfDosaCompanyCredential.create({ data: { companyId, rnc: "101000001", environment: "production", status: "ACTIVE", source: "WEBHOOK", keyVersion: 1,
      ciphertext: "synthetic-never-opened", iv: "synthetic", authTag: "synthetic", fingerprint: "a".repeat(64), present: { apiKeyProduccion: true } } });
    for (const documentType of ["E31", "E32"]) {
      await db.ecfDgiiAuthorizedSequence.create({ data: { companyId, environment: "PRODUCTION", documentType, authorizationNumber: "SYNTHETIC", rangeFrom: 1, rangeTo: 10, approvedQuantity: 10, declarationVersion: "local-test" } });
      await db.ecfSequence.create({ data: { companyId, environment: "PRODUCTION", documentType, prefix: documentType, startNumber: 1, nextNumber: 1, endNumber: capacity } });
    }
    const warehouse = await db.warehouse.create({ data: { companyId, name: "Synthetic warehouse", code: "W1", isDefault: true } });
    const terminal = await db.terminal.create({ data: { companyId, name: "Synthetic terminal", code: "T1", defaultWarehouseId: warehouse.id, isDefault: true } });
    const session = await db.cashSession.create({ data: { companyId, openedByUserId: userId, terminalId: terminal.id, initialAmount: 0, status: "OPEN" } });
    const unit = await db.unitOfMeasure.create({ data: { id: randomUUID(), companyId, code: "UNIT", name: "Unidad", symbol: "u", category: "COUNT" } });
    const product = await db.product.create({ data: { companyId, nombre: "Synthetic tracked product", categoria: "Synthetic QA", precio: 100, costo: 50, stock: 10, itemType: "PRODUCT", trackInventory: true, unitOfMeasureId: unit.id } });
    await db.warehouseStock.create({ data: { companyId, warehouseId: warehouse.id, productId: product.id, quantity: 10 } });
    const dto = { clientRequestId: randomUUID(), originCashSessionId: session.id, originTerminalId: terminal.id, terminalId: terminal.id, saleOccurredAt: new Date().toISOString(), fiscalVoucherType: "E31", sequenceDueDate: "2027-12-31",
      fiscalCustomerTaxId: "130000000", fiscalCustomerName: "Synthetic buyer", paymentMethod: "cash" as const,
      items: [{ productId: product.id, qty: 1, priceSoldUnit: 100, costUnitSnapshot: 50 }] };
    return { companyId, user, dto, product, warehouse };
  }
  async function expectUntouched(f: Awaited<ReturnType<typeof fixture>>) {
    expect(await db.sale.count({ where: { companyId: f.companyId } })).toBe(0);
    expect(await db.inventoryMovement.count({ where: { companyId: f.companyId } })).toBe(0);
    expect(await db.ecfElectronicDocument.count({ where: { companyId: f.companyId } })).toBe(0);
    expect(await db.ecfSequenceAuditLog.count({ where: { companyId: f.companyId } })).toBe(0);
    expect((await db.product.findFirstOrThrow({ where: { companyId: f.companyId, id: f.product.id } })).stock.toString()).toBe("10");
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId: f.companyId, documentType: "E31" } })).nextNumber).toBe(1);
  }
  it.each(["DOSA_EMISSION_ENABLED", "DOSA_PRODUCTION_EMISSION_ENABLED", "DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED"])("rejects %s=false before financial or inventory writes", async key => {
    const f = await fixture(); process.env[key] = "false";
    await expect(sales.create(f.user, f.dto)).rejects.toThrow(); await expectUntouched(f);
  });
  it("rejects a cashier without fiscal permission even with a valid cash session", async () => {
    const f = await fixture();
    await expect(sales.create({ ...f.user, role: "CAJERO", userPermissions: {} }, f.dto)).rejects.toThrow("permiso");
    await expectUntouched(f);
  });
  it("requires explicit production activation for this certified company", async () => {
    const f = await fixture();
    await db.ecfCompanyConfiguration.update({ where: { companyId: f.companyId }, data: { productionEnabled: false } });
    await expect(sales.create(f.user, f.dto)).rejects.toThrow(); await expectUntouched(f);
  });
  it("requires this company's production credential, not its TEST key", async () => {
    const f = await fixture();
    await db.ecfDosaCompanyCredential.updateMany({ where: { companyId: f.companyId }, data: { present: { apiKeyTest: true } } });
    await expect(sales.create(f.user, f.dto)).rejects.toThrow(); await expectUntouched(f);
  });
  it("rolls back sale, stock and numbering when fiscal validation fails after local sale construction", async () => {
    const f = await fixture();
    await db.appConfig.updateMany({ where: { companyId: f.companyId }, data: { address: "" } });
    await expect(sales.create(f.user, f.dto)).rejects.toThrow(); await expectUntouched(f);
  });
  it.each(["E31", "E32"])("commits one %s and one sale, and replays both without another allocation", async type => {
    const f = await fixture(); const dto = { ...f.dto, fiscalVoucherType: type };
    const first = await sales.create(f.user, dto), second = await sales.create(f.user, dto);
    expect(first.id).toBe(second.id);
    expect(await db.sale.count({ where: { companyId: f.companyId } })).toBe(1);
    expect(await db.ecfElectronicDocument.count({ where: { companyId: f.companyId, sourceId: first.id } })).toBe(1);
    expect(await db.ecfSequenceAuditLog.count({ where: { companyId: f.companyId, type, action: "ALLOCATED" } })).toBe(1);
    expect(await db.ecfElectronicDocumentAttempt.count({ where: { companyId: f.companyId, operation: "SEND_TO_PROVIDER" } })).toBe(0);
    const preparation = new EcfPreparationService(db);
    const input = { saleId: first.id, paymentType: 1 as const, incomeType: 1 as const, sequenceDueDate: dto.sequenceDueDate };
    expect((type === "E31" ? await preparation.prepareFromSale(f.user, { ...input, documentType: "E31" }) : await preparation.prepareConsumoFromSale(f.user, { ...input, documentType: "E32" })).ok).toBe(true);
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId: f.companyId, documentType: type } })).nextNumber).toBe(2);
  });
  it("also rolls back numbering when mapping fails after allocation", async () => {
    const f = await fixture();
    const mapping = jest.spyOn(fiscalMapper, "mapEcfToAlanubeDom").mockReturnValueOnce({ schemaValidation: { ok: false } } as never);
    try { await expect(sales.create(f.user, f.dto)).rejects.toThrow("ECF_EMISSION_CONTRACT_BLOCKED"); }
    finally { mapping.mockRestore(); }
    await expectUntouched(f);
  });
  it("concurrent checkouts cannot leave an unprepared sale when the final number is consumed", async () => {
    const f = await fixture(1);
    const attempts = await Promise.allSettled([sales.create(f.user, f.dto),
      sales.create(f.user, { ...f.dto, clientRequestId: randomUUID() })]);
    expect(attempts.filter(attempt => attempt.status === "fulfilled")).toHaveLength(1);
    expect(attempts.filter(attempt => attempt.status === "rejected")).toHaveLength(1);
    expect(await db.sale.count({ where: { companyId: f.companyId } })).toBe(1);
    expect(await db.ecfElectronicDocument.count({ where: { companyId: f.companyId, documentType: "E31" } })).toBe(1);
    expect((await db.product.findFirstOrThrow({ where: { companyId: f.companyId, id: f.product.id } })).stock.toString()).toBe("9");
    expect((await db.ecfSequence.findFirstOrThrow({ where: { companyId: f.companyId, documentType: "E31" } })).nextNumber).toBe(2);
  });
  it("legacy ordinary payloads and explicit NORMAL keep ITBIS without any fiscal allocation", async () => {
    const f = await fixture(); process.env.DOSA_EMISSION_ENABLED = "false";
    await db.ecfCompanyConfiguration.update({ where: { companyId: f.companyId }, data: { enabled: false } });
    const legacy = await sales.create(f.user, { ...f.dto, fiscalVoucherType: undefined });
    const normal = await sales.create(f.user, { ...f.dto, clientRequestId: randomUUID(), fiscalVoucherType: "NORMAL" });
    expect(legacy.fiscalVoucherType).toBeNull(); expect(normal.fiscalVoucherType).toBe("NORMAL");
    expect(normal.taxAmount.toString()).toBe("18"); expect(legacy.totalSold.toString()).toBe("118");
    expect(await db.ecfElectronicDocument.count({ where: { companyId: f.companyId } })).toBe(0);
    expect(await db.ecfSequenceAuditLog.count({ where: { companyId: f.companyId } })).toBe(0);
  });
});
