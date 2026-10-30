import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../../app.module";
import { PrismaService } from "../../prisma/prisma.service";

/**
 * Clasificación fiscal supervisada (F1) — HTTP real + PostgreSQL real.
 *
 * Se levanta la aplicación completa contra una base DESECHABLE y se la conduce
 * por HTTP: login real, JWT real, `AuthGuard`/`RolesGuard` reales y validación de
 * DTO real. Es la única forma de demostrar que el permiso nuevo se exige de
 * verdad y que la empresa sale del contexto autenticado.
 *
 * La venta y su partida se siembran por Prisma a propósito: son PRECONDICIÓN del
 * módulo (el flujo POS completo ya está cubierto por
 * `legacy-pos-compatibility-http.e2e-spec.ts`) y así esta prueba se centra en la
 * superficie de clasificación.
 *
 * Sin proveedor, sin emisión y sin numeración real.
 */
jest.setTimeout(240000);

const PASSWORD = "EcfF1HttpE2E123!";
const SAFE_DB = /^fullpos_f1_http_e2e_/;
const uat = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

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

uat("F1 clasificación fiscal — HTTP + PostgreSQL", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;
  let fleet = 900000;

  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_f1_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "ecf-f1-http-e2e-secret";
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
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
    prisma = app.get(PrismaService);
  }, 240000);

  afterAll(async () => {
    if (app) await app.close();
    if (adminUrl && dbName && SAFE_DB.test(dbName)) {
      const admin = new Client({ connectionString: adminUrl });
      await admin.connect();
      await admin.query(
        `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()`,
        [dbName],
      );
      // La base se destruye entera: la tabla de clasificaciones es APPEND-ONLY y
      // su trigger impide borrar filas, así que no se limpia por tablas.
      await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
      await admin.end();
    }
  }, 120000);

  async function registerTenant(suffix: string) {
    const email = `f1-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "F1",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `F1 ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Av. Sintética ${suffix}`,
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

  async function createOperator(
    adminToken: string,
    permissions: Record<string, boolean>,
  ) {
    fleet += 1;
    const email = `f1-op-${Date.now()}-${randomUUID().slice(0, 6)}@example.test`;
    await http()
      .post("/users")
      .set("Authorization", `Bearer ${adminToken}`)
      .send({
        email,
        password: PASSWORD,
        nombreCompleto: "Operador F1",
        telefono: `809555${String(fleet).slice(-4)}`,
        numeroFlota: String(fleet),
        edad: 30,
        role: "VENDEDOR",
        userPermissions: permissions,
      })
      .expect(201);
    const login = await http()
      .post("/auth/login")
      .send({ email, password: PASSWORD })
      .expect(201);
    return { token: login.body.accessToken as string };
  }

  /** Venta con una partida SIN producto: el caso que hay que poder resolver. */
  async function saleWithoutProduct(companyId: string, userId: string) {
    const sale = await prisma.sale.create({
      data: {
        companyId,
        userId,
        totalSold: "100.00",
        totalCost: "0.00",
        totalProfit: "0.00",
        commissionAmount: "0.00",
        taxableBase: "100.00",
        exemptAmount: "0.00",
        discountAmount: "0.00",
        taxAmount: "0.00",
        fiscalTaxEnabled: true,
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1, Santo Domingo",
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
      },
    });
    const item = await prisma.saleItem.create({
      data: {
        saleId: sale.id,
        productId: null,
        productNameSnapshot: "Servicio suelto",
        qty: "1",
        priceSoldUnit: "100.00",
        costUnitSnapshot: "0.00",
        subtotalSold: "100.00",
        subtotalCost: "0.00",
        profit: "100.00",
        grossAmount: "100.00",
        lineDiscountAmount: "0.00",
        taxableBase: "100.00",
        exemptAmount: "0.00",
        taxAmount: "0.00",
        taxRate: "0.0000",
        taxExempt: true,
        itemTypeSnapshot: null,
      },
    });
    return { sale, item };
  }

  const getPending = (token: string, saleId: string) =>
    http()
      .get(`/ecf/documents/${saleId}/pending-classifications`)
      .set("Authorization", `Bearer ${token}`);

  const confirm = (token: string, body: Record<string, unknown>) =>
    http()
      .post("/ecf/documents/line-classifications")
      .set("Authorization", `Bearer ${token}`)
      .send(body);

  it("sin sesión no se expone nada", async () => {
    const tenant = await registerTenant("sin-sesion");
    const { sale } = await saleWithoutProduct(tenant.companyId, tenant.userId);

    await http()
      .get(`/ecf/documents/${sale.id}/pending-classifications`)
      .expect(401);
    await http()
      .post("/ecf/documents/line-classifications")
      .send({ saleId: sale.id, saleItemId: randomUUID() })
      .expect(401);
  });

  it("el permiso es propio: consultar no basta para confirmar", async () => {
    const tenant = await registerTenant("permiso");
    const { sale, item } = await saleWithoutProduct(
      tenant.companyId,
      tenant.userId,
    );
    const viewer = await createOperator(tenant.token, {
      viewEcfDocuments: true,
    });

    // Puede CONSULTAR el bloqueo…
    const view = await getPending(viewer.token, sale.id).expect(200);
    expect(view.body.lines).toHaveLength(1);
    expect(view.body.lines[0].needsClassification).toBe(true);
    expect(view.body.lines[0].canConfirm).toBe(true);

    // …pero NO confirmar: el permiso de confirmación es independiente.
    await confirm(viewer.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "Intento sin permiso",
    }).expect(403);

    // Y no quedó nada escrito.
    expect(
      await prisma.ecfLineClassification.count({
        where: { companyId: tenant.companyId },
      }),
    ).toBe(0);
  });

  it("un usuario sin permisos e-CF no ve ni toca nada", async () => {
    const tenant = await registerTenant("sin-permisos");
    const { sale, item } = await saleWithoutProduct(
      tenant.companyId,
      tenant.userId,
    );
    const operator = await createOperator(tenant.token, {});

    await getPending(operator.token, sale.id).expect(403);
    await confirm(operator.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "Sin permiso alguno",
    }).expect(403);
  });

  it("el contrato rechaza una clasificación inventada y un motivo vacío", async () => {
    const tenant = await registerTenant("contrato");
    const { sale, item } = await saleWithoutProduct(
      tenant.companyId,
      tenant.userId,
    );

    await confirm(tenant.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "MERCANCIA",
      reason: "Clasificación que no existe",
    }).expect(400);

    await confirm(tenant.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "",
    }).expect(400);

    await confirm(tenant.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "ok",
      companyId: randomUUID(),
    }).expect(400);

    expect(
      await prisma.ecfLineClassification.count({
        where: { companyId: tenant.companyId },
      }),
    ).toBe(0);
  });

  it("el caso completo: confirmar desbloquea sin tocar la venta", async () => {
    const tenant = await registerTenant("completo");
    const { sale, item } = await saleWithoutProduct(
      tenant.companyId,
      tenant.userId,
    );

    const before = await prisma.saleItem.findUniqueOrThrow({
      where: { id: item.id },
    });
    const saleBefore = await prisma.sale.findUniqueOrThrow({
      where: { id: sale.id },
    });

    const res = await confirm(tenant.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "SERVICE",
      reason: "El operador verificó que es mano de obra",
    }).expect(201);
    expect(res.body.classification.classification).toBe("SERVICE");
    // El estado que se devuelve ya viene recalculado por el backend.
    expect(res.body.sale.lines[0].needsClassification).toBe(false);
    expect(res.body.sale.lines[0].effectiveClassification).toBe("SERVICE");

    // La partida histórica NO se modificó.
    const after = await prisma.saleItem.findUniqueOrThrow({
      where: { id: item.id },
    });
    expect(after.itemTypeSnapshot).toBeNull();
    expect(after.taxableBase.toString()).toBe(before.taxableBase.toString());
    expect(after.taxAmount.toString()).toBe(before.taxAmount.toString());
    // La venta tampoco, y la caja no se toca.
    const saleAfter = await prisma.sale.findUniqueOrThrow({
      where: { id: sale.id },
    });
    expect(saleAfter.totalSold.toFixed(2)).toBe(
      saleBefore.totalSold.toFixed(2),
    );
    expect(
      await prisma.cashMovement.count({
        where: { companyId: tenant.companyId },
      }),
    ).toBe(0);

    // Y el hecho queda auditado.
    const audit = await prisma.ecfAuditLog.findMany({
      where: {
        companyId: tenant.companyId,
        action: "LINE_CLASSIFICATION_CONFIRMED",
      },
    });
    expect(audit).toHaveLength(1);
    expect(audit[0].actorUserId).toBe(tenant.userId);

    // La consulta posterior ya lo refleja.
    const afterView = await getPending(tenant.token, sale.id).expect(200);
    expect(afterView.body.lines[0].needsClassification).toBe(false);
    expect(afterView.body.lines[0].canConfirm).toBe(false);
  });

  it("la clasificación no cruza empresas, ni con el identificador real", async () => {
    const a = await registerTenant("empresa-a");
    const b = await registerTenant("empresa-b");
    const { sale, item } = await saleWithoutProduct(a.companyId, a.userId);

    // B conoce los identificadores reales de A y aun así no alcanza nada.
    await getPending(b.token, sale.id).expect(404);
    await confirm(b.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "Intento desde otra empresa",
    }).expect(404);

    // Un identificador inventado se comporta igual: no filtra existencia.
    await getPending(b.token, randomUUID()).expect(404);
    await confirm(b.token, {
      saleId: randomUUID(),
      saleItemId: item.id,
      classification: "PRODUCT",
      reason: "Venta ajena inexistente",
    }).expect(404);

    // En B no quedó ningún rastro.
    expect(
      await prisma.ecfLineClassification.count({ where: { companyId: b.companyId } }),
    ).toBe(0);
    expect(
      await prisma.ecfAuditLog.count({ where: { companyId: b.companyId } }),
    ).toBe(0);
  });

  it("no se clasifica una partida cuya venta ya congeló el tipo", async () => {
    const tenant = await registerTenant("congelada");
    const { sale, item } = await saleWithoutProduct(
      tenant.companyId,
      tenant.userId,
    );
    await prisma.saleItem.updateMany({
      where: { id: item.id },
      data: { itemTypeSnapshot: "PRODUCT" },
    });

    await confirm(tenant.token, {
      saleId: sale.id,
      saleItemId: item.id,
      classification: "SERVICE",
      reason: "Intento de reclasificar una venta que ya declaró su tipo",
    }).expect(409);

    const view = await getPending(tenant.token, sale.id).expect(200);
    // La clasificación de la venta manda.
    expect(view.body.lines[0].effectiveClassification).toBe("PRODUCT");
    expect(view.body.lines[0].canConfirm).toBe(false);
  });
});
