import { PrismaClient } from "@prisma/client";
import { EcfDosaSessionService } from "./ecf-dosa-session.service";

/**
 * Exclusividad de `postulacion_id` bajo CONCURRENCIA REAL.
 *
 * Lo que estas pruebas demuestran y un doble NO puede demostrar:
 *
 * 1. Dos empresas distintas que intentan quedarse con el MISMO `postulacion_id`
 *    al mismo tiempo: solo una gana. Un `NOT EXISTS` suelto no lo garantiza
 *    (write skew bajo READ COMMITTED); con el bloqueo de asesoría sí.
 * 2. El intento correcto es el que se vincula: solo el ACTIVO de esa empresa y
 *    ese RNC.
 * 3. Un evento fuera de orden no reescribe el vínculo ya confirmado.
 * 4. Sin intento activo no se inventa nada.
 *
 * Solo contra una base DESECHABLE declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const COMPANY_A = "7a7a7a7a-0000-4000-8000-0000000000aa";
const COMPANY_B = "7b7b7b7b-0000-4000-8000-0000000000bb";
const RNC_A = "133306101";
const RNC_B = "130000202";
const POSTULATION = "postulacion-concurrente-0001";

const ALL_COMPANIES = [COMPANY_A, COMPANY_B];

real("postulacion_id — exclusividad concurrente en PostgreSQL", () => {
  let prisma: PrismaClient;
  let sessions: EcfDosaSessionService;

  beforeAll(async () => {
    prisma = new PrismaClient();
    // Se usa PrismaService-like: el servicio real, con su `$transaction`.
    sessions = new EcfDosaSessionService(prisma as never);

    for (const [id, slug] of [
      [COMPANY_A, "bind-a"],
      [COMPANY_B, "bind-b"],
    ]) {
      await prisma.$executeRaw`
        INSERT INTO "companies" ("id","name","slug","updated_at")
        VALUES (${id}::uuid, ${slug}, ${slug}, NOW())
        ON CONFLICT ("id") DO NOTHING
      `;
    }
  });

  beforeEach(async () => {
    await cleanup();
  });

  afterAll(async () => {
    await cleanup();
    await prisma.$executeRaw`
      DELETE FROM "companies" WHERE "id" = ANY(${ALL_COMPANIES}::uuid[])
    `;
    await prisma.$disconnect();
  });

  async function cleanup() {
    await prisma.$executeRaw`
      DELETE FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ANY(${ALL_COMPANIES}::uuid[])
    `;
  }

  /** Crea el intento ACTIVO de una empresa. */
  async function activeSession(companyId: string, rnc: string) {
    await prisma.$executeRaw`
      INSERT INTO "ecf_dosa_certification_sessions"
        ("id","company_id","rnc","attempt_no","active_key","status","updated_at")
      VALUES
        (gen_random_uuid(), ${companyId}::uuid, ${rnc}, 1,
         ${`${companyId}:${rnc}`}, 'RUNNING', NOW())
    `;
  }

  async function boundOwners(postulationId: string) {
    return prisma.$queryRaw<Array<{ company_id: string }>>`
      SELECT "company_id"
        FROM "ecf_dosa_certification_sessions"
       WHERE "provider_postulation_id" = ${postulationId}
    `;
  }

  it("dos empresas simultáneas con el MISMO postulacion_id: solo una lo obtiene", async () => {
    await activeSession(COMPANY_A, RNC_A);
    await activeSession(COMPANY_B, RNC_B);

    const [a, b] = await Promise.all([
      sessions.bindProviderPostulation({
        companyId: COMPANY_A,
        rnc: RNC_A,
        providerPostulationId: POSTULATION,
      }),
      sessions.bindProviderPostulation({
        companyId: COMPANY_B,
        rnc: RNC_B,
        providerPostulationId: POSTULATION,
      }),
    ]);

    // Exactamente una vinculación gana.
    expect([a.bound, b.bound].filter(Boolean)).toHaveLength(1);

    // Y en la base solo una fila lo declara.
    const owners = await boundOwners(POSTULATION);
    expect(owners).toHaveLength(1);
  });

  it("repetir la misma vinculación es idempotente", async () => {
    await activeSession(COMPANY_A, RNC_A);
    const input = {
      companyId: COMPANY_A,
      rnc: RNC_A,
      providerPostulationId: POSTULATION,
    };

    expect((await sessions.bindProviderPostulation(input)).bound).toBe(true);
    expect((await sessions.bindProviderPostulation(input)).bound).toBe(true);

    // Sexto intento, ahora en ráfaga.
    const burst = await Promise.all(
      Array.from({ length: 6 }, () => sessions.bindProviderPostulation(input)),
    );
    expect(burst.every((r) => r.bound)).toBe(true);
    expect(await boundOwners(POSTULATION)).toHaveLength(1);
  });

  it("un evento fuera de orden no reescribe el vínculo confirmado", async () => {
    await activeSession(COMPANY_A, RNC_A);

    const first = await sessions.bindProviderPostulation({
      companyId: COMPANY_A,
      rnc: RNC_A,
      providerPostulationId: "postulacion-1",
    });
    expect(first.bound).toBe(true);

    // Llega un identificador DISTINTO para el mismo intento: no lo sobrescribe.
    const second = await sessions.bindProviderPostulation({
      companyId: COMPANY_A,
      rnc: RNC_A,
      providerPostulationId: "postulacion-2",
    });
    expect(second.bound).toBe(false);

    const rows = await prisma.$queryRaw<
      Array<{ provider_postulation_id: string }>
    >`
      SELECT "provider_postulation_id"
        FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;
    expect(rows[0].provider_postulation_id).toBe("postulacion-1");
  });

  it("sin intento activo no se vincula ni se crea nada", async () => {
    // Hay empresa, pero ninguna sesión.
    const result = await sessions.bindProviderPostulation({
      companyId: COMPANY_A,
      rnc: RNC_A,
      providerPostulationId: POSTULATION,
    });

    expect(result.bound).toBe(false);
    const rows = await prisma.$queryRaw<Array<{ n: number }>>`
      SELECT count(*)::int AS "n" FROM "ecf_dosa_certification_sessions"
       WHERE "company_id" = ${COMPANY_A}::uuid
    `;
    expect(rows[0].n).toBe(0);
  });

  it("no se vincula al intento de OTRO RNC de la misma empresa", async () => {
    await activeSession(COMPANY_A, RNC_A);

    const result = await sessions.bindProviderPostulation({
      companyId: COMPANY_A,
      rnc: RNC_B, // RNC distinto: no corresponde al intento activo
      providerPostulationId: POSTULATION,
    });

    expect(result.bound).toBe(false);
    expect(await boundOwners(POSTULATION)).toHaveLength(0);
  });

  it("una ráfaga de 10 intentos cruzados deja un único dueño", async () => {
    await activeSession(COMPANY_A, RNC_A);
    await activeSession(COMPANY_B, RNC_B);

    const calls = Array.from({ length: 10 }, (_, index) =>
      index % 2 === 0
        ? sessions.bindProviderPostulation({
            companyId: COMPANY_A,
            rnc: RNC_A,
            providerPostulationId: POSTULATION,
          })
        : sessions.bindProviderPostulation({
            companyId: COMPANY_B,
            rnc: RNC_B,
            providerPostulationId: POSTULATION,
          }),
    );

    await Promise.all(calls);

    // Pase lo que pase con el orden, jamás puede haber dos dueños.
    expect(await boundOwners(POSTULATION)).toHaveLength(1);
  });
});
