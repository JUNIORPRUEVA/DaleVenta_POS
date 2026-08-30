import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { CompanyMemberRole, Role } from "@prisma/client";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "./app.module";
import { PrismaService } from "./prisma/prisma.service";

const PASSWORD = "Phase26Uat123!";
jest.setTimeout(180000);

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

function dbNameFromUrl(url: string) {
  return new URL(url).pathname.replace(/^\//, "");
}

function expectDecimal(value: unknown, expected: string) {
  expect(`${value}`).toBe(expected);
}

describe("PHASE 2.6 UoM manual UAT on isolated test database", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;
  const evidence: Record<string, unknown> = {};

  async function assertTestDatabase() {
    const [db, user, addr, port] = await Promise.all([
      prisma.$queryRawUnsafe<Array<{ current_database: string }>>(
        "SELECT current_database()",
      ),
      prisma.$queryRawUnsafe<Array<{ current_user: string }>>(
        "SELECT current_user",
      ),
      prisma.$queryRawUnsafe<Array<{ inet_server_addr: string }>>(
        "SELECT inet_server_addr()",
      ),
      prisma.$queryRawUnsafe<Array<{ inet_server_port: number }>>(
        "SELECT inet_server_port()",
      ),
    ]);
    const currentDatabase = db[0]?.current_database;
    if (!currentDatabase?.endsWith("_uom_test")) {
      throw new Error(`Unsafe database for UAT: ${currentDatabase}`);
    }
    evidence.database = {
      name: currentDatabase,
      user: user[0]?.current_user,
      server: `${addr[0]?.inet_server_addr}:${port[0]?.inet_server_port}`,
    };
  }

  async function registerCompany(suffix: string) {
    await assertTestDatabase();
    const email = `phase26-${Date.now()}-${suffix}@example.test`;
    const res = await request(app.getHttpServer())
      .post("/auth/register-business")
      .send({
        firstName: "Phase",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Phase 26 ${suffix}`,
        taxId: suffix === "legacy" ? "101010101" : "202020202",
        businessPhone: "8095551111",
        address: `UAT ${suffix}`,
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

  async function openCashSession(companyId: string, userId: string) {
    await assertTestDatabase();
    return prisma.cashSession.create({
      data: {
        companyId,
        openedByUserId: userId,
        initialAmount: "0",
        status: "OPEN",
      },
    });
  }

  async function createProduct(token: string, body: Record<string, unknown>) {
    await assertTestDatabase();
    return request(app.getHttpServer())
      .post("/products")
      .set("Authorization", `Bearer ${token}`)
      .send(body)
      .expect(201)
      .then((res) => res.body);
  }

  async function createSale(
    token: string,
    body: Record<string, unknown>,
    expectedStatus = 201,
  ) {
    await assertTestDatabase();
    return request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${token}`)
      .send(body)
      .expect(expectedStatus)
      .then((res) => res.body);
  }

  beforeAll(async () => {
    const baseUrl = baseDatabaseUrl();
    const productionDb = dbNameFromUrl(baseUrl);
    dbName = `daleventas_phase26_${Date.now()}_uom_test`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!dbName.endsWith("_uom_test")) {
      throw new Error("Unsafe UAT DB name");
    }

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    const identity = await admin.query(
      "SELECT current_database(), current_user, inet_server_addr(), inet_server_port(), version()",
    );
    evidence.production = {
      protectedDatabase: productionDb,
      postgresVersion: identity.rows[0]?.version,
      adminDatabase: identity.rows[0]?.current_database,
    };
    await admin.query(`CREATE DATABASE "${dbName}"`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "phase26-uat-secret";
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
    await assertTestDatabase();
  }, 180000);

  afterAll(async () => {
    if (app) await app.close();
    if (adminUrl && dbName && dbName.endsWith("_uom_test")) {
      const admin = new Client({ connectionString: adminUrl });
      await admin.connect();
      await admin.query(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
        [dbName],
      );
      await admin.query(`DROP DATABASE IF EXISTS "${dbName}"`);
      await admin.end();
    }
    // eslint-disable-next-line no-console
    console.log("[phase26-uat-evidence]", JSON.stringify(evidence, null, 2));
  }, 60000);

  it("validates legacy and UoM flows end-to-end without touching production", async () => {
    await assertTestDatabase();
    const [unit, yard, pound] = await Promise.all([
      prisma.unitOfMeasure.findFirstOrThrow({ where: { code: "UNIT" } }),
      prisma.unitOfMeasure.findFirstOrThrow({ where: { code: "YARD" } }),
      prisma.unitOfMeasure.findFirstOrThrow({ where: { code: "POUND" } }),
    ]);

    const companyA = await registerCompany("legacy");
    const companyB = await registerCompany("uom");

    const settingsA = await request(app.getHttpServer())
      .get("/settings")
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(200)
      .then((res) => res.body);
    expect(settingsA.measurementUnitsEnabled).toBe(false);

    const settingsB = await request(app.getHttpServer())
      .patch("/settings")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({ measurementUnitsEnabled: true })
      .expect(200)
      .then((res) => res.body);
    expect(settingsB.measurementUnitsEnabled).toBe(true);

    await openCashSession(companyA.companyId, companyA.userId);
    await openCashSession(companyB.companyId, companyB.userId);

    const legacyProduct = await createProduct(companyA.token, {
      nombre: "Audifonos UAT",
      codigo: `AUD-${Date.now()}`,
      categoria: "Legacy",
      stock: 10,
      precio: 500,
      costo: 250,
    });
    expect(legacyProduct.unitOfMeasure.code).toBe("UNIT");

    const legacySale = await createSale(companyA.token, {
      paymentMethod: "cash",
      paymentCashAmount: 1000,
      expectedTotalSold: 1000,
      items: [{ productId: legacyProduct.id, qty: 2, priceSoldUnit: 500 }],
    });
    expectDecimal(legacySale.totalSold, "1000");
    const legacyAfter = await prisma.product.findUniqueOrThrow({
      where: { id: legacyProduct.id },
    });
    expectDecimal(legacyAfter.stock, "8");
    await createSale(
      companyA.token,
      {
        paymentMethod: "cash",
        paymentCashAmount: 750,
        items: [{ productId: legacyProduct.id, qty: 1.5, priceSoldUnit: 500 }],
      },
      400,
    );

    const tela = await createProduct(companyB.token, {
      nombre: "Tela Azul UAT",
      codigo: `TELA-${Date.now()}`,
      categoria: "UoM",
      stock: 20,
      precio: 200,
      costo: 100,
      unitOfMeasureId: yard.id,
    });
    const carne = await createProduct(companyB.token, {
      nombre: "Carne UAT",
      codigo: `CARNE-${Date.now()}`,
      categoria: "UoM",
      stock: 10,
      precio: 180,
      costo: 120,
      unitOfMeasureId: pound.id,
    });

    const telaSale = await createSale(companyB.token, {
      paymentMethod: "cash",
      paymentCashAmount: 1100,
      expectedTotalSold: 1100,
      items: [{ productId: tela.id, qty: 5.5, priceSoldUnit: 200 }],
    });
    expectDecimal(telaSale.totalSold, "1100");
    expectDecimal(telaSale.items[0].qty, "5.5");
    expect(telaSale.items[0].unitCodeSnapshot).toBe("YARD");
    let telaDb = await prisma.product.findUniqueOrThrow({
      where: { id: tela.id },
    });
    expectDecimal(telaDb.stock, "14.5");

    const carneSale = await createSale(companyB.token, {
      paymentMethod: "cash",
      paymentCashAmount: 427.5,
      expectedTotalSold: 427.5,
      items: [{ productId: carne.id, qty: 2.375, priceSoldUnit: 180 }],
    });
    expectDecimal(carneSale.totalSold, "427.5");
    let carneDb = await prisma.product.findUniqueOrThrow({
      where: { id: carne.id },
    });
    expectDecimal(carneDb.stock, "7.625");

    const fractionProduct = await createProduct(companyB.token, {
      nombre: "Fraccion UAT",
      codigo: `FRAC-${Date.now()}`,
      categoria: "UoM",
      stock: 1,
      precio: 200,
      costo: 100,
      unitOfMeasureId: yard.id,
    });
    await createSale(companyB.token, {
      paymentMethod: "cash",
      paymentCashAmount: 25,
      expectedTotalSold: 25,
      items: [
        { productId: fractionProduct.id, qty: 0.125, priceSoldUnit: 200 },
      ],
    });
    const fractionDb = await prisma.product.findUniqueOrThrow({
      where: { id: fractionProduct.id },
    });
    expectDecimal(fractionDb.stock, "0.875");

    await createSale(
      companyB.token,
      {
        paymentMethod: "cash",
        paymentCashAmount: 246.9,
        items: [{ productId: tela.id, qty: 1.2345, priceSoldUnit: 200 }],
      },
      400,
    );
    await createSale(
      companyB.token,
      {
        paymentMethod: "cash",
        paymentCashAmount: 0,
        items: [{ productId: tela.id, qty: 0, priceSoldUnit: 200 }],
      },
      400,
    );
    const boundary = await createProduct(companyB.token, {
      nombre: "Boundary UAT",
      codigo: `BOUND-${Date.now()}`,
      categoria: "UoM",
      stock: 5.5,
      precio: 200,
      costo: 100,
      unitOfMeasureId: yard.id,
    });
    await createSale(
      companyB.token,
      {
        paymentMethod: "cash",
        paymentCashAmount: 1100.2,
        items: [{ productId: boundary.id, qty: 5.501, priceSoldUnit: 200 }],
      },
      400,
    );
    await createSale(
      companyB.token,
      {
        paymentMethod: "cash",
        paymentCashAmount: 1200,
        items: [{ productId: boundary.id, qty: 6, priceSoldUnit: 200 }],
      },
      400,
    );
    await createSale(companyB.token, {
      paymentMethod: "cash",
      paymentCashAmount: 1100,
      expectedTotalSold: 1100,
      items: [{ productId: boundary.id, qty: 5.5, priceSoldUnit: 200 }],
    });

    const cartMergeCalc = await request(app.getHttpServer())
      .post("/sales/calculate")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({
        paymentMethod: "cash",
        items: [{ productId: tela.id, qty: 2.375, priceSoldUnit: 200 }],
      })
      .expect(201)
      .then((res) => res.body);
    expect(cartMergeCalc.grandTotal).toBe(475);

    const discounted = await createSale(companyB.token, {
      paymentMethod: "cash",
      paymentCashAmount: 1000,
      globalDiscountAmount: 100,
      items: [
        {
          productId: tela.id,
          qty: 1.25,
          priceSoldUnit: 200,
          taxTreatment: "TAXABLE",
        },
        {
          productId: carne.id,
          qty: 1,
          priceSoldUnit: 180,
          taxTreatment: "EXEMPT",
        },
      ],
    });
    expect(Number(discounted.totalSold)).toBeGreaterThan(0);

    const supplier = await request(app.getHttpServer())
      .post("/purchases/suppliers")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({ commercialName: "Proveedor UAT" })
      .expect(201)
      .then((res) => res.body);
    const order = await request(app.getHttpServer())
      .post("/purchases/orders")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({
        supplierId: supplier.id,
        items: [
          {
            productId: tela.id,
            productName: "Tela Azul UAT",
            quantity: 50.5,
            unitCost: 100,
          },
        ],
      })
      .expect(201)
      .then((res) => res.body);
    await request(app.getHttpServer())
      .post(`/purchases/orders/${order.id}/receive`)
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({
        updateInventory: true,
        items: [
          {
            purchaseOrderItemId: order.items[0].id,
            quantityReceived: 20.25,
            unitCost: 100,
          },
        ],
      })
      .expect(201);
    telaDb = await prisma.product.findUniqueOrThrow({ where: { id: tela.id } });
    expectDecimal(telaDb.stock, "33.5");
    const orderAfter = await prisma.purchaseOrderItem.findUniqueOrThrow({
      where: { id: order.items[0].id },
    });
    expectDecimal(orderAfter.receivedQuantity, "20.25");
    expectDecimal(orderAfter.pendingQuantity, "30.25");

    const stockBeforeReturn = await prisma.product.findUniqueOrThrow({
      where: { id: tela.id },
    });
    const refund = await request(app.getHttpServer())
      .post(`/sales/${telaSale.id}/return`)
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({
        reason: "Phase 2.6 partial UAT",
        items: [{ saleItemId: telaSale.items[0].id, qty: 1.25 }],
      })
      .expect(201)
      .then((res) => res.body);
    expect(refund.kind).toBe("refund");
    expectDecimal(refund.items[0].qty, "1.25");
    telaDb = await prisma.product.findUniqueOrThrow({ where: { id: tela.id } });
    expectDecimal(telaDb.stock, stockBeforeReturn.stock.plus(1.25).toString());
    await request(app.getHttpServer())
      .post(`/sales/${telaSale.id}/return`)
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({ items: [{ saleItemId: telaSale.items[0].id, qty: 4.251 }] })
      .expect(400);

    const cancelSale = await createSale(companyB.token, {
      paymentMethod: "cash",
      paymentCashAmount: 427.5,
      expectedTotalSold: 427.5,
      items: [{ productId: carne.id, qty: 2.375, priceSoldUnit: 180 }],
    });
    carneDb = await prisma.product.findUniqueOrThrow({
      where: { id: carne.id },
    });
    await request(app.getHttpServer())
      .delete(`/sales/${cancelSale.id}`)
      .set("Authorization", `Bearer ${companyB.token}`)
      .expect(200);
    const carneAfterDelete = await prisma.product.findUniqueOrThrow({
      where: { id: carne.id },
    });
    expectDecimal(carneAfterDelete.stock, carneDb.stock.toString());
    evidence.deleteSemantics =
      "DELETE /sales marks sale deleted and does not restore inventory; POST /sales/:id/return is the inventory-restoring workflow.";

    const quotation = await request(app.getHttpServer())
      .post("/cotizaciones")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({
        customerName: "Cliente UAT",
        customerPhone: "8095553333",
        items: [
          { productId: tela.id, qty: 5.5, unitPrice: 200 },
          { productId: carne.id, qty: 2.375, unitPrice: 180 },
        ],
      })
      .expect(201)
      .then((res) => res.body);
    expect(quotation.items[0].unitCodeSnapshot).toBe("YARD");
    expect(quotation.items[1].unitCodeSnapshot).toBe("POUND");

    const snapshotSale = await createSale(companyB.token, {
      paymentMethod: "cash",
      paymentCashAmount: 200,
      expectedTotalSold: 200,
      items: [{ productId: tela.id, qty: 1, priceSoldUnit: 200 }],
    });
    await request(app.getHttpServer())
      .patch(`/products/${tela.id}`)
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({ ...tela, unitOfMeasureId: pound.id })
      .expect(400);
    const historicalItem = await prisma.saleItem.findFirstOrThrow({
      where: { saleId: snapshotSale.id },
    });
    expect(historicalItem.unitCodeSnapshot).toBe("YARD");

    const report = await request(app.getHttpServer())
      .get("/reports/sales-overview")
      .query({ from: "2026-01-01", to: "2026-12-31" })
      .set("Authorization", `Bearer ${companyB.token}`)
      .expect(200)
      .then((res) => res.body);
    const reportText = JSON.stringify(report);
    expect(reportText).toContain("YARD");
    expect(reportText).toContain("POUND");
    expect(reportText).not.toContain("17.875 unidades");

    const saleItemDb = await prisma.saleItem.findUniqueOrThrow({
      where: { id: telaSale.items[0].id },
    });
    expectDecimal(saleItemDb.qty, "5.5");
    expect(saleItemDb.unitSymbolSnapshot).toBe("yd");

    const companyACannotSeeB = await request(app.getHttpServer())
      .get(`/products/${tela.id}`)
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(404);
    expect(companyACannotSeeB.body).toBeDefined();

    evidence.results = {
      legacy: {
        stock: legacyAfter.stock.toString(),
        total: legacySale.totalSold,
      },
      yardSale: {
        qty: saleItemDb.qty.toString(),
        stockAfterSale: "14.5",
        stockAfterPurchaseAndReturn: telaDb.stock.toString(),
      },
      poundSale: { stock: carneAfterDelete.stock.toString() },
      fraction: { stock: fractionDb.stock.toString() },
      purchase: {
        received: orderAfter.receivedQuantity.toString(),
        pending: orderAfter.pendingQuantity.toString(),
      },
      return: {
        qty: refund.items[0].qty,
        unit: refund.items[0].unitCodeSnapshot,
      },
      quotationUnits: quotation.items.map((item: any) => ({
        qty: item.qty,
        unit: item.unitCodeSnapshot,
      })),
      reportCategoryLabels: report.categoryProfits.map((row: any) => ({
        category: row.category,
        totalQtyLabel: row.totalQtyLabel,
      })),
      tenantIsolation: "Company A received 404 for Company B product",
    };
  });
});
