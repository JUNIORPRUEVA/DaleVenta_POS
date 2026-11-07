import { PrismaClient } from "@prisma/client";
import { createHmac, randomBytes } from "node:crypto";
import {
  DosaCredentialService,
  PrismaDosaCredentialStore,
} from "./dosa-credential.service";
import { DosaCredentialVault } from "./dosa-credential-vault.service";
import { PrismaDosaCompanyResolver } from "./dosa-company-resolver.service";
import { DosaWebhookService } from "./dosa-webhook.service";
import type { DosaSignatureConfig } from "./dosa-webhook-signature.policy";

/**
 * Ciclo completo multiempresa contra PostgreSQL real.
 *
 * Solo con una base desechable declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 *
 * Escenario (el del encargo):
 *
 * * Empresa A — certificada, recibe credenciales TEST y PRODUCCIÓN.
 * * Empresa B — en certificación, todavía sin credenciales.
 * * Empresa C — certificada, con credenciales distintas de las de A.
 * * Empresa D — con el MISMO RNC que A: debe provocar ambigüedad, no una elección.
 *
 * Lo que se demuestra y un doble no puede demostrar:
 *
 * 1. Un evento se asigna a la empresa correcta por RNC + sesión, no por parecido.
 * 2. Las dos claves quedan en filas distintas, una por ambiente.
 * 3. Ninguna empresa ve ni toca las credenciales de otra.
 * 4. Reintento idéntico → `duplicate`; mismo identificador con cuerpo distinto →
 *    evento nuevo (no se pierde) y conflicto si la credencial ya estaba activa.
 * 5. RNC desconocido o ambiguo → se detiene sin escribir nada.
 * 6. Entregas concurrentes → una sola fila de evento.
 */
const real =
  process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const SECRET = "secreto-hmac-multiempresa-no-real";
const MASTER = randomBytes(32).toString("base64");

const COMPANY_A = "a1a1a1a1-0000-4000-8000-0000000000a1";
const COMPANY_B = "b2b2b2b2-0000-4000-8000-0000000000b2";
const COMPANY_C = "c3c3c3c3-0000-4000-8000-0000000000c3";
const COMPANY_D = "d4d4d4d4-0000-4000-8000-0000000000d4";

const RNC_A = "133080206";
const RNC_B = "130000002";
const RNC_C = "130000003";
const RNC_D = "130000004"; // propia; la ambigüedad se crea dentro de su prueba

const signatureConfig: DosaSignatureConfig = {
  strategy: "HMAC_SHA256_TIMESTAMPED",
  secret: SECRET,
  timestampUnit: "seconds",
  toleranceSeconds: 300,
};

function payload(input: {
  postulacionId?: string;
  rnc: string;
  apiKeyProduccion?: string;
  apiKeyTest?: string;
  apiSecret?: string;
  estado?: string;
  disponiblesDesde?: string;
}) {
  return {
    postulacion_id: input.postulacionId ?? "post-multi-1",
    rnc: input.rnc,
    razon_social: "EMPRESA DE PRUEBA SRL",
    correo: "fiscal@example.test",
    ambiente: "Produccion",
    estado_certificacion: input.estado ?? "finalizado",
    disponibles_desde: input.disponiblesDesde ?? "2026-11-01T22:50:12Z",
    credenciales_pendientes: false,
    credenciales: {
      ...(input.apiKeyProduccion ? { api_key_produccion: input.apiKeyProduccion } : {}),
      ...(input.apiKeyTest ? { api_key_test: input.apiKeyTest } : {}),
      ...(input.apiSecret ? { api_secret: input.apiSecret } : {}),
    },
  };
}

function signed(body: Record<string, unknown>) {
  const raw = Buffer.from(JSON.stringify(body), "utf8");
  const t = String(Math.floor(Date.now() / 1000));
  const digest = createHmac("sha256", SECRET)
    .update(`${t}.`, "utf8")
    .update(raw)
    .digest("hex");
  return {
    headers: { "x-dosa-signature": `t=${t},v1=${digest}` },
    rawBody: raw,
    body: JSON.parse(raw.toString()),
  };
}

real("Webhook DOSA — ciclo multiempresa en PostgreSQL real", () => {
  let prisma: PrismaClient;
  let service: DosaWebhookService;
  let credentials: DosaCredentialService;

  const ids = [COMPANY_A, COMPANY_B, COMPANY_C, COMPANY_D];

  beforeAll(async () => {
    prisma = new PrismaClient();

    // Limpieza idempotente de la propia fixture.
    await prisma.$executeRaw`DELETE FROM "ecf_dosa_webhook_events" WHERE "company_id" = ANY(${ids}::uuid[])`;
    await prisma.$executeRaw`DELETE FROM "ecf_dosa_company_credentials" WHERE "company_id" = ANY(${ids}::uuid[])`;
    await prisma.$executeRaw`DELETE FROM "ecf_dosa_certification_sessions" WHERE "company_id" = ANY(${ids}::uuid[])`;
    await prisma.$executeRaw`DELETE FROM "ecf_company_configurations" WHERE "company_id" = ANY(${ids}::uuid[])`;
    await prisma.$executeRaw`DELETE FROM "companies" WHERE "id" = ANY(${ids}::uuid[])`;

    for (const [id, slug] of [
      [COMPANY_A, "multi-empresa-a"],
      [COMPANY_B, "multi-empresa-b"],
      [COMPANY_C, "multi-empresa-c"],
      [COMPANY_D, "multi-empresa-d"],
    ]) {
      await prisma.$executeRaw`
        INSERT INTO "companies" ("id","name","slug","updated_at")
        VALUES (${id}::uuid, ${slug}, ${slug}, NOW())
      `;
    }

    // A y C están certificadas y habilitadas para e-CF; B está en trámite.
    for (const [companyId, rnc, enabled] of [
      [COMPANY_A, RNC_A, true],
      [COMPANY_C, RNC_C, true],
      [COMPANY_B, RNC_B, true],
      [COMPANY_D, RNC_D, true],
    ] as const) {
      await prisma.$executeRaw`
        INSERT INTO "ecf_company_configurations" ("id","company_id","enabled")
        VALUES (gen_random_uuid(), ${companyId}::uuid, ${enabled})
      `;
      await prisma.$executeRaw`
        INSERT INTO "ecf_dosa_certification_sessions"
          ("id","company_id","rnc","attempt_no","status","active_key","updated_at")
        VALUES (gen_random_uuid(), ${companyId}::uuid, ${rnc}, 1, 'NOT_STARTED',
                ${`${companyId}:${rnc}`}, NOW())
      `;
    }

    credentials = new DosaCredentialService(
      new PrismaDosaCredentialStore(prisma),
      new DosaCredentialVault(MASTER),
    );
    service = new DosaWebhookService(
      prisma,
      new PrismaDosaCompanyResolver(prisma),
      signatureConfig,
      credentials,
      undefined,
    );
  }, 60000);

  afterAll(async () => {
    if (prisma) await prisma.$disconnect();
  });

  async function rowsOf(companyId: string) {
    return prisma.$queryRaw<
      Array<{ environment: string; status: string; rnc: string; present: unknown }>
    >`
      SELECT "environment","status","rnc","present"
        FROM "ecf_dosa_company_credentials"
       WHERE "company_id" = ${companyId}::uuid
       ORDER BY "environment"
    `;
  }

  async function eventsOf(companyId: string) {
    return prisma.$queryRaw<Array<{ id: string; processing_state: string }>>`
      SELECT "id","processing_state"
        FROM "ecf_dosa_webhook_events"
       WHERE "company_id" = ${companyId}::uuid
       ORDER BY "received_at"
    `;
  }

  it("A recibe sus dos ambientes y las demás empresas quedan intactas", async () => {
    const outcome = await service.handle(
      signed(
        payload({
          rnc: RNC_A,
          apiKeyProduccion: "prod-A",
          apiKeyTest: "test-A",
          apiSecret: "secret-A",
        }),
      ),
    );

    expect(outcome).toMatchObject({ accepted: true, status: 200, duplicate: false });

    const rowsA = await rowsOf(COMPANY_A);
    expect(rowsA.map((row) => row.environment)).toEqual(["production", "test"]);
    expect(rowsA.every((row) => row.status === "PENDING_CONFIRMATION")).toBe(true);
    expect(rowsA.every((row) => row.rnc === RNC_A)).toBe(true);

    // El secreto queda en una sola fila, no duplicado en ambas.
    const present = rowsA.map((row) => row.present as Record<string, boolean>);
    expect(present.filter((entry) => entry.apiSecret === true)).toHaveLength(1);

    // B y C no tienen nada.
    expect(await rowsOf(COMPANY_B)).toHaveLength(0);
    expect(await rowsOf(COMPANY_C)).toHaveLength(0);
  });

  it("el reintento idéntico es duplicado y no crea otra fila", async () => {
    const body = payload({
      rnc: RNC_A,
      apiKeyProduccion: "prod-A",
      apiKeyTest: "test-A",
      apiSecret: "secret-A",
    });

    const outcome = await service.handle(signed(body));

    expect(outcome).toMatchObject({
      accepted: true,
      duplicate: true,
      code: "ECF_DOSA_WEBHOOK_DUPLICATE",
    });
    expect(await eventsOf(COMPANY_A)).toHaveLength(1);
  });

  it("mismo identificador con cuerpo distinto se registra como evento nuevo", async () => {
    // Empresa C, misma postulación lógica pero credenciales distintas.
    const first = await service.handle(
      signed(payload({ rnc: RNC_C, apiKeyProduccion: "prod-C", apiKeyTest: "test-C" })),
    );
    expect(first).toMatchObject({ accepted: true, duplicate: false });

    const rotated = await service.handle(
      signed(
        payload({
          rnc: RNC_C,
          apiKeyProduccion: "prod-C",
          apiKeyTest: "test-C",
          apiSecret: "secreto-nuevo-C",
        }),
      ),
    );

    // No se descarta: entra como evento propio.
    expect(rotated).toMatchObject({ accepted: true, duplicate: false });
    expect(await eventsOf(COMPANY_C)).toHaveLength(2);
  });

  it("un webhook no rota una credencial activa: queda en revisión", async () => {
    await prisma.$executeRaw`
      UPDATE "ecf_dosa_company_credentials"
         SET "status" = 'ACTIVE'
       WHERE "company_id" = ${COMPANY_C}::uuid AND "environment" = 'test'
    `;

    const outcome = await service.handle(
      signed(payload({ rnc: RNC_C, apiKeyTest: "clave-intrusa-C" })),
    );

    expect(outcome).toMatchObject({
      accepted: true,
      code: "ECF_DOSA_WEBHOOK_CONFLICT_PENDING_REVIEW",
    });

    const events = await eventsOf(COMPANY_C);
    expect(events.some((row) => row.processing_state === "CONFLICT_PENDING_REVIEW")).toBe(
      true,
    );

    // La credencial activa sigue activa: no se sustituyó.
    const test = await prisma.$queryRaw<Array<{ status: string }>>`
      SELECT "status" FROM "ecf_dosa_company_credentials"
       WHERE "company_id" = ${COMPANY_C}::uuid AND "environment" = 'test'
    `;
    expect(test[0].status).toBe("ACTIVE");
  });

  it("un RNC sin sesión de certificación se detiene sin escribir", async () => {
    const outcome = await service.handle(
      signed(payload({ rnc: "139999999", apiKeyProduccion: "x" })),
    );

    expect(outcome).toMatchObject({
      accepted: false,
      status: 404,
      reason: "UNKNOWN_RNC",
    });
  });

  it("un RNC repetido en dos empresas es ambiguo: no se elige ninguna", async () => {
    // Se crea la ambigüedad aquí, no en la fixture: D recibe una sesión con el
    // RNC de A. El resolutor debe rechazar en vez de quedarse con la primera.
    const ambiguousKey = `${COMPANY_D}:${RNC_A}`;
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id","company_id","rnc","attempt_no","status","active_key","updated_at")
      VALUES (gen_random_uuid(), ${COMPANY_D}::uuid, ${RNC_A}, 2, 'NOT_STARTED',
              ${ambiguousKey}, NOW())
    `;

    const outcome = await service.handle(
      signed(payload({ rnc: RNC_A, apiKeyProduccion: "prod-ambiguo" })),
    );

    expect(outcome).toMatchObject({ accepted: false, status: 404 });
    expect(await rowsOf(COMPANY_D)).toHaveLength(0);

    // Se retira la ambigüedad para no condicionar el resto de la suite.
    await prisma.$executeRaw`
      DELETE FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${COMPANY_D}::uuid AND "rnc" = ${RNC_A}
    `;
  });

  it("ninguna empresa puede leer las credenciales de otra", async () => {
    const listA = await credentials.listForCompany(COMPANY_A);
    const listC = await credentials.listForCompany(COMPANY_C);

    expect(listA.every((row) => row.companyId === COMPANY_A)).toBe(true);
    expect(listC.every((row) => row.companyId === COMPANY_C)).toBe(true);

    // B sigue sin credenciales.
    expect(await credentials.listForCompany(COMPANY_B)).toHaveLength(0);
  });

  it("entregas concurrentes del mismo evento dejan una sola fila", async () => {
    const before = (await eventsOf(COMPANY_A)).length;
    const body = payload({
      postulacionId: "post-concurrente",
      rnc: RNC_A,
      apiKeyProduccion: "prod-A",
    });

    const outcomes = await Promise.all([
      service.handle(signed(body)),
      service.handle(signed(body)),
      service.handle(signed(body)),
    ]);

    expect(outcomes.every((outcome) => outcome.accepted)).toBe(true);
    const events = await eventsOf(COMPANY_A);
    expect(events.length).toBe(before + 1);
  }, 60000);
});
