import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../../../app.module";
import { PrismaService } from "../../../prisma/prisma.service";
import type { TenantUser } from "../../../auth/tenant-context";
import type { EcfIssuanceMetadata } from "../../fiscal-core/alanube-dom.contract";
import { mapEcfToDosaDraft } from "./dosa-ecf.mapper";
import { assessDosaDocumentBarrier } from "./dosa-emission.barrier";
import { EcfSaleFiscalAdapter } from "../../pos/ecf-sale-fiscal.adapter";
import { mapSaleSnapshotToEcfDocument } from "../../pos/ecf-sale-adapter";

/**
 * Recorrido REAL: venta del POS → documento fiscal → JSON de DOSA → barrera.
 *
 * Lo que demuestra, y por qué importa:
 *
 * 1. La venta se crea con los **endpoints reales** del POS (`POST /sales`), no
 *    insertando filas: se ejercitan stock, snapshots, turno de caja, impuestos y
 *    numeración.
 * 2. El documento fiscal se construye con el **adaptador real**
 *    (`EcfSaleFiscalAdapter`), que lee de PostgreSQL lo persistido.
 * 3. La unidad de medida llega al JSON desde el **snapshot histórico de la
 *    partida** (`SaleItem.unitCodeSnapshot`), traducida al catálogo del
 *    proveedor. No hay `unidadMedida = 1` por defecto.
 * 4. El JSON se valida con la **barrera del punto de envío**.
 * 5. **No se envía nada**: este arnés no importa el cliente HTTP de emisión, así
 *    que no existe camino a un socket fiscal.
 *
 * Base de datos DESECHABLE creada para esta ejecución y destruida al terminar.
 * Sin proveedor, sin emisión y sin claves reales.
 */
jest.setTimeout(300000);

const PASSWORD = "DosaSaleJson123!";
const SAFE_DB = /^fullpos_dosa_sale_json_e2e_/;
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

uat("Venta real del POS → JSON de DOSA (sin transmitir)", () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let adapter: EcfSaleFiscalAdapter;
  let dbName: string;
  let adminUrl: string;
  let unitUnitId: string;
  let yardId: string;
  let customUnitId: string;

  const http = () => request(app.getHttpServer());

  const metadataFor = (encf: string): EcfIssuanceMetadata => ({
    encf,
    paymentType: 1,
    sequenceDueDate: "2027-12-31",
    incomeType: 1,
  });

  beforeAll(async () => {
    if (process.env.ALANUBE_ENABLE_REAL_CALLS !== "false") {
      throw new Error("E2E_REFUSES_REAL_PROVIDER_CALLS");
    }
    const baseUrl = baseDatabaseUrl();
    dbName = `fullpos_dosa_sale_json_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    const appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "dosa-sale-json-e2e";
    // La CLI de Prisma puede estar hoisteada en la raíz del monorepo o en el
    // paquete. Asumir solo `apps/api/node_modules` rompía esta prueba en
    // cualquier instalación con npm workspaces (`npm ci` en la raíz), que es la
    // que usa CI. Mismo patrón que el resto de las pruebas de integración.
    const prismaCandidates = [
      resolve(process.cwd(), "node_modules", "prisma", "build", "index.js"),
      resolve(
        process.cwd(),
        "..",
        "..",
        "node_modules",
        "prisma",
        "build",
        "index.js",
      ),
    ];
    const prismaCli = prismaCandidates.find((candidate) => existsSync(candidate));
    if (!prismaCli) throw new Error("PRISMA_CLI_NOT_FOUND");
    execFileSync(process.execPath, [prismaCli, "migrate", "deploy"], {
      cwd: process.cwd(),
      env: { ...process.env, DATABASE_URL: appUrl },
      stdio: "pipe",
    });

    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    prisma = app.get(PrismaService);
    adapter = new EcfSaleFiscalAdapter(prisma);

    const unit = async (
      code: string,
      name: string,
      symbol: string,
      category: "COUNT" | "LENGTH" = "COUNT",
      allowDecimals = false,
    ) => {
      const row = await prisma.unitOfMeasure.upsert({
        where: { id: code },
        update: {},
        create: {
          id: code,
          code,
          name,
          symbol,
          category,
          allowDecimals,
          precision: allowDecimals ? 3 : 0,
        },
      });
      return row.id;
    };
    unitUnitId = await unit("UNIT", "Unidad", "u");
    yardId = await unit("YARD", "Yarda", "yd", "LENGTH", true);
    // Unidad propia de la empresa, sin equivalencia documentada con DOSA.
    customUnitId = await unit("CAJA_PROPIA", "Caja propia", "cj", "COUNT", true);
  }, 300000);

  afterAll(async () => {
    if (app) await app.close();
    if (adminUrl && dbName && SAFE_DB.test(dbName)) {
      const admin = new Client({ connectionString: adminUrl });
      await admin.connect();
      await admin.query(
        "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()",
        [dbName],
      );
      await admin.query(`DROP DATABASE IF EXISTS ${dbName}`);
      await admin.end();
    }
  }, 120000);

  async function registerTenant(suffix: string) {
    const email = `dosa-json-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Dosa",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `Dosa JSON ${suffix}`,
        taxId: `1${Date.now().toString().slice(-8)}`,
        businessPhone: "8095551111",
        address: `Av. Sintética ${suffix}`,
        country: "DO",
      });
    if (res.status !== 201) {
      throw new Error(`POST /auth/register-business -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return {
      token: res.body.accessToken as string,
      userId: res.body.user.id as string,
      companyId: res.body.activeCompany.id as string,
    };
  }

  /** Habilita las unidades de medida de la empresa (requisito del POS). */
  async function setupUnits(token: string) {
    const settings = await http()
      .patch("/settings")
      .set("Authorization", `Bearer ${token}`)
      .send({ measurementUnitsEnabled: true });
    expect(settings.status).toBe(200);
  }

  /**
   * Configuración fiscal REAL de la empresa: unidades de medida, impuesto,
   * ajustes fiscales y una secuencia B01. Sin esto el POS rechaza una venta con
   * comprobante fiscal, igual que en producción.
   */
  async function setupFiscal(token: string) {
    await setupUnits(token);

    const tax = await http()
      .post("/taxes")
      .set("Authorization", `Bearer ${token}`)
      .send({ name: "ITBIS 18", rate: 0.18, isActive: true, isDefault: true });
    expect(tax.status).toBe(201);

    const fiscal = await http()
      .patch("/company/fiscal-settings")
      .set("Authorization", `Bearer ${token}`)
      .send({
        taxEnabled: true,
        defaultTaxId: tax.body.id,
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
      });
    expect(fiscal.status).toBe(200);
  }

  async function openSession(token: string, companyId: string, userId: string) {
    const opened = await http()
      .post("/cash/sessions/open")
      .set("Authorization", `Bearer ${token}`)
      .send({ openingAmount: 0 });
    expect(opened.status).toBe(201);
    const session = await prisma.cashSession.findFirstOrThrow({
      where: { companyId, openedByUserId: userId, status: "OPEN" },
      orderBy: { openedAt: "desc" },
    });
    return session.id;
  }

  async function createProduct(
    token: string,
    body: {
      nombre: string;
      precio: number;
      stock: number;
      unitOfMeasureId: string;
      itemType?: "PRODUCT" | "SERVICE";
    },
  ) {
    const res = await http()
      .post("/products")
      .set("Authorization", `Bearer ${token}`)
      .send({
        nombre: body.nombre,
        codigo: `SKU-${Date.now()}-${Math.floor(Math.random() * 1000)}`,
        categoria: "Fiscal",
        precio: body.precio,
        costo: body.precio / 2,
        stock: body.stock,
        unitOfMeasureId: body.unitOfMeasureId,
        ...(body.itemType ? { itemType: body.itemType } : {}),
        ...(body.itemType === "SERVICE" ? { trackInventory: false } : {}),
      });
    if (res.status !== 201) {
      throw new Error(`POST /products -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return res.body as { id: string; nombre: string; unitOfMeasure?: { code: string } };
  }

  /** Cliente con identificación fiscal: el comprobante B01 lo exige. */
  async function createClient(token: string) {
    const res = await http()
      .post("/clients")
      .set("Authorization", `Bearer ${token}`)
      .send({
        nombre: "Cliente Fiscal SA",
        telefono: "8090000000",
        taxId: "130000000",
        businessName: "Cliente Fiscal SA",
        direccion: "Av. Fiscal 1",
      });
    if (res.status !== 201) {
      throw new Error(`POST /clients -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return res.body as { id: string };
  }

  async function createSale(token: string, body: Record<string, unknown>) {
    const res = await http()
      .post("/sales")
      .set("Authorization", `Bearer ${token}`)
      .send(body);
    if (res.status !== 201) {
      // Falla con el motivo REAL del POS en vez de un "expected 201" mudo.
      throw new Error(`POST /sales -> ${res.status}: ${JSON.stringify(res.body)}`);
    }
    return res.body as { id: string; totalSold: string };
  }

  /**
   * Recorre venta → documento fiscal → JSON de DOSA y lo valida con la barrera.
   * Es exactamente la cadena que usará la emisión, sin el paso de red.
   */
  async function buildDosaJson(input: {
    companyId: string;
    userId: string;
    saleId: string;
    documentType: "E31" | "E32";
    encf: string;
  }) {
    const user = { id: input.userId, role: "ADMIN", companyId: input.companyId } as TenantUser;
    const built = await adapter.build(user, {
      saleId: input.saleId,
      documentType: input.documentType,
    });
    if (!built.ok) return { stage: "ADAPTER" as const, built };

    const document = mapSaleSnapshotToEcfDocument(built.value.snapshot);
    const mapped = mapEcfToDosaDraft(document, metadataFor(input.encf));
    if (!mapped.ok) return { stage: "MAPPER" as const, mapped, built };

    const barrier = assessDosaDocumentBarrier(mapped.draft.body, {
      documentType: input.documentType,
      companyRnc: built.value.snapshot.seller.taxId,
    });
    return { stage: "BARRIER" as const, barrier, draft: mapped.draft, built, document };
  }

  it("E31: venta con un bien por unidad llega a JSON de DOSA válido", async () => {
    const tenant = await registerTenant("e31");
    await setupFiscal(tenant.token);
    const sessionId = await openSession(tenant.token, tenant.companyId, tenant.userId);
    const product = await createProduct(tenant.token, {
      nombre: "Artículo E31",
      precio: 118,
      stock: 10,
      unitOfMeasureId: unitUnitId,
    });
    const client = await createClient(tenant.token);
    const sale = await createSale(tenant.token, {
      originCashSessionId: sessionId,
      paymentMethod: "cash",
      paymentCashAmount: 118,
      customerId: client.id,
      expectedTotalSold: 118,
      items: [
        {
          productId: product.id,
          productSource: "LOCAL",
          productName: product.nombre,
          qty: 1,
          priceSoldUnit: 118,
        },
      ],
    });

    const result = await buildDosaJson({
      companyId: tenant.companyId,
      userId: tenant.userId,
      saleId: sale.id,
      documentType: "E31",
      encf: "E310000000901",
    });

    expect(result.stage).toBe("BARRIER");
    if (result.stage !== "BARRIER") throw new Error(`bloqueado en ${result.stage}`);
    expect(result.barrier.blockingReasons).toEqual([]);

    const body = result.draft.body;
    expect(body.encabezado.idDoc.tipoeCF).toBe("31");
    expect(body.encabezado.idDoc.eNCF).toBe("E310000000901");
    expect(body.encabezado.emisor.RNCEmisor).toBe(result.built.value.snapshot.seller.taxId);
    expect(body.encabezado.comprador?.RNCComprador).toBe("130000000");
    // Unidad traducida al catálogo REAL de la DGII: 43 = Unidad.
    // (La tabla 1=Unidad, 2=Caja… era incorrecta y se corrigió en noviembre de
    // 2026; ver `DOSA_UNIDAD_MEDIDA_BY_FULLPOS_CODE` y
    // `dosa-ecf.fiscal-catalogues.spec.ts`, que fija esos códigos.)
    expect(body.detallesItems[0].unidadMedida).toBe(43);
    expect(body.detallesItems[0].indicadorFacturacion).toBe(1);
    // 1 = bien, 2 = servicio.
    expect(body.detallesItems[0].indicadorBienoServicio).toBe(1);
    // Los totales del comprobante son los de la venta, no un recálculo.
    expect(body.encabezado.totales.MontoGravadoTotal).toBe("100.00");
    expect(body.encabezado.totales.TotalITBIS).toBe("18.00");
    expect(body.encabezado.totales.MontoTotal).toBe(Number(sale.totalSold).toFixed(2));
  });

  it("E32: venta de consumidor final por yardas conserva cantidad y unidad", async () => {
    const tenant = await registerTenant("e32");
    // E32 no exige numeración ni datos fiscales del comprador: solo unidades.
    await setupUnits(tenant.token);
    const sessionId = await openSession(tenant.token, tenant.companyId, tenant.userId);
    const product = await createProduct(tenant.token, {
      nombre: "Tela por yarda",
      precio: 200,
      stock: 20,
      unitOfMeasureId: yardId,
    });
    // La unidad elegida por el POS debe ser la del producto, no la de defecto.
    expect(product.unitOfMeasure?.code).toBe("YARD");

    const sale = await createSale(tenant.token, {
      originCashSessionId: sessionId,
      paymentMethod: "cash",
      paymentCashAmount: 1100,
      expectedTotalSold: 1100,
      items: [
        {
          productId: product.id,
          productSource: "LOCAL",
          productName: product.nombre,
          qty: 5.5,
          priceSoldUnit: 200,
        },
      ],
    });

    const result = await buildDosaJson({
      companyId: tenant.companyId,
      userId: tenant.userId,
      saleId: sale.id,
      documentType: "E32",
      encf: "E320000000901",
    });

    expect(result.stage).toBe("BARRIER");
    if (result.stage !== "BARRIER") throw new Error(`bloqueado en ${result.stage}`);
    expect(result.barrier.blockingReasons).toEqual([]);

    const item = result.draft.body.detallesItems[0];
    expect(result.draft.body.encabezado.idDoc.tipoeCF).toBe("32");
    expect(item.unidadMedida).toBe(41); // 41 = Yarda en el catálogo de la DGII
    expect(item.cantidadItem).toBe("5.5"); // la cantidad no se reconvierte
    expect(item.precioUnitarioItem).toBe("200.00");
    expect(item.montoItem).toBe("1100.00");
    // E32 sin comprador identificado.
    expect(result.draft.body.encabezado.comprador?.RNCComprador).toBeUndefined();
  });

  it("venta mixta (bien + servicio) declara la naturaleza de cada línea", async () => {
    const tenant = await registerTenant("mixta");
    await setupFiscal(tenant.token);
    const sessionId = await openSession(tenant.token, tenant.companyId, tenant.userId);
    const good = await createProduct(tenant.token, {
      nombre: "Bien mixto",
      precio: 118,
      stock: 5,
      unitOfMeasureId: unitUnitId,
    });
    const service = await createProduct(tenant.token, {
      nombre: "Servicio de instalación",
      precio: 118,
      stock: 0,
      unitOfMeasureId: unitUnitId,
      itemType: "SERVICE",
    });
    const client = await createClient(tenant.token);
    const sale = await createSale(tenant.token, {
      originCashSessionId: sessionId,
      paymentMethod: "cash",
      paymentCashAmount: 236,
      customerId: client.id,
      expectedTotalSold: 236,
      items: [
        {
          productId: good.id,
          productSource: "LOCAL",
          productName: good.nombre,
          qty: 1,
          priceSoldUnit: 118,
        },
        {
          productId: service.id,
          productSource: "LOCAL",
          productName: service.nombre,
          qty: 1,
          priceSoldUnit: 118,
        },
      ],
    });

    const items = await prisma.saleItem.findMany({
      where: { saleId: sale.id },
      orderBy: { createdAt: "asc" },
    });
    expect(items).toHaveLength(2);
    // Naturaleza y unidad congeladas en la venta.
    expect(items.map((item) => item.itemTypeSnapshot)).toEqual(["PRODUCT", "SERVICE"]);
    expect(items.map((item) => item.unitCodeSnapshot)).toEqual(["UNIT", "UNIT"]);

    const result = await buildDosaJson({
      companyId: tenant.companyId,
      userId: tenant.userId,
      saleId: sale.id,
      documentType: "E31",
      encf: "E310000000902",
    });

    expect(result.stage).toBe("BARRIER");
    if (result.stage !== "BARRIER") throw new Error(`bloqueado en ${result.stage}`);
    expect(result.barrier.blockingReasons).toEqual([]);
    expect(
      result.draft.body.detallesItems.map((item) => ({
        facturacion: item.indicadorFacturacion,
        bienoServicio: item.indicadorBienoServicio,
        unidad: item.unidadMedida,
      })),
    ).toEqual([
      // 1 = bien, 2 = servicio. `indicadorFacturacion` NO es la naturaleza: es
      // la tasa de ITBIS aplicada (1 = ITBIS1, 18%), y ambas líneas van al 18 %.
      // La versión anterior de esta prueba había invertido ambos indicadores y
      // usaba el catálogo viejo de unidades (1 = Unidad); se alineó con el
      // catálogo oficial que fija `dosa-ecf.fiscal-catalogues.spec.ts`.
      { facturacion: 1, bienoServicio: 1, unidad: 43 }, // bien
      { facturacion: 1, bienoServicio: 2, unidad: 43 }, // servicio
    ]);
  });

  it("unidad sin equivalencia documentada: se bloquea y NUNCA llega a la barrera", async () => {
    const tenant = await registerTenant("unidad-rara");
    await setupFiscal(tenant.token);
    const sessionId = await openSession(tenant.token, tenant.companyId, tenant.userId);
    const product = await createProduct(tenant.token, {
      nombre: "Caja propia",
      precio: 118,
      stock: 5,
      unitOfMeasureId: customUnitId,
    });
    const client = await createClient(tenant.token);
    const sale = await createSale(tenant.token, {
      originCashSessionId: sessionId,
      paymentMethod: "cash",
      paymentCashAmount: 118,
      customerId: client.id,
      expectedTotalSold: 118,
      items: [
        {
          productId: product.id,
          productSource: "LOCAL",
          productName: product.nombre,
          qty: 1,
          priceSoldUnit: 118,
        },
      ],
    });

    const result = await buildDosaJson({
      companyId: tenant.companyId,
      userId: tenant.userId,
      saleId: sale.id,
      documentType: "E31",
      encf: "E310000000903",
    });

    // Se detiene en el MAPEADOR: no hay borrador, así que no hay nada que la
    // barrera pueda dejar pasar ni que el cliente HTTP pueda enviar.
    expect(result.stage).toBe("MAPPER");
    if (result.stage !== "MAPPER") throw new Error(`llegó a ${result.stage}`);
    expect(result.mapped.ok).toBe(false);
    if (result.mapped.ok) return;
    expect(result.mapped.blockedReason).toBe("DOSA_UNIT_OF_MEASURE_UNMAPPED:1:CAJA_PROPIA");
  });

  it("una venta cancelada no produce documento fiscal", async () => {
    const tenant = await registerTenant("cancelada");
    await setupUnits(tenant.token);
    const sessionId = await openSession(tenant.token, tenant.companyId, tenant.userId);
    const product = await createProduct(tenant.token, {
      nombre: "Cancelable",
      precio: 118,
      stock: 5,
      unitOfMeasureId: unitUnitId,
    });
    const sale = await createSale(tenant.token, {
      originCashSessionId: sessionId,
      paymentMethod: "cash",
      paymentCashAmount: 118,
      expectedTotalSold: 118,
      items: [
        {
          productId: product.id,
          productSource: "LOCAL",
          productName: product.nombre,
          qty: 1,
          priceSoldUnit: 118,
        },
      ],
    });
    const removed = await http()
      .delete(`/sales/${sale.id}`)
      .set("Authorization", `Bearer ${tenant.token}`);
    expect(removed.status).toBe(200);

    const result = await buildDosaJson({
      companyId: tenant.companyId,
      userId: tenant.userId,
      saleId: sale.id,
      documentType: "E31",
      encf: "E310000000904",
    });

    expect(result.stage).toBe("ADAPTER");
    if (result.stage !== "ADAPTER") throw new Error(`llegó a ${result.stage}`);
    expect(result.built.ok).toBe(false);
    if (result.built.ok) return;
    // `DELETE /sales` es una cancelación segura: la venta queda marcada como
    // eliminada y con el inventario repuesto, y el adaptador la rechaza.
    expect(result.built.code).toBe("ECF_SALE_DELETED");
  });

  it("la nota de crédito no se prepara desde una venta, y nunca sin código", async () => {
    const tenant = await registerTenant("e34");
    await setupFiscal(tenant.token);
    const sessionId = await openSession(tenant.token, tenant.companyId, tenant.userId);
    const product = await createProduct(tenant.token, {
      nombre: "Nota E34",
      precio: 118,
      stock: 5,
      unitOfMeasureId: unitUnitId,
    });
    const client = await createClient(tenant.token);
    const sale = await createSale(tenant.token, {
      originCashSessionId: sessionId,
      paymentMethod: "cash",
      paymentCashAmount: 118,
      customerId: client.id,
      expectedTotalSold: 118,
      items: [
        {
          productId: product.id,
          productSource: "LOCAL",
          productName: product.nombre,
          qty: 1,
          priceSoldUnit: 118,
        },
      ],
    });

    // El adaptador de venta solo prepara E31/E32: una nota de crédito tiene su
    // propio flujo (referencia al comprobante original).
    const user = { id: tenant.userId, role: "ADMIN", companyId: tenant.companyId } as TenantUser;
    const built = await adapter.build(user, {
      saleId: sale.id,
      // @ts-expect-error E34 no está soportado por el adaptador de venta: se
      // comprueba justamente que lo rechaza en vez de improvisar.
      documentType: "E34",
    });
    expect(built.ok).toBe(false);
    if (built.ok) return;
    expect(built.code).toBe("ECF_DOCUMENT_TYPE_UNSUPPORTED");
  });
});
