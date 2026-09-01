/**
 * SYNC-03 FINAL END-TO-END RECOVERY AND MULTI-TENANT VALIDATION
 *
 * Proves the full offline-sync recovery flow against a REAL, ISOLATED UAT
 * database (never production):
 *
 *   1. settings.save (PATCH /settings) forwards defaultTaxId to fiscal
 *      settings and persists it (the exact payload the client sync handler
 *      replays for a queued settings.save).
 *   2. Product delete normal case  -> deleted exactly once.
 *   3. Product delete already-deleted (response-loss retry) -> idempotent ok.
 *   4. Product delete FK/history conflict -> HTTP 409 Conflict (not 500).
 *   5. Cross-tenant delete -> never mutates another company's product.
 *   6. Queued replay tenant safety -> Company A token cannot read/mutate
 *      Company B fiscal settings, and vice versa.
 *   7. Sale replay exact-once (clientRequestId) with single stock decrement.
 *
 * The client-side classification of these HTTP responses (409 -> permanent
 * "conflict", no retry storm; network -> retryable backoff) is proven by the
 * Flutter test suite (test/core/offline/sync_queue_service_test.dart).
 *
 * Safety: creates an isolated `*_sync03_test` database, refuses to run
 * otherwise, migrates it, and drops it on teardown. No production writes.
 */

import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "./app.module";
import { PrismaService } from "./prisma/prisma.service";

const PASSWORD = "Sync03Uat123!";
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

describe("SYNC-03 end-to-end offline recovery + multi-tenant (isolated UAT DB)", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;

  async function assertTestDatabase() {
    const [db] = await prisma.$queryRawUnsafe<Array<{ current_database: string }>>(
      "SELECT current_database()",
    );
    if (!db?.current_database?.endsWith("_sync03_test")) {
      throw new Error(`Unsafe database for SYNC-03 UAT: ${db?.current_database}`);
    }
  }

  async function registerCompany(suffix: string) {
    await assertTestDatabase();
    const email = `sync03-${Date.now()}-${suffix}@example.test`;
    const res = await request(app.getHttpServer())
      .post("/auth/register-business")
      .send({
        firstName: "Sync",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Sync03 ${suffix}`,
        taxId: suffix === "b" ? "404040404" : "303030303",
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

  async function createProduct(token: string, body: Record<string, unknown>) {
    await assertTestDatabase();
    return request(app.getHttpServer())
      .post("/products")
      .set("Authorization", `Bearer ${token}`)
      .send(body)
      .expect(201)
      .then((res) => res.body);
  }

  async function createTax(token: string, name: string, rate: number) {
    await assertTestDatabase();
    return request(app.getHttpServer())
      .post("/taxes")
      .set("Authorization", `Bearer ${token}`)
      .send({ name, rate, isActive: true, isDefault: false })
      .expect(201)
      .then((res) => res.body);
  }

  beforeAll(async () => {
    const baseUrl = baseDatabaseUrl();
    const productionDb = dbNameFromUrl(baseUrl);
    dbName = `daleventas_sync03_${Date.now()}_sync03_test`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!dbName.endsWith("_sync03_test")) {
      throw new Error("Unsafe SYNC-03 UAT DB name");
    }

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE "${dbName}"`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "sync03-uat-secret";
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
    if (adminUrl && dbName && dbName.endsWith("_sync03_test")) {
      const admin = new Client({ connectionString: adminUrl });
      await admin.connect();
      await admin.query(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
        [dbName],
      );
      await admin.query(`DROP DATABASE IF EXISTS "${dbName}"`);
      await admin.end();
    }
  }, 60000);

  it("persists defaultTaxId via generic settings.save and isolates tenants", async () => {
    await assertTestDatabase();
    const companyA = await registerCompany("settings-a");
    const companyB = await registerCompany("settings-b");

    const tax = await createTax(companyA.token, "ITBIS 18 SYNC03", 0.18);
    // This is exactly the payload the client sync handler replays for a
    // queued `settings.save` (see CompanySettingsRepository._saveSettingsRemote).
    const saved = await request(app.getHttpServer())
      .patch("/settings")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({
        taxEnabled: true,
        defaultTaxId: tax.id,
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      })
      .expect(200);

    // The settings response is flat: fiscal fields live at the top level.
    expect(saved.body.defaultTaxId).toBe(tax.id);
    expect(saved.body.taxEnabled).toBe(true);

    const persisted = await prisma.company.findUniqueOrThrow({
      where: { id: companyA.companyId },
    });
    expect(persisted.defaultTaxId).toBe(tax.id);
    expect(Number(persisted.defaultTaxRate)).toBeCloseTo(0.18, 6);

    const settingsB = await request(app.getHttpServer())
      .get("/settings")
      .set("Authorization", `Bearer ${companyB.token}`)
      .expect(200)
      .then((res) => res.body);
    expect(settingsB.defaultTaxId).not.toBe(tax.id);
    expect(settingsB.taxEnabled).not.toBe(true);
  }, 60000);

  it("deletes a disposable product exactly once and treats retries idempotently", async () => {
    await assertTestDatabase();
    const companyA = await registerCompany("delete-normal");

    // Disposable product: stock 0 so NO INITIAL_STOCK InventoryMovement is
    // created (onDelete: Restrict would block the delete).
    const product = await createProduct(companyA.token, {
      nombre: "Producto descartable SYNC03",
      codigo: `SYNC03-DEL-${Date.now()}`,
      categoria: "Sync",
      stock: 0,
      precio: 120,
      costo: 50,
    });

    const first = await request(app.getHttpServer())
      .delete(`/products/${product.id}`)
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(200);
    expect(first.body.ok).toBe(true);

    const countAfterFirst = await prisma.product.count({
      where: { id: product.id, companyId: companyA.companyId },
    });
    expect(countAfterFirst).toBe(0);

    // Response-loss retry: product is already absent -> idempotent ok (no 500).
    const retry = await request(app.getHttpServer())
      .delete(`/products/${product.id}`)
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(200);
    expect(retry.body.ok).toBe(true);
  }, 60000);

  it("returns HTTP 409 Conflict (not 500) when product history blocks delete", async () => {
    await assertTestDatabase();
    const companyA = await registerCompany("delete-fk");

    // Creating a product with stock > 0 auto-records an INITIAL_STOCK
    // InventoryMovement (onDelete: Restrict), which blocks physical delete.
    const product = await createProduct(companyA.token, {
      nombre: "Producto con historial SYNC03",
      codigo: `SYNC03-FK-${Date.now()}`,
      categoria: "Sync",
      stock: 3,
      precio: 80,
      costo: 30,
    });

    const movements = await prisma.inventoryMovement.count({
      where: { companyId: companyA.companyId, productId: product.id },
    });
    expect(movements).toBeGreaterThan(0);

    const res = await request(app.getHttpServer())
      .delete(`/products/${product.id}`)
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(409);

    expect(res.status).toBe(409);
    expect(`${(res.body as { message?: unknown }).message ?? ""}`).toMatch(
      /historial de inventario|transferencias/i,
    );

    // Operation did NOT complete: the product must still exist.
    const stillThere = await prisma.product.count({
      where: { id: product.id, companyId: companyA.companyId },
    });
    expect(stillThere).toBe(1);
  }, 60000);

  it("never mutates another tenant's product from a cross-tenant delete", async () => {
    await assertTestDatabase();
    const companyA = await registerCompany("x-tenant-a");
    const companyB = await registerCompany("x-tenant-b");

    // Disposable product (stock 0) so Company A can later delete it.
    const productA = await createProduct(companyA.token, {
      nombre: "Producto A SYNC03",
      codigo: `SYNC03-XA-${Date.now()}`,
      categoria: "Sync",
      stock: 0,
      precio: 60,
      costo: 20,
    });

    // Company B replays a queued delete for Company A's product.
    // Tenant comes from the JWT, so this must NOT delete A's product.
    const res = await request(app.getHttpServer())
      .delete(`/products/${productA.id}`)
      .set("Authorization", `Bearer ${companyB.token}`)
      .expect(200);
    expect(res.body.ok).toBe(true);

    const stillThere = await prisma.product.count({
      where: { id: productA.id, companyId: companyA.companyId },
    });
    expect(stillThere).toBe(1);

    // Company A can still delete its own product.
    await request(app.getHttpServer())
      .delete(`/products/${productA.id}`)
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(200);
    expect(
      await prisma.product.count({
        where: { id: productA.id, companyId: companyA.companyId },
      }),
    ).toBe(0);
  }, 60000);

  it("replays queued sale exactly once (single stock decrement) under response loss", async () => {
    await assertTestDatabase();
    const companyA = await registerCompany("sale-idem");
    await prisma.cashSession.create({
      data: {
        companyId: companyA.companyId,
        openedByUserId: companyA.userId,
        initialAmount: "0",
        status: "OPEN",
      },
    });

    const product = await createProduct(companyA.token, {
      nombre: "Producto venta idempotente SYNC03",
      codigo: `SYNC03-SALE-${Date.now()}`,
      categoria: "Sync",
      stock: 10,
      precio: 100,
      costo: 40,
    });

    const payload = {
      clientRequestId: `sync03-sale-response-lost-${Date.now()}`,
      paymentMethod: "cash",
      paymentCashAmount: 200,
      items: [
        {
          productId: product.id,
          qty: 2,
          priceSoldUnit: 100,
          costUnitSnapshot: 40,
        },
      ],
    };

    const first = await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send(payload)
      .expect(201);

    const retry = await request(app.getHttpServer())
      .post("/sales")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({ ...payload, paymentCashAmount: 9999 })
      .expect(201);

    expect(retry.body.id).toBe(first.body.id);

    const sales = await prisma.sale.findMany({
      where: {
        companyId: companyA.companyId,
        clientRequestId: payload.clientRequestId,
      },
      include: { items: true },
    });
    expect(sales).toHaveLength(1);
    expect(sales[0].items).toHaveLength(1);
    expect(Number(sales[0].paymentCashAmount)).toBeCloseTo(200, 2);

    const stockNow = await prisma.product.findUniqueOrThrow({
      where: { id: product.id },
    });
    expect(Number(stockNow.stock)).toBeCloseTo(8, 3);
  }, 60000);
});
