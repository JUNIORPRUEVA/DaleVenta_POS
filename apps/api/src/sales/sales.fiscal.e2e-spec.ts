import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { CompanyMemberRole, Role } from "@prisma/client";
import * as bcrypt from "bcryptjs";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../app.module";
import { PrismaService } from "../prisma/prisma.service";

const PASSWORD = "FiscalE2E123!";
jest.setTimeout(120000);

function baseDatabaseUrl() {
  const envUrl = process.env.DATABASE_URL?.trim();
  if (envUrl) return envUrl;
  const raw = readFileSync(".env", "utf8");
  const line = raw
    .split(/\r?\n/)
    .find((entry) => entry.startsWith("DATABASE_URL="));
  if (!line) throw new Error("DATABASE_URL missing");
  return line.slice("DATABASE_URL=".length).trim();
}

function replaceDbName(url: string, dbName: string) {
  const parsed = new URL(url);
  parsed.pathname = `/${dbName}`;
  return parsed.toString();
}

describe("Fiscal authenticated HTTP E2E", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;

  async function registerCompany(suffix: string) {
    const email = `fiscal-${Date.now()}-${suffix}@example.test`;
    const res = await request(app.getHttpServer())
      .post("/auth/register-business")
      .send({
        firstName: "Fiscal",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Empresa ${suffix}`,
        taxId: suffix === "a" ? "111111111" : "333333333",
        businessPhone: "8095551111",
        address: `Address ${suffix}`,
        country: "DO",
      })
      .expect(201);
    return {
      email,
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  async function login(email: string) {
    const res = await request(app.getHttpServer())
      .post("/auth/login")
      .send({ email, password: PASSWORD })
      .expect(201);
    return res.body.accessToken as string;
  }

  async function createCashier(
    companyId: string,
    suffix: string,
    permissions: Record<string, boolean> = {},
  ) {
    const email = `cashier-${Date.now()}-${suffix}@example.test`;
    const passwordHash = await bcrypt.hash(PASSWORD, 10);
    const user = await prisma.user.create({
      data: {
        companyId,
        email,
        passwordHash,
        nombreCompleto: `Cashier ${suffix}`,
        telefono: "8095552222",
        edad: 20,
        role: Role.CAJERO,
        blocked: false,
        userPermissions: permissions,
      },
    });
    await prisma.companyMember.create({
      data: {
        userId: user.id,
        companyId,
        role: CompanyMemberRole.MEMBER,
        status: "ACTIVE",
        joinedAt: new Date(),
      },
    });
    return { email, userId: user.id, token: await login(email) };
  }

  async function openCashSession(companyId: string, userId: string) {
    return prisma.cashSession.create({
      data: {
        companyId,
        openedByUserId: userId,
        initialAmount: "0",
        status: "OPEN",
      },
    });
  }

  beforeAll(async () => {
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!/^fullpos_http_e2e_/.test(dbName)) {
      throw new Error("Unsafe E2E DB name");
    }

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "fiscal-e2e-secret";
    const prismaCli = resolve(
      process.cwd(),
      "..",
      "..",
      "node_modules",
      "prisma",
      "build",
      "index.js",
    );
    execFileSync(process.execPath, [prismaCli, "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleRef.createNestApplication();
    await app.init();
    prisma = app.get(PrismaService);
  }, 120000);

  afterAll(async () => {
    if (app) await app.close();
    if (adminUrl && dbName && /^fullpos_http_e2e_/.test(dbName)) {
      const admin = new Client({ connectionString: adminUrl });
      await admin.connect();
      await admin.query(
        `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()`,
        [dbName],
      );
      await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
      await admin.end();
    }
  }, 60000);

  it("authenticates real tenants and blocks cashier fiscal admin actions", async () => {
    const adminA = await registerCompany("a");
    const cashierA = await createCashier(adminA.companyId, "a");

    const tax = await request(app.getHttpServer())
      .post("/taxes")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({ name: "ITBIS 18", rate: 0.18, isActive: true, isDefault: true })
      .expect(201);

    await request(app.getHttpServer())
      .patch("/company/fiscal-settings")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        taxEnabled: true,
        defaultTaxId: tax.body.id,
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      })
      .expect(200);

    await request(app.getHttpServer())
      .patch("/company/fiscal-settings")
      .set("Authorization", `Bearer ${cashierA.token}`)
      .send({ taxEnabled: false })
      .expect(403);

    await request(app.getHttpServer())
      .post("/ncf/sequences")
      .set("Authorization", `Bearer ${cashierA.token}`)
      .send({
        voucherType: "B01",
        prefix: "B01",
        startNumber: 1,
        endNumber: 10,
      })
      .expect(403);
  });

  it("keeps quote snapshots through B01 conversion and prevents duplicate NCF", async () => {
    const adminA = await registerCompany("quote-a");
    await openCashSession(adminA.companyId, adminA.userId);

    const tax = await request(app.getHttpServer())
      .post("/taxes")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({ name: "ITBIS 18", rate: 0.18, isActive: true, isDefault: true })
      .expect(201);
    await request(app.getHttpServer())
      .patch("/company/fiscal-settings")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        taxEnabled: true,
        defaultTaxId: tax.body.id,
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      })
      .expect(200);
    await request(app.getHttpServer())
      .post("/ncf/sequences")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        voucherType: "B01",
        prefix: "B01",
        startNumber: 1,
        endNumber: 50,
      })
      .expect(201);

    const product = await request(app.getHttpServer())
      .post("/products")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        nombre: "Producto Original",
        categoria: "Fiscal",
        precio: 1180,
        costo: 600,
        stock: 10,
        taxTreatment: "TAXABLE",
        taxRate: 0.18,
        taxPriceMode: "TAX_INCLUDED",
      })
      .expect(201);
    const client = await request(app.getHttpServer())
      .post("/clients")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        nombre: "Cliente Original",
        telefono: "8090000000",
        taxId: "222222222",
        businessName: "Cliente Original",
        direccion: "Customer Original",
      })
      .expect(201);

    const quote = await request(app.getHttpServer())
      .post("/cotizaciones")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        customerId: client.body.id,
        customerName: "Cliente Original",
        customerPhone: "8090000000",
        items: [
          {
            productId: product.body.id,
            qty: 1,
            unitPrice: 1180,
            costUnitSnapshot: 600,
            taxTreatment: "TAXABLE",
            taxRate: 0.18,
            taxPriceMode: "TAX_INCLUDED",
          },
        ],
      })
      .expect(201);

    expect(Number(quote.body.taxableBase)).toBeCloseTo(1000, 2);
    expect(Number(quote.body.taxAmount)).toBeCloseTo(180, 2);
    expect(Number(quote.body.total)).toBeCloseTo(1180, 2);

    await prisma.product.update({
      where: { id: product.body.id },
      data: { nombre: "Producto Mutado", precio: "9999" },
    });

    const invoice = await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        sourceQuotationId: quote.body.id,
        fiscalVoucherType: "B01",
        customerId: client.body.id,
        expectedTotalSold: 1180,
        items: [
          { productName: "Stale", qty: 1, priceSoldUnit: 1, costUnitSnapshot: 0 },
        ],
      })
      .expect(201);

    const duplicate = await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        sourceQuotationId: quote.body.id,
        fiscalVoucherType: "B01",
        customerId: client.body.id,
        expectedTotalSold: 1180,
        items: [
          { productName: "Stale", qty: 1, priceSoldUnit: 1, costUnitSnapshot: 0 },
        ],
      })
      .expect(201);

    expect(duplicate.body.id).toBe(invoice.body.id);
    expect(invoice.body.ncf).toBe("B0100000001");
    expect(Number(invoice.body.taxableBase)).toBeCloseTo(1000, 2);
    expect(Number(invoice.body.taxAmount)).toBeCloseTo(180, 2);
    expect(Number(invoice.body.totalSold)).toBeCloseTo(1180, 2);

    const sequence = await prisma.ncfSequence.findFirstOrThrow({
      where: { companyId: adminA.companyId, voucherType: "B01" },
    });
    expect(sequence.nextNumber).toBe(2);
  }, 60000);

  it("blocks cross-tenant product/client/sale access and isolates reports", async () => {
    const adminA = await registerCompany("tenant-a");
    const adminB = await registerCompany("tenant-b");
    await openCashSession(adminA.companyId, adminA.userId);
    await openCashSession(adminB.companyId, adminB.userId);

    const productB = await request(app.getHttpServer())
      .post("/products")
      .set("Authorization", `Bearer ${adminB.token}`)
      .send({
        nombre: "Producto B",
        categoria: "Fiscal",
        precio: 20000,
        costo: 10000,
        stock: 5,
      })
      .expect(201);
    const clientB = await request(app.getHttpServer())
      .post("/clients")
      .set("Authorization", `Bearer ${adminB.token}`)
      .send({ nombre: "Cliente B", telefono: "8091111111" })
      .expect(201);

    await request(app.getHttpServer())
      .get(`/products/${productB.body.id}`)
      .set("Authorization", `Bearer ${adminA.token}`)
      .expect(404);
    await request(app.getHttpServer())
      .get(`/clients/${clientB.body.id}`)
      .set("Authorization", `Bearer ${adminA.token}`)
      .expect(404);

    const saleA = await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        clientRequestId: "sale-a-10000",
        items: [
          { productName: "A", qty: 1, priceSoldUnit: 10000, costUnitSnapshot: 6000 },
        ],
      })
      .expect(201);
    await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${adminB.token}`)
      .send({
        clientRequestId: "sale-b-20000",
        items: [
          { productName: "B", qty: 1, priceSoldUnit: 20000, costUnitSnapshot: 12000 },
        ],
      })
      .expect(201);

    await request(app.getHttpServer())
      .post(`/sales/${saleA.body.id}/return`)
      .set("Authorization", `Bearer ${adminB.token}`)
      .send({})
      .expect(404);

    const reportA = await request(app.getHttpServer())
      .get("/reports/sales-overview")
      .set("Authorization", `Bearer ${adminA.token}`)
      .expect(200);
    const reportB = await request(app.getHttpServer())
      .get("/reports/sales-overview")
      .set("Authorization", `Bearer ${adminB.token}`)
      .expect(200);
    expect(Number(reportA.body.kpis.totalSold)).toBeCloseTo(10000, 2);
    expect(Number(reportB.body.kpis.totalSold)).toBeCloseTo(20000, 2);
  }, 60000);

  it("validates B01 failure without fiscal customer, B02, refunds and over-refund", async () => {
    const adminA = await registerCompany("refund-a");
    await openCashSession(adminA.companyId, adminA.userId);
    const tax = await request(app.getHttpServer())
      .post("/taxes")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({ name: "ITBIS 18", rate: 0.18, isActive: true, isDefault: true })
      .expect(201);
    await request(app.getHttpServer())
      .patch("/company/fiscal-settings")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        taxEnabled: true,
        defaultTaxId: tax.body.id,
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      })
      .expect(200);
    await request(app.getHttpServer())
      .post("/ncf/sequences")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        voucherType: "B01",
        prefix: "B01",
        startNumber: 1,
        endNumber: 10,
      })
      .expect(201);
    await request(app.getHttpServer())
      .post("/ncf/sequences")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        voucherType: "B02",
        prefix: "B02",
        startNumber: 1,
        endNumber: 10,
      })
      .expect(201);

    await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        fiscalVoucherType: "B01",
        items: [
          { productName: "Fiscal", qty: 1, priceSoldUnit: 1180, costUnitSnapshot: 600 },
        ],
      })
      .expect(400);
    const seqAfterFailedB01 = await prisma.ncfSequence.findFirstOrThrow({
      where: { companyId: adminA.companyId, voucherType: "B01" },
    });
    expect(seqAfterFailedB01.nextNumber).toBe(1);

    const b02 = await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        fiscalVoucherType: "B02",
        items: [
          { productName: "Final", qty: 1, priceSoldUnit: 1180, costUnitSnapshot: 600 },
        ],
      })
      .expect(201);
    expect(b02.body.ncf).toBe("B0200000001");

    const sale = await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({
        items: [
          {
            productName: "Refundable",
            qty: 2,
            priceSoldUnit: 1180,
            costUnitSnapshot: 600,
          },
        ],
      })
      .expect(201);
    const firstItem = sale.body.items[0];
    const refund = await request(app.getHttpServer())
      .post(`/sales/${sale.body.id}/return`)
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({ items: [{ saleItemId: firstItem.id, qty: 1 }] })
      .expect(201);
    expect(Number(refund.body.totalSold)).toBeCloseTo(-1180, 2);

    await request(app.getHttpServer())
      .post(`/sales/${sale.body.id}/return`)
      .set("Authorization", `Bearer ${adminA.token}`)
      .send({ items: [{ saleItemId: firstItem.id, qty: 2 }] })
      .expect(400);
  }, 60000);
});
