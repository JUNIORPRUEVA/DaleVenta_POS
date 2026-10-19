import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../app.module";
import { PrismaService } from "../prisma/prisma.service";

const PASSWORD = "MayoreoE2E123!";
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

describe("Price lists authenticated HTTP E2E", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;

  async function registerCompany(suffix: string) {
    const res = await request(app.getHttpServer())
      .post("/auth/register-business")
      .send({
        firstName: "Mayoreo",
        lastName: suffix,
        email: `mayoreo-${Date.now()}-${suffix}@example.test`,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Mayoreo ${suffix}`,
        taxId: suffix === "a" ? "121212121" : "232323232",
        businessPhone: "8095551111",
        address: `UAT ${suffix}`,
        country: "DO",
      })
      .expect(201);
    return {
      token: res.body.accessToken as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  async function createProduct(token: string, suffix: string, price: number) {
    return request(app.getHttpServer())
      .post("/products")
      .set("Authorization", `Bearer ${token}`)
      .send({
        nombre: `Cable mayorista ${suffix}`,
        codigo: `MY-${Date.now()}-${suffix}`,
        categoria: "Mayoreo",
        precio: price,
        costo: price / 2,
        stock: 100,
      })
      .expect(201)
      .then((res) => res.body);
  }

  beforeAll(async () => {
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_mayoreo_http_e2e_${Date.now()}_test`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!dbName.endsWith("_test") || !dbName.includes("mayoreo_http_e2e")) {
      throw new Error("Unsafe E2E DB name");
    }

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE "${dbName}"`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.PRODUCTS_SOURCE = "LOCAL";
    process.env.JWT_SECRET = process.env.JWT_SECRET || "mayoreo-e2e-secret";
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
      env: { ...process.env, DATABASE_URL: appUrl, PRODUCTS_SOURCE: "LOCAL" },
      stdio: "pipe",
    });

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    await app.init();
    prisma = app.get(PrismaService);
  }, 180000);

  afterAll(async () => {
    if (prisma) await prisma.$disconnect();
    if (app) await app.close();
    if (adminUrl && dbName && dbName.endsWith("_test")) {
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

  it("creates, lists, assigns and resolves price lists per tenant", async () => {
    const companyA = await registerCompany("a");
    const companyB = await registerCompany("b");

    await request(app.getHttpServer())
      .patch("/settings")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({ wholesalePriceListsEnabled: true })
      .expect(200);
    await request(app.getHttpServer())
      .patch("/settings")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({ wholesalePriceListsEnabled: true })
      .expect(200);

    const productA = await createProduct(companyA.token, "a", 100);
    const productB = await createProduct(companyB.token, "b", 200);

    const listA = await request(app.getHttpServer())
      .post("/price-lists")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({ name: "Mayorista A" })
      .expect(201)
      .then((res) => res.body);

    await request(app.getHttpServer())
      .post(`/price-lists/${listA.id}/rules`)
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({
        productId: productA.id,
        mode: "FIXED_PRICE",
        fixedPrice: 80,
        minQuantity: 1,
      })
      .expect(201);

    const client = await request(app.getHttpServer())
      .post("/clients")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({ nombre: "Cliente mayorista", telefono: "8095553333" })
      .expect(201)
      .then((res) => res.body);

    await request(app.getHttpServer())
      .patch(`/price-lists/clients/${client.id}`)
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({ priceListId: listA.id })
      .expect(200);

    const resolved = await request(app.getHttpServer())
      .post("/price-lists/resolve-line")
      .set("Authorization", `Bearer ${companyA.token}`)
      .send({ productId: productA.id, qty: 2, clientId: client.id })
      .expect(201)
      .then((res) => res.body);
    expect(resolved).toMatchObject({
      applied: true,
      unitPrice: 80,
      originalUnitPrice: 100,
    });

    const listed = await request(app.getHttpServer())
      .get("/price-lists")
      .set("Authorization", `Bearer ${companyA.token}`)
      .expect(200)
      .then((res) => res.body);
    expect(listed).toEqual(
      expect.arrayContaining([expect.objectContaining({ id: listA.id })]),
    );

    await request(app.getHttpServer())
      .post("/price-lists/resolve-line")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({ productId: productA.id, qty: 1, priceListId: listA.id })
      .expect(400);

    const tenantBResolution = await request(app.getHttpServer())
      .post("/price-lists/resolve-line")
      .set("Authorization", `Bearer ${companyB.token}`)
      .send({ productId: productB.id, qty: 1 })
      .expect(201)
      .then((res) => res.body);
    expect(tenantBResolution.applied).toBe(false);

    const currentDb = await prisma.$queryRawUnsafe<
      Array<{ current_database: string }>
    >("SELECT current_database()");
    expect(currentDb[0]?.current_database).toBe(dbName);
  });
});
