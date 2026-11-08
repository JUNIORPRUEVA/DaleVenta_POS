import { randomUUID } from "node:crypto";
import { isEcfLocalTarget } from "../ecf-local-target";
import { PrismaService } from "../../prisma/prisma.service";
import type { TenantUser } from "../../auth/tenant-context";
import { EcfSalesWithoutDocumentService } from "./ecf-sales-without-document.service";

// Opt-in suite on the ephemeral test database. El registro de ventas sin
// comprobante es evidencia fiscal: se prueba contra una base real porque lo que
// se valida es la persistencia y el aislamiento por empresa.
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

uat("venta sin comprobante electrónico (registro de excepciones) on PostgreSQL", () => {
  let prisma: PrismaService;
  let service: EcfSalesWithoutDocumentService;
  let userId: string;

  beforeAll(async () => {
    if (!isEcfLocalTarget() || process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("ECF_SALES_WITHOUT_DOCUMENT_UAT_REFUSED");
    }
    prisma = new PrismaService();
    await prisma.$connect();
    service = new EcfSalesWithoutDocumentService(prisma);
    userId = randomUUID();
    await prisma.user.create({
      data: {
        id: userId,
        email: `ecf-without-doc-${userId}@synthetic.test`,
        passwordHash: "synthetic-not-a-real-hash",
        nombreCompleto: "Synthetic Without Document User",
        telefono: "0000000000",
        edad: 30,
        role: "ADMIN",
      },
    });
  });

  afterAll(async () => {
    await prisma?.user.deleteMany({ where: { id: userId } });
    await prisma?.$disconnect();
  });

  async function tenant(options: {
    enabled?: boolean;
    allow?: boolean;
  } = {}) {
    const companyId = randomUUID();
    await prisma.company.create({
      data: { id: companyId, name: "Synthetic sin comprobante", slug: `ecf-nodoc-${companyId}` },
    });
    await prisma.ecfCompanyConfiguration.create({
      data: {
        companyId,
        enabled: options.enabled ?? true,
        environment: "SANDBOX",
        allowSalesWithoutEcf: options.allow ?? true,
      },
    });
    return { companyId, user: { id: userId, role: "ADMIN", companyId } as TenantUser };
  }

  async function createSale(companyId: string, fiscalVoucherType: string | null = null) {
    return prisma.sale.create({
      data: {
        companyId,
        userId,
        totalSold: "118.00",
        totalCost: "10.00",
        totalProfit: "0.00",
        commissionAmount: "0.00",
        taxableBase: "100.00",
        exemptAmount: "0.00",
        discountAmount: "0.00",
        taxAmount: "18.00",
        fiscalTaxEnabled: true,
        fiscalVoucherType,
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1, Santo Domingo",
      },
    });
  }

  const reason = "Venta de prueba interna sin comprobante fiscal";

  it("registra la excepción con motivo, usuario y venta", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const view = await service.register(user, {
      saleId: sale.id,
      reason: `  ${reason}  `,
      expectedDocumentType: "E32",
    });

    expect(view.saleId).toBe(sale.id);
    expect(view.reason).toBe(reason);
    expect(view.expectedDocumentType).toBe("E32");
    expect(view.registeredByUserId).toBe(userId);

    const stored = await prisma.ecfSaleWithoutDocument.findFirstOrThrow({
      where: { companyId, saleId: sale.id },
    });
    expect(stored.reason).toBe(reason);
    expect(stored.registeredByUserId).toBe(userId);
  });

  it("rechaza la opción Normal cuando la empresa no la habilitó", async () => {
    const { companyId, user } = await tenant({ allow: false });
    const sale = await createSale(companyId);

    await expect(
      service.register(user, { saleId: sale.id, reason }),
    ).rejects.toThrow(/ECF_SALES_WITHOUT_DOCUMENT_NOT_ALLOWED/);
    expect(await prisma.ecfSaleWithoutDocument.count({ where: { companyId } })).toBe(0);
  });

  it("rechaza la opción Normal cuando la facturación electrónica está apagada", async () => {
    const { companyId, user } = await tenant({ enabled: false });
    const sale = await createSale(companyId);

    await expect(
      service.register(user, { saleId: sale.id, reason }),
    ).rejects.toThrow(/ECF_COMPANY_DISABLED/);
    expect(await prisma.ecfSaleWithoutDocument.count({ where: { companyId } })).toBe(0);
  });

  it("exige un motivo con contenido real", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    await expect(
      service.register(user, { saleId: sale.id, reason: "ok" }),
    ).rejects.toThrow(/ECF_WITHOUT_DOCUMENT_REASON_REQUIRED/);
    expect(await prisma.ecfSaleWithoutDocument.count({ where: { companyId } })).toBe(0);
  });

  it("es idempotente por venta: un reintento devuelve la misma evidencia", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);

    const first = await service.register(user, { saleId: sale.id, reason });
    const second = await service.register(user, { saleId: sale.id, reason });

    expect(second.id).toBe(first.id);
    expect(await prisma.ecfSaleWithoutDocument.count({ where: { companyId } })).toBe(1);
  });

  it("no acepta una venta que ya tiene comprobante fiscal legado", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId, "B02");

    await expect(
      service.register(user, { saleId: sale.id, reason }),
    ).rejects.toThrow(/ECF_SALES_WITHOUT_DOCUMENT_HAS_ECF/);
  });

  it("no acepta una venta que ya tiene un e-CF preparado", async () => {
    const { companyId, user } = await tenant();
    const sale = await createSale(companyId);
    await prisma.ecfElectronicDocument.create({
      data: {
        companyId,
        documentType: "E32",
        status: "LOCAL_VALIDATED",
        sourceType: "SALE",
        sourceId: sale.id,
        idempotencyKey: `synthetic-without-doc-${randomUUID()}`,
        payloadFingerprint: "d".repeat(64),
      },
    });

    await expect(
      service.register(user, { saleId: sale.id, reason }),
    ).rejects.toThrow(/ECF_SALES_WITHOUT_DOCUMENT_HAS_ECF/);
  });

  it("no permite registrar la venta de otra empresa", async () => {
    const a = await tenant();
    const b = await tenant();
    const sale = await createSale(a.companyId);

    await expect(
      service.register(b.user, { saleId: sale.id, reason }),
    ).rejects.toThrow(/ECF_SALES_WITHOUT_DOCUMENT_SALE_NOT_FOUND/);
    expect(await prisma.ecfSaleWithoutDocument.count({ where: { companyId: b.companyId } })).toBe(0);
  });

  it("lista solo las excepciones de la propia empresa", async () => {
    const a = await tenant();
    const b = await tenant();
    const saleA = await createSale(a.companyId);
    const saleB = await createSale(b.companyId);
    await service.register(a.user, { saleId: saleA.id, reason });
    await service.register(b.user, { saleId: saleB.id, reason });

    const aList = await service.list(a.user);
    const bList = await service.list(b.user);

    expect(aList.items).toHaveLength(1);
    expect(aList.items[0].saleId).toBe(saleA.id);
    expect(bList.items).toHaveLength(1);
    expect(bList.items[0].saleId).toBe(saleB.id);
  });
});
