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
 * COMPATIBILIDAD DEL POS TRADICIONAL con el módulo e-CF.
 *
 * Este arnés **no** prueba e-CF: prueba que e-CF no rompe la venta normal. Es la
 * dirección que más importa, porque FullPOS Cloud ya tiene negocios facturando
 * todos los días y ninguno puede empezar a fallar por una función que ni usan.
 *
 * Contrato de compatibilidad que el backend aplica hoy (verificado aquí sobre
 * HTTP real contra PostgreSQL real):
 *
 *  - La venta se clasifica por `originCashSessionId` (campo nuevo requerido) y
 *    `originTerminalId` (nuevo opcional) en `classifyFinancialContract`.
 *  - Sin ninguno de los dos → ruta ANTIGUA: se admite SOLO si el interruptor
 *    `FINANCIAL_LEGACY_COMPAT` está activo; si no, responde
 *    `LEGACY_MISSING_SESSION` («Actualiza Fullpos…»).
 *  - Con el opcional pero sin el requerido → solicitud PARCIAL: se rechaza
 *    siempre con `INVALID_PARTIAL_FINANCIAL_REQUEST`, haya o no interruptor.
 *    Distinguir al cliente viejo de una actualización a medias es deliberado.
 *
 * Nada de esto es e-CF: es el contrato financiero que ya existía. Lo que se
 * demuestra es que e-CF no lo altera y que vender nunca escribe en `ecf_*`.
 *
 * Base DESECHABLE creada para esta ejecución y destruida al terminar. Sin
 * proveedor, sin emisión y sin numeración real.
 */
jest.setTimeout(240000);

const PASSWORD = "LegacyPosCompat123!";
const SAFE_DB = /^fullpos_legacy_pos_e2e_/;
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

uat("POS tradicional — compatibilidad con e-CF (HTTP + PostgreSQL)", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let dbName: string;
  let appUrl: string;
  let adminUrl: string;
  let unitId: string;

  const http = () => request(app.getHttpServer());

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_legacy_pos_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "legacy-pos-e2e-secret";
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
    // Misma validación global que `main.ts`: sin ella no se probaría el
    // contrato real que ve el cliente antiguo.
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
    prisma = app.get(PrismaService);

    unitId = `UNIT_${randomUUID().slice(0, 8)}`;
    await prisma.unitOfMeasure.create({
      data: {
        id: unitId,
        code: unitId,
        name: "Unidad",
        symbol: "u",
        category: "COUNT",
      },
    });
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
      await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
      await admin.end();
    }
  }, 120000);

  /** Ejecuta un bloque con `FINANCIAL_LEGACY_COMPAT` en el valor indicado. */
  async function withLegacyFlag<T>(
    enabled: boolean,
    run: () => Promise<T>,
  ): Promise<T> {
    const previous = process.env.FINANCIAL_LEGACY_COMPAT;
    process.env.FINANCIAL_LEGACY_COMPAT = enabled ? "true" : "false";
    try {
      return await run();
    } finally {
      if (previous === undefined) delete process.env.FINANCIAL_LEGACY_COMPAT;
      else process.env.FINANCIAL_LEGACY_COMPAT = previous;
    }
  }

  async function registerTenant(suffix: string) {
    const email = `legacy-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Legacy",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Legacy ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Av. Sintética ${suffix}`,
        country: "DO",
      })
      .expect(201);
    return {
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  /**
   * Abre un turno de caja y devuelve su identificador leído de la base.
   *
   * Es una precondición REAL de la venta: sin turno abierto no hay venta, ni
   * por la ruta antigua ni por la nueva. El id se resuelve en PostgreSQL en vez
   * de adivinar la forma de la respuesta del endpoint.
   */
  async function openSession(
    token: string,
    companyId: string,
    userId: string,
  ) {
    await http()
      .post("/cash/sessions/open")
      .set("Authorization", `Bearer ${token}`)
      .send({ openingAmount: 0 })
      .expect(201);
    const session = await prisma.cashSession.findFirstOrThrow({
      where: { companyId, openedByUserId: userId, status: "OPEN" },
      orderBy: { openedAt: "desc" },
    });
    return session.id;
  }

  /** Cliente con identificación fiscal: lo exige el comprobante tradicional. */
  async function createFiscalClient(companyId: string, ownerId: string) {
    return prisma.client.create({
      data: {
        companyId,
        ownerId,
        nombre: "Cliente Tradicional SA",
        telefono: "8095551234",
        taxId: "130000000",
        businessName: "Cliente Tradicional SA",
      },
    });
  }

  /**
   * Activa los comprobantes fiscales TRADICIONALES (NCF) y registra una serie.
   *
   * Sin esto la venta con NCF se rechaza con «Los comprobantes fiscales no
   * están activados para esta empresa»: es una precondición previa a e-CF, no
   * una consecuencia suya.
   */
  async function enableTraditionalFiscal(token: string) {
    await http()
      .patch("/company/fiscal-settings")
      .set("Authorization", `Bearer ${token}`)
      .send({ ncfEnabled: true })
      .expect(200);
    await http()
      .post("/ncf/sequences")
      .set("Authorization", `Bearer ${token}`)
      .send({
        voucherType: "B01",
        prefix: "B01",
        startNumber: 1,
        endNumber: 100,
      })
      .expect(201);
  }

  async function createProduct(companyId: string) {
    return prisma.product.create({
      data: {
        companyId,
        nombre: "Producto gravado",
        codigo: `SKU-${randomUUID().slice(0, 8)}`,
        categoria: "General",
        costo: "1.00",
        precio: "118.00",
        unitOfMeasureId: unitId,
        itemType: "PRODUCT",
      },
    });
  }

  /** Ninguna tabla e-CF debe haber sido tocada por una venta. */
  async function ecfRowCount(companyId: string) {
    const [documents, evidence, reservations, habilitation] = await Promise.all([
      prisma.ecfElectronicDocument.count({ where: { companyId } }),
      prisma.ecfEvidenceReceipt.count({ where: { companyId } }),
      prisma.ecfCreditReservation.count({ where: { companyId } }),
      prisma.ecfDgiiHabilitation.count({ where: { companyId } }),
    ]);
    return { documents, evidence, reservations, habilitation };
  }

  const postSale = (token: string, body: Record<string, unknown>) =>
    http()
      .post("/sales")
      .set("Authorization", `Bearer ${token}`)
      .send(body);

  /** Espera un estado concreto y, si no coincide, muestra el cuerpo real. */
  async function expectStatus(
    req: request.Test,
    status: number,
  ): Promise<request.Response> {
    const res = await req;
    if (res.status !== status) {
      throw new Error(
        `Se esperaba ${status} y respondió ${res.status}: ${JSON.stringify(res.body)}`,
      );
    }
    return res;
  }

  /** Payload que un POS antiguo ya instalado envía hoy: sin campos nuevos. */
  const legacySaleBody = {
    items: [
      {
        productName: "Servicio suelto",
        qty: 2,
        priceSoldUnit: 50,
        costUnitSnapshot: 20,
      },
    ],
    paymentMethod: "cash",
  };

  it("la ruta antigua sigue vendiendo cuando el interruptor está activo", async () => {
    const tenant = await registerTenant("antiguo-ok");
    await openSession(tenant.token, tenant.companyId, tenant.userId);

    const res = await withLegacyFlag(true, () =>
      postSale(tenant.token, legacySaleBody).expect(201),
    );
    const saleId = (res.body.id ?? res.body.sale?.id) as string;
    expect(saleId).toBeTruthy();

    // El POS no perdió nada: la venta quedó escrita.
    expect(
      await prisma.sale.count({ where: { companyId: tenant.companyId } }),
    ).toBe(1);

    // Y vender no escribió una sola fila e-CF.
    expect(await ecfRowCount(tenant.companyId)).toEqual({
      documents: 0,
      evidence: 0,
      reservations: 0,
      habilitation: 0,
    });
  });

  it("con el interruptor apagado la ruta antigua se rechaza y no crea nada", async () => {
    const tenant = await registerTenant("antiguo-bloqueado");
    // Hay turno abierto: si se rechaza, es SOLO por el interruptor.
    await openSession(tenant.token, tenant.companyId, tenant.userId);

    const res = await withLegacyFlag(false, () =>
      postSale(tenant.token, legacySaleBody),
    );
    expect(res.status).toBe(409);
    expect(res.body.errorCode ?? res.body.code).toBe("LEGACY_MISSING_SESSION");

    // Se rechaza ANTES de escribir: no queda una venta a medias.
    expect(
      await prisma.sale.count({ where: { companyId: tenant.companyId } }),
    ).toBe(0);
    expect(await ecfRowCount(tenant.companyId)).toEqual({
      documents: 0,
      evidence: 0,
      reservations: 0,
      habilitation: 0,
    });
  });

  it("una solicitud parcial se rechaza aunque el interruptor esté activo", async () => {
    const tenant = await registerTenant("parcial");
    await openSession(tenant.token, tenant.companyId, tenant.userId);

    // Manda el campo opcional nuevo pero NO el requerido: es una actualización
    // a medias, no un cliente antiguo, y el backend no adivina cuál es.
    const res = await withLegacyFlag(true, () =>
      postSale(tenant.token, {
        ...legacySaleBody,
        originTerminalId: randomUUID(),
      }),
    );
    expect(res.status).toBe(409);
    expect(res.body.errorCode ?? res.body.code).toBe(
      "INVALID_PARTIAL_FINANCIAL_REQUEST",
    );
    expect(
      await prisma.sale.count({ where: { companyId: tenant.companyId } }),
    ).toBe(0);
  });

  it("una venta fiscal tradicional con NCF se guarda sin volverse e-CF", async () => {
    const tenant = await registerTenant("ncf");
    await openSession(tenant.token, tenant.companyId, tenant.userId);
    await enableTraditionalFiscal(tenant.token);
    const client = await createFiscalClient(tenant.companyId, tenant.userId);

    const res = await withLegacyFlag(true, () =>
      expectStatus(
        postSale(tenant.token, {
          items: [
            {
              productName: "Producto tradicional",
              qty: 1,
              priceSoldUnit: 118,
              costUnitSnapshot: 80,
            },
          ],
          paymentMethod: "cash",
          customerId: client.id,
          fiscalVoucherType: "B01",
          ncf: "B0100000001",
          fiscalCustomerTaxId: "130000000",
          fiscalCustomerName: "Cliente Tradicional SA",
        }),
        201,
      ),
    );

    const saleId = (res.body.id ?? res.body.sale?.id) as string;
    const sale = await prisma.sale.findFirstOrThrow({
      where: { id: saleId, companyId: tenant.companyId },
    });
    expect(sale.ncf).toBe("B0100000001");
    expect(sale.fiscalCustomerName).toBe("Cliente Tradicional SA");

    expect(await ecfRowCount(tenant.companyId)).toEqual({
      documents: 0,
      evidence: 0,
      reservations: 0,
      habilitation: 0,
    });
  });

  it("con e-CF encendido, vender congela la clasificación y no prepara nada", async () => {
    const tenant = await registerTenant("encendido");
    const product = await createProduct(tenant.companyId);

    await http()
      .patch("/ecf/config")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ enabled: true })
      .expect(200);

    // Ruta NUEVA (con turno explícito): no depende de ningún interruptor.
    const sessionId = await openSession(
      tenant.token,
      tenant.companyId,
      tenant.userId,
    );
    const res = await expectStatus(
      postSale(tenant.token, {
        items: [
          {
            productId: product.id,
            productSource: "LOCAL",
            productName: product.nombre,
            qty: 1,
            priceSoldUnit: 118,
            inventoryTrackedSnapshot: false,
          },
        ],
        paymentMethod: "cash",
        originCashSessionId: sessionId,
      }),
      201,
    );

    const saleId = (res.body.id ?? res.body.sale?.id) as string;
    const item = await prisma.saleItem.findFirstOrThrow({
      where: { saleId, sale: { companyId: tenant.companyId } },
    });
    // La clasificación fiscal queda CONGELADA con la venta, no al facturar.
    expect(item.itemTypeSnapshot).toBe("PRODUCT");

    // La preparación es una acción explícita y aparte: vender no la ejecutó.
    expect(await ecfRowCount(tenant.companyId)).toEqual({
      documents: 0,
      evidence: 0,
      reservations: 0,
      habilitation: 0,
    });
  });

  it("una partida sin producto no rompe la venta y e-CF se niega a adivinarla", async () => {
    const tenant = await registerTenant("sin-producto");
    await http()
      .patch("/ecf/config")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ enabled: true })
      .expect(200);
    await openSession(tenant.token, tenant.companyId, tenant.userId);

    // Partida de texto libre: el POS la vende hoy y debe seguir vendiéndola.
    const res = await withLegacyFlag(true, () =>
      expectStatus(
        postSale(tenant.token, {
          items: [
            {
              productName: "Servicio suelto",
              qty: 1,
              priceSoldUnit: 500,
              costUnitSnapshot: 100,
            },
          ],
          paymentMethod: "cash",
        }),
        201,
      ),
    );

    const saleId = (res.body.id ?? res.body.sale?.id) as string;
    const item = await prisma.saleItem.findFirstOrThrow({
      where: { saleId, sale: { companyId: tenant.companyId } },
    });
    // Sin producto no hay clasificación declarada y NO se adivina.
    expect(item.itemTypeSnapshot).toBeNull();

    // La preparación NO puede producir un comprobante con una clasificación
    // inventada. Estos endpoints informan el resultado en el CUERPO (`ok`), no
    // en el estado HTTP, así que se comprueba `ok`, no el código de estado.
    const prepared = await http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ saleId, documentType: "E31", paymentType: 1 });
    expect(prepared.status).toBeLessThan(500);
    expect(prepared.body.ok).toBe(false);
    expect(typeof prepared.body.code).toBe("string");

    // No quedó ningún documento ni evidencia a medias.
    const rows = await ecfRowCount(tenant.companyId);
    expect(rows.evidence).toBe(0);
    expect(rows.reservations).toBe(0);
  });

  it("la ruta nueva no depende del interruptor legacy", async () => {
    const tenant = await registerTenant("nuevo-flag");
    const sessionId = await openSession(
      tenant.token,
      tenant.companyId,
      tenant.userId,
    );

    // El interruptor existe para el cliente ANTIGUO. Un cliente nuevo envía el
    // turno explícito y debe venderse igual con el interruptor en ambos valores.
    for (const flag of [true, false]) {
      const res = await withLegacyFlag(flag, () =>
        postSale(tenant.token, {
          items: [
            {
              productName: "Servicio nuevo",
              qty: 1,
              priceSoldUnit: 100,
              costUnitSnapshot: 10,
            },
          ],
          paymentMethod: "cash",
          originCashSessionId: sessionId,
        }),
      );
      expect(res.status).toBe(201);
    }

    const sales = await prisma.sale.findMany({
      where: { companyId: tenant.companyId },
    });
    expect(sales).toHaveLength(2);
    // Ambas quedaron en el turno real, no en otro.
    for (const sale of sales) expect(sale.cashSessionId).toBe(sessionId);
  });

  it("el reintento del cliente antiguo no duplica la venta", async () => {
    const tenant = await registerTenant("antiguo-retry");
    const sessionId = await openSession(
      tenant.token,
      tenant.companyId,
      tenant.userId,
    );
    const body = {
      ...legacySaleBody,
      clientRequestId: `legacy-retry-${randomUUID()}`,
    };

    const first = await withLegacyFlag(true, () =>
      postSale(tenant.token, body),
    );
    expect(first.status).toBe(201);
    const firstId = (first.body.id ?? first.body.sale?.id) as string;
    expect(firstId).toBeTruthy();

    // Replay del mismo cliente (fallo de red, reintento offline): devuelve la
    // venta existente en vez de crear otra.
    const second = await withLegacyFlag(true, () =>
      postSale(tenant.token, body),
    );
    expect([200, 201]).toContain(second.status);
    const secondId = (second.body.id ?? second.body.sale?.id) as string;
    expect(secondId).toBe(firstId);

    const sales = await prisma.sale.findMany({
      where: { companyId: tenant.companyId },
    });
    expect(sales).toHaveLength(1);
    // El replay no reasigna la venta a otro turno.
    expect(sales[0].cashSessionId).toBe(sessionId);
  });

  it("el reintento del cliente nuevo no duplica la venta", async () => {
    const tenant = await registerTenant("nuevo-retry");
    const sessionId = await openSession(
      tenant.token,
      tenant.companyId,
      tenant.userId,
    );
    const body = {
      items: [
        {
          productName: "Servicio idempotente",
          qty: 1,
          priceSoldUnit: 100,
          costUnitSnapshot: 10,
        },
      ],
      paymentMethod: "cash",
      originCashSessionId: sessionId,
      clientRequestId: `new-retry-${randomUUID()}`,
    };

    const first = await postSale(tenant.token, body);
    expect(first.status).toBe(201);
    const firstId = (first.body.id ?? first.body.sale?.id) as string;
    expect(firstId).toBeTruthy();

    const second = await postSale(tenant.token, body);
    expect([200, 201]).toContain(second.status);
    const secondId = (second.body.id ?? second.body.sale?.id) as string;
    expect(secondId).toBe(firstId);

    expect(
      await prisma.sale.count({ where: { companyId: tenant.companyId } }),
    ).toBe(1);
  });

  it("con el turno cerrado ninguna de las dos rutas crea la venta", async () => {
    const tenant = await registerTenant("turno-cerrado");
    const sessionId = await openSession(
      tenant.token,
      tenant.companyId,
      tenant.userId,
    );

    const closed = await http()
      .post("/cash/sessions/close")
      .set("Authorization", `Bearer ${tenant.token}`)
      .send({ sessionId, closingAmount: 0 });
    expect([200, 201]).toContain(closed.status);

    // Ruta antigua: sin turno abierto no hay venta, ni con el interruptor activo.
    const legacy = await withLegacyFlag(true, () =>
      postSale(tenant.token, legacySaleBody),
    );
    expect(legacy.status).toBeGreaterThanOrEqual(400);
    expect(legacy.status).toBeLessThan(500);

    // Ruta nueva: apunta a un turno que ya no está abierto.
    const modern = await postSale(tenant.token, {
      items: [
        {
          productName: "Servicio tras cierre",
          qty: 1,
          priceSoldUnit: 100,
          costUnitSnapshot: 10,
        },
      ],
      paymentMethod: "cash",
      originCashSessionId: sessionId,
    });
    expect(modern.status).toBeGreaterThanOrEqual(400);
    expect(modern.status).toBeLessThan(500);

    // Rechazo controlado, sin venta a medias.
    expect(
      await prisma.sale.count({ where: { companyId: tenant.companyId } }),
    ).toBe(0);
  });
});
