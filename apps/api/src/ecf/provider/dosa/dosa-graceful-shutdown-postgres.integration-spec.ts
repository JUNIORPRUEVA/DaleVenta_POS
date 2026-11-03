import { PrismaClient } from "@prisma/client";

/**
 * Cierre ordenado de NestJS contra PostgreSQL real.
 *
 * Arranca la aplicación completa, fuerza una conexión a la base a través de su
 * propio `PrismaService`, cuenta las conexiones abiertas y comprueba que al
 * cerrar **se liberan**. Es la prueba que faltaba: que el proceso no muera
 * dejando el pool colgado.
 *
 * Solo con base desechable declarada explícitamente:
 *
 *   $env:ECF_POSTGRES_UAT = "true"
 *   $env:DATABASE_URL = "postgresql://.../base_desechable"
 */
const real = process.env.ECF_POSTGRES_UAT === "true" ? describe : describe.skip;

const requiredEnv: Record<string, string> = {
  NODE_ENV: "test",
  APP_ENV: "graceful-shutdown",
  JWT_SECRET: "shutdown-test-secret-000000000000000000",
  APP_JWT_SECRET: "shutdown-test-secret-000000000000000000",
  REDIS_ENABLED: "false",
  DOSA_WEBHOOK_ENABLED: "false",
  DOSA_EMISSION_ENABLED: "false",
};

real("NestJS — cierre ordenado y liberación de conexiones", () => {
  const previous: Record<string, string | undefined> = {};

  beforeAll(() => {
    for (const [key, value] of Object.entries(requiredEnv)) {
      previous[key] = process.env[key];
      process.env[key] = value;
    }
  });

  afterAll(() => {
    for (const key of Object.keys(requiredEnv)) {
      if (previous[key] === undefined) delete process.env[key];
      else process.env[key] = previous[key];
    }
  });

  async function openConnections(probe: PrismaClient): Promise<number> {
    const rows = await probe.$queryRaw<Array<{ n: number }>>`
      SELECT count(*)::int AS "n"
        FROM pg_stat_activity
       WHERE datname = current_database()
         AND pid <> pg_backend_pid()
         AND application_name NOT LIKE '%psql%'
    `;
    return rows[0]?.n ?? 0;
  }

  it("arranca, atiende y deja cero conexiones abiertas al cerrar", async () => {
    const { NestFactory } = await import("@nestjs/core");
    const { AppModule } = await import("../../../app.module");
    const { PrismaService } = await import("../../../prisma/prisma.service");

    const app = await NestFactory.create(AppModule, { logger: false });
    await app.listen(0);

    // Fuerza una conexión real a través del pool de la aplicación.
    const prisma = app.get(PrismaService);
    await prisma.$queryRaw`SELECT 1`;

    const probe = new PrismaClient();
    try {
      const before = await openConnections(probe);
      expect(before).toBeGreaterThan(0);

      await app.close();

      // Margen acotado para que el pool cierre en el servidor.
      await new Promise((resolve) => setTimeout(resolve, 1_000));

      const after = await openConnections(probe);
      expect(after).toBe(0);
    } finally {
      await probe.$disconnect();
    }
  }, 120_000);
});
