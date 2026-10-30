import { INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Client } from "pg";
import request from "supertest";
import { AppModule } from "../app.module";
import { PrismaService } from "../prisma/prisma.service";

/**
 * E2E VERTICAL de e-CF: HTTP real → guardas de auth → servicio → PostgreSQL.
 *
 * Se levanta la aplicación completa contra una base DESECHABLE creada para esta
 * ejecución y se la conduce con `supertest`, es decir por HTTP de verdad: login
 * real, JWT real, `AuthGuard`/`RolesGuard` reales, validación de DTO real.
 *
 * Alcance declarado (no es un E2E de interfaz gráfica):
 *  - La empresa y el administrador se crean por HTTP (`/auth/register-business`).
 *  - Toda la superficie e-CF se ejercita por HTTP.
 *  - La VENTA se siembra por Prisma: es una PRECONDICIÓN del módulo (no código
 *    e-CF) y el flujo POS completo no forma parte de esta superficie.
 *  - El comprobante original ACEPTADO de E34 también se siembra: por diseño no
 *    existe endpoint que emita, así que no puede producirse por HTTP.
 *  - No hay proveedor, no hay emisión y no se declara ninguna aceptación real:
 *    las evidencias sembradas son sintéticas y lo dicen en su `reasonCode`.
 */
jest.setTimeout(240000);

const PASSWORD = "EcfHttpE2E123!";
const SAFE_DB = /^fullpos_http_e2e_/;
// Opt-in: solo corre en la base efímera de pruebas.
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

uat("e-CF E2E HTTP + PostgreSQL desechable", () => {
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
    dbName = `fullpos_http_e2e_${Date.now()}`;
    adminUrl = replaceDbName(baseUrl, "postgres");
    appUrl = replaceDbName(baseUrl, dbName);
    if (!SAFE_DB.test(dbName)) throw new Error("Unsafe E2E DB name");

    const admin = new Client({ connectionString: adminUrl });
    await admin.connect();
    await admin.query(`CREATE DATABASE ${dbName}`);
    await admin.end();

    process.env.DATABASE_URL = appUrl;
    process.env.JWT_SECRET = process.env.JWT_SECRET || "ecf-http-e2e-secret";
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

    unitId = `UNIT_${randomUUID().slice(0, 8)}`;
    await prisma.unitOfMeasure.create({
      data: { id: unitId, code: unitId, name: "Unidad", symbol: "u", category: "COUNT" },
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

  /** Empresa + administrador reales, creados por HTTP. */
  async function registerTenant(suffix: string) {
    const email = `ecf-e2e-${Date.now()}-${suffix}@example.test`;
    const res = await http()
      .post("/auth/register-business")
      .send({
        firstName: "Ecf",
        lastName: suffix,
        email,
        phone: "8095550000",
        password: PASSWORD,
        confirmPassword: PASSWORD,
        commercialName: `e-CF ${suffix}`,
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

  /** Login real por HTTP: prueba que el backend nuevo autentica igual que antes. */
  async function login(email: string) {
    const res = await http()
      .post("/auth/login")
      .send({ email, password: PASSWORD })
      .expect(201);
    return res.body.accessToken as string;
  }

  async function enableEcf(token: string) {
    await http()
      .patch("/ecf/config")
      .set("Authorization", `Bearer ${token}`)
      .send({ enabled: true })
      .expect(200);
  }

  async function registerSequence(
    token: string,
    documentType: "E31" | "E34",
  ) {
    await http()
      .post("/ecf/sequences")
      .set("Authorization", `Bearer ${token}`)
      .send({ documentType, startNumber: 1, endNumber: 20 })
      .expect(201);
  }

  /**
   * Venta sintética: 3 × 59.00 con ITBIS 18% incluido (base 150.00, impuesto
   * 27.00, total 177.00). Es precondición del módulo, no superficie e-CF.
   */
  async function seedSale(companyId: string, userId: string) {
    const sale = await prisma.sale.create({
      data: {
        companyId,
        userId,
        totalSold: "177.00",
        totalCost: "3.00",
        totalProfit: "0.00",
        commissionAmount: "0.00",
        taxableBase: "150.00",
        exemptAmount: "0.00",
        discountAmount: "0.00",
        taxAmount: "27.00",
        fiscalTaxEnabled: true,
        issuerNameSnapshot: "Emisor Sintético SRL",
        issuerTaxIdSnapshot: "101000001",
        issuerAddressSnapshot: "Av. Principal 1, Santo Domingo",
        fiscalCustomerTaxId: "130000000",
        fiscalCustomerName: "Cliente SA",
      },
    });
    const product = await prisma.product.create({
      data: {
        companyId,
        nombre: "Producto gravado",
        codigo: `SKU-${randomUUID().slice(0, 8)}`,
        categoria: "General",
        costo: "1.00",
        precio: "59.00",
        unitOfMeasureId: unitId,
        itemType: "PRODUCT",
      },
    });
    await prisma.saleItem.create({
      data: {
        saleId: sale.id,
        productId: product.id,
        productNameSnapshot: "Producto gravado",
        qty: "3",
        priceSoldUnit: "59.00",
        grossAmount: "177.00",
        lineDiscountAmount: "0.00",
        taxableBase: "150.00",
        taxRate: "0.1800",
        taxAmount: "27.00",
        exemptAmount: "0.00",
        costUnitSnapshot: "1.00",
        subtotalSold: "150.00",
        subtotalCost: "3.00",
        profit: "0.00",
        itemTypeSnapshot: "PRODUCT",
      },
    });
    return sale;
  }

  /**
   * Original ACEPTADO sintético para E34. La evidencia dice explícitamente que
   * es sintética: no es una aceptación real de la DGII.
   */
  async function seedAcceptedOriginal(
    companyId: string,
    saleId: string,
    total: string,
  ) {
    // El contrato exige exactamente `E31` + 10 dígitos.
    const encf = `E31${String(
      Math.floor(1000000000 + Math.random() * 8999999999),
    )}`;
    const evidenceRef = `uat://synthetic-not-dgii/${randomUUID()}`;
    const evidenceHash = "a".repeat(64);
    const doc = await prisma.ecfElectronicDocument.create({
      data: {
        companyId,
        documentType: "E31",
        status: "DGII_ACCEPTED",
        sourceType: "SALE",
        sourceId: saleId,
        externalDocumentNumber: encf,
        externalProviderId: `synthetic-${randomUUID()}`,
        idempotencyKey: `synthetic-original-${randomUUID()}`,
        payloadFingerprint: "b".repeat(64),
        payloadSummary: { type: "E31", total, currency: "DOP", issueDate: "2026-10-14" },
        fiscalSnapshot: {
          total,
          currency: "DOP",
          issueDate: "2026-10-14",
          issuerRnc: "101000001",
          encf,
          evidenceRef,
          evidenceHash,
        },
      },
    });
    await prisma.ecfElectronicDocumentStatusLog.create({
      data: {
        companyId,
        documentId: doc.id,
        statusAfter: "DGII_ACCEPTED",
        reasonCode: "SYNTHETIC_TEST_ONLY_NOT_DGII",
        metadata: { evidenceRef, evidenceHash },
      },
    });
    return { id: doc.id, encf };
  }

  // ---------------------------------------------------------------------------
  // E31 — preparación desde una venta real
  // ---------------------------------------------------------------------------
  it("E31: login real, prepara por HTTP, aparece en la bandeja y no se duplica", async () => {
    const tenant = await registerTenant("e31");
    const token = await login(tenant.email);
    await enableEcf(token);
    await registerSequence(token, "E31");

    const caps = await http()
      .get("/ecf/capabilities")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(caps.body.enabled).toBe(true);
    // La emisión NO es alcanzable desde HTTP: es una invariante de diseño.
    expect(caps.body.emissionPathAvailable).toBe(false);

    const sale = await seedSale(tenant.companyId, tenant.userId);

    const prepared = await http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${token}`)
      .send({
        saleId: sale.id,
        documentType: "E31",
        paymentType: 1,
        incomeType: 1,
        sequenceDueDate: "2026-12-31",
      })
      .expect(201);
    expect(prepared.body.ok).toBe(true);
    expect(prepared.body.value.encf).toBe("E310000000001");
    expect(prepared.body.value.status).toBe("LOCAL_VALIDATED");
    expect(prepared.body.value.documentId).toBeTruthy();

    // Bandeja por HTTP.
    const tray = await http()
      .get("/ecf/documents")
      .query({ documentType: "E31" })
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(tray.body.total).toBe(1);
    expect(tray.body.items[0].encf).toBe("E310000000001");
    expect(tray.body.items[0].total).toBe("177.00");
    expect(tray.body.items[0].currency).toBe("DOP");
    expect(tray.body.items[0].statusGroup).toBe("PENDING");
    // El receptor congelado viaja en la proyección, y el payload del proveedor no.
    expect(tray.body.items[0].receiverTaxId).toBe("130000000");
    expect(tray.body.items[0].payloadSummary).toBeUndefined();

    // Detalle con trazabilidad.
    const detail = await http()
      .get(`/ecf/documents/${prepared.body.value.documentId}`)
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(detail.body.statusLogs.length).toBeGreaterThan(0);
    expect(detail.body).not.toHaveProperty("fiscalDocument");

    // Reintento de la MISMA operación: mismo documento y mismo número.
    const retry = await http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${token}`)
      .send({
        saleId: sale.id,
        documentType: "E31",
        paymentType: 1,
        incomeType: 1,
        sequenceDueDate: "2026-12-31",
      })
      .expect(201);
    expect(retry.body.ok).toBe(true);
    expect(retry.body.value.documentId).toBe(prepared.body.value.documentId);
    expect(retry.body.value.encf).toBe("E310000000001");

    // Verificación directa en PostgreSQL.
    const stored = await prisma.ecfElectronicDocument.findMany({
      where: { companyId: tenant.companyId },
    });
    expect(stored).toHaveLength(1);
    // El número reservado al preparar vive en el resumen de emisión: el despacho
    // es quien fija `external_document_number`. Un borrador local no tiene
    // todavía número externo, y por eso la bandeja usa el reservado.
    expect(stored[0].externalDocumentNumber).toBeNull();
    expect(
      (stored[0].payloadSummary as { emission?: { encf?: string } }).emission
        ?.encf,
    ).toBe("E310000000001");
    const sequence = await prisma.ecfSequence.findFirstOrThrow({
      where: { companyId: tenant.companyId, documentType: "E31" },
    });
    // Un reintento no consume un segundo número.
    expect(sequence.nextNumber).toBe(2);
  });

  // ---------------------------------------------------------------------------
  // E32 — consumo: sin numeración y sin cupo de sandbox
  // ---------------------------------------------------------------------------
  it("E32: prepara consumo sin numeración, sin cupo y sin duplicar", async () => {
    const tenant = await registerTenant("e32");
    const token = await login(tenant.email);
    await enableEcf(token);
    await registerSequence(token, "E31");

    const sale = await seedSale(tenant.companyId, tenant.userId);
    const sequencesBefore = await prisma.ecfSequence.findMany({
      where: { companyId: tenant.companyId },
      select: { documentType: true, nextNumber: true },
    });

    const prepared = await http()
      .post("/ecf/documents/prepare-consumo")
      .set("Authorization", `Bearer ${token}`)
      .send({ saleId: sale.id, documentType: "E32", paymentType: 1, incomeType: 1 })
      .expect(201);
    expect(prepared.body.ok).toBe(true);
    expect(prepared.body.value.documentType).toBe("E32");
    expect(prepared.body.value.encf).toBeNull();
    expect(prepared.body.value.numberingState).toBe("PENDING_SANDBOX_SLOT");
    expect(prepared.body.value.status).toBe("LOCAL_VALIDATED");

    // Ni rango de empresa ni cupo de sandbox.
    const sequencesAfter = await prisma.ecfSequence.findMany({
      where: { companyId: tenant.companyId },
      select: { documentType: true, nextNumber: true },
    });
    expect(sequencesAfter).toEqual(sequencesBefore);
    expect(
      await prisma.ecfSandboxE32Trial.count({ where: { companyId: tenant.companyId } }),
    ).toBe(0);

    // Idempotencia por venta.
    const retry = await http()
      .post("/ecf/documents/prepare-consumo")
      .set("Authorization", `Bearer ${token}`)
      .send({ saleId: sale.id, documentType: "E32", paymentType: 1, incomeType: 1 })
      .expect(201);
    expect(retry.body.value.documentId).toBe(prepared.body.value.documentId);
    expect(
      await prisma.ecfElectronicDocument.count({ where: { companyId: tenant.companyId } }),
    ).toBe(1);

    // Consulta posterior por HTTP: sin e-NCF y sin presentarse como aceptado.
    const tray = await http()
      .get("/ecf/documents")
      .query({ documentType: "E32" })
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(tray.body.total).toBe(1);
    expect(tray.body.items[0].encf).toBeNull();
    expect(tray.body.items[0].status).toBe("LOCAL_VALIDATED");
  });

  // ---------------------------------------------------------------------------
  // E34 — nota de crédito: saldo, exceso y total
  // ---------------------------------------------------------------------------
  it("E34: nota parcial, exceso bloqueado, saldo restante y nota total", async () => {
    const tenant = await registerTenant("e34");
    const token = await login(tenant.email);
    await enableEcf(token);
    await registerSequence(token, "E31");
    await registerSequence(token, "E34");

    const sale = await seedSale(tenant.companyId, tenant.userId);
    const original = await seedAcceptedOriginal(tenant.companyId, sale.id, "177.00");

    // Saldo ofrecido por el servidor.
    const eligible = await http()
      .get("/ecf/documents/eligible-originals")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    const candidate = eligible.body.items.find(
      (item: { id: string }) => item.id === original.id,
    );
    expect(candidate).toBeTruthy();
    expect(candidate.availableAmount).toBe("177.00");

    // Nota PARCIAL: 1 de 3 unidades.
    const partial = await http()
      .post("/ecf/documents/prepare-credit-note")
      .set("Authorization", `Bearer ${token}`)
      .send({
        originalDocumentId: original.id,
        clientRequestId: randomUUID(),
        refundKind: "PARTIAL",
        lines: [{ lineNumber: 1, quantity: "1" }],
        modificationCode: 3,
        modificationReason: "Devolución parcial",
        paymentType: 1,
        creditNoteIndicator: 0,
      })
      .expect(201);
    expect(partial.body.ok).toBe(true);
    expect(partial.body.value.encf).toBe("E340000000001");
    expect(partial.body.value.originalEncf).toBe(original.encf);
    // El importe reservado se compara numéricamente: el contrato no garantiza
    // ceros finales en el decimal devuelto.
    expect(Number(partial.body.value.reservedAmount)).toBe(59);

    // El saldo baja tras la nota.
    const afterPartial = await http()
      .get("/ecf/documents/eligible-originals")
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    const remaining = afterPartial.body.items.find(
      (item: { id: string }) => item.id === original.id,
    );
    expect(remaining.availableAmount).toBe("118.00");

    // Exceso REAL de saldo: la línea completa (3 unidades = 177.00) ya no cabe
    // en los 118.00 disponibles. La guarda de saldo lanza un error de dominio
    // (HTTP 409), no un 201 con `ok:false`: aquí no es un fallo de elegibilidad
    // sino una operación que el servidor rechaza.
    const excess = await http()
      .post("/ecf/documents/prepare-credit-note")
      .set("Authorization", `Bearer ${token}`)
      .send({
        originalDocumentId: original.id,
        clientRequestId: randomUUID(),
        refundKind: "PARTIAL",
        lines: [{ lineNumber: 1, quantity: "3" }],
        modificationCode: 3,
        modificationReason: "Intento por encima del saldo",
        paymentType: 1,
        creditNoteIndicator: 0,
      })
      .expect(409);
    expect(JSON.stringify(excess.body)).toContain("E34_INSUFFICIENT_FISCAL_BALANCE");
    // Y no dejó nada reservado.
    expect(
      await prisma.ecfCreditReservation.count({ where: { companyId: tenant.companyId } }),
    ).toBe(1);

    // Segunda nota parcial: el saldo restante sigue disponible.
    const second = await http()
      .post("/ecf/documents/prepare-credit-note")
      .set("Authorization", `Bearer ${token}`)
      .send({
        originalDocumentId: original.id,
        clientRequestId: randomUUID(),
        refundKind: "PARTIAL",
        lines: [{ lineNumber: 1, quantity: "1" }],
        modificationCode: 3,
        modificationReason: "Segunda devolución",
        paymentType: 1,
        creditNoteIndicator: 0,
      })
      .expect(201);
    expect(second.body.value.encf).toBe("E340000000002");
    expect(Number(second.body.value.reservedAmount)).toBe(59);

    // La referencia al original viaja en la proyección de la bandeja.
    const tray = await http()
      .get("/ecf/documents")
      .query({ documentType: "E34" })
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(tray.body.total).toBe(2);
    const first = tray.body.items.find(
      (item: { id: string }) => item.id === partial.body.value.documentId,
    );
    expect(first.originalEncf).toBe(original.encf);
    expect(first.total).toBe("59.00");

    // PostgreSQL: dos reservas y ningún efecto sobre inventario ni caja.
    expect(
      await prisma.ecfElectronicDocument.count({
        where: { companyId: tenant.companyId, documentType: "E34" },
      }),
    ).toBe(2);
    expect(
      await prisma.ecfCreditReservation.count({ where: { companyId: tenant.companyId } }),
    ).toBe(2);
    expect(
      await prisma.inventoryMovement.count({ where: { companyId: tenant.companyId } }),
    ).toBe(0);
    expect(
      await prisma.sale.count({ where: { companyId: tenant.companyId } }),
    ).toBe(1);
  });

  // ---------------------------------------------------------------------------
  // CIRCUITO SIMULADO COMPLETO POR HTTP
  //
  // Prepara (HTTP) → despacha contra el ALANUBE SIMULADO (HTTP) → normaliza y
  // persiste → consulta de nuevo por HTTP (bandeja y detalle) → verificación
  // directa en PostgreSQL. Cierra el circuito sin proveedor real, sin red, sin
  // credenciales y sin consumir numeración oficial.
  // ---------------------------------------------------------------------------
  it("SIMULADO: circuito HTTP completo contra Alanube simulado, sin aceptación fiscal", async () => {
    const tenant = await registerTenant("sim");
    const token = await login(tenant.email);
    await enableEcf(token);
    await registerSequence(token, "E31");
    const sale = await seedSale(tenant.companyId, tenant.userId);

    // 1) Preparación por HTTP: el e-NCF se reserva y el documento queda validado.
    const prepared = await http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${token}`)
      .send({
        saleId: sale.id,
        documentType: "E31",
        paymentType: 1,
        incomeType: 1,
        sequenceDueDate: "2026-12-31",
      })
      .expect(201);
    const documentId = prepared.body.value.documentId as string;
    expect(prepared.body.value.status).toBe("LOCAL_VALIDATED");
    expect(prepared.body.value.encf).toBe("E310000000001");

    // 2) Despacho SIMULADO por HTTP (aceptación declarada por el proveedor).
    const dispatched = await http()
      .post(`/ecf/documents/${documentId}/simulate-dispatch`)
      .set("Authorization", `Bearer ${token}`)
      .send({ scenario: "PROVIDER_ACCEPTED" })
      .expect(201);

    // El resultado se declara SIMULADO y nunca como aceptación fiscal oficial.
    expect(dispatched.body).toMatchObject({
      simulated: true,
      officialFiscalAcceptance: false,
      scenario: "PROVIDER_ACCEPTED",
      correlated: true,
      documentType: "E31",
    });
    expect(dispatched.body.observation.providerOutcome).toBe("ACCEPTED");

    // 3) Persistencia: aceptación del PROVEEDOR observada ⇒ revisión humana.
    const row = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId: tenant.companyId, id: documentId },
    });
    expect(row.status).toBe("HUMAN_REVIEW_REQUIRED");
    expect(row.externalDocumentNumber).toBe("E310000000001");
    expect(row.externalProviderId).toBeTruthy();
    expect(
      await prisma.ecfEvidenceReceipt.count({
        where: { companyId: tenant.companyId, documentId },
      }),
    ).toBe(1);
    // La regla de oro: ni un 2xx simulado ni la declaración del proveedor
    // producen aceptación de la DGII.
    expect(
      await prisma.ecfElectronicDocument.count({
        where: {
          companyId: tenant.companyId,
          status: { in: ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] },
        },
      }),
    ).toBe(0);

    // 4) Consulta posterior por HTTP: bandeja y detalle reflejan lo persistido.
    const tray = await http()
      .get("/ecf/documents")
      .query({ documentType: "E31" })
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(tray.body.total).toBe(1);
    expect(tray.body.items[0].status).toBe("HUMAN_REVIEW_REQUIRED");
    expect(tray.body.items[0].statusGroup).toBe("REQUIRES_REVIEW");
    expect(tray.body.items[0].encf).toBe("E310000000001");

    const detail = await http()
      .get(`/ecf/documents/${documentId}`)
      .set("Authorization", `Bearer ${token}`)
      .expect(200);
    expect(detail.body.statusLogs.length).toBeGreaterThan(0);
    // El comprobante fiscal completo nunca se devuelve por las rutas de lectura.
    expect(detail.body).not.toHaveProperty("fiscalDocument");

    // 5) Idempotencia en HTTP: un segundo despacho del mismo comprobante se
    //    rechaza y no registra un segundo envío al proveedor.
    await http()
      .post(`/ecf/documents/${documentId}/simulate-dispatch`)
      .set("Authorization", `Bearer ${token}`)
      .send({ scenario: "PROVIDER_ACCEPTED" })
      .expect(409);
    expect(
      await prisma.ecfElectronicDocumentAttempt.count({
        where: { companyId: tenant.companyId, documentId, operation: "SEND_TO_PROVIDER" },
      }),
    ).toBe(1);
    // El despacho no consume un segundo número: la secuencia sigue donde quedó.
    const sequence = await prisma.ecfSequence.findFirstOrThrow({
      where: { companyId: tenant.companyId, documentType: "E31" },
    });
    expect(sequence.nextNumber).toBe(2);

    // 6) Escenario de TIMEOUT sobre otro comprobante: error recuperable, sin
    //    evidencia inventada y sin aceptación.
    const sale2 = await seedSale(tenant.companyId, tenant.userId);
    const prepared2 = await http()
      .post("/ecf/documents/prepare")
      .set("Authorization", `Bearer ${token}`)
      .send({
        saleId: sale2.id,
        documentType: "E31",
        paymentType: 1,
        incomeType: 1,
        sequenceDueDate: "2026-12-31",
      })
      .expect(201);
    const documentId2 = prepared2.body.value.documentId as string;
    expect(documentId2).not.toBe(documentId);

    const timedOut = await http()
      .post(`/ecf/documents/${documentId2}/simulate-dispatch`)
      .set("Authorization", `Bearer ${token}`)
      .send({ scenario: "TIMEOUT" })
      .expect(201);
    expect(timedOut.body).toMatchObject({ simulated: true, correlated: false });
    expect(timedOut.body.httpStatus).toBeNull();
    const row2 = await prisma.ecfElectronicDocument.findFirstOrThrow({
      where: { companyId: tenant.companyId, id: documentId2 },
    });
    expect(row2.status).not.toBe("DGII_ACCEPTED");
    expect(
      await prisma.ecfEvidenceReceipt.count({
        where: { companyId: tenant.companyId, documentId: documentId2 },
      }),
    ).toBe(0);
    expect(
      await prisma.ecfElectronicDocument.count({
        where: {
          companyId: tenant.companyId,
          status: { in: ["DGII_ACCEPTED", "PROVIDER_ACCEPTED"] },
        },
      }),
    ).toBe(0);
  });
});
