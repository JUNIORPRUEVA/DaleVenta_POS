import { Test } from "@nestjs/testing";

/**
 * Guardia de arranque: el módulo completo debe **compilar su grafo de
 * dependencias**. Esta prueba existe porque un token sin proveedor o un
 * proveedor mal cableado no lo detecta TypeScript: compila, y solo falla al
 * bootear la aplicación en producción.
 *
 * No abre conexión real: `compile()` resuelve y construye todos los providers
 * sin ejecutar `onModuleInit`, y `close()` los libera. La conexión efectiva se
 * validó aparte arrancando `dist/main.js` contra una base desechable.
 */
describe("AppModule — grafo de dependencias", () => {
  const requiredEnv: Record<string, string> = {
    NODE_ENV: "test",
    APP_ENV: "dependency-graph-only",
    DATABASE_URL: "postgresql://graph:graph@127.0.0.1:1/graph_only?schema=public",
    JWT_SECRET: "dependency-graph-secret-0000000000000000",
    APP_JWT_SECRET: "dependency-graph-secret-0000000000000000",
    REDIS_ENABLED: "false",
  };

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

  it("construye todos los providers, incluidos los de DOSA", async () => {
    // Import dinámico: los `import` estáticos se hoistean y se ejecutarían antes
    // de que el entorno de esta prueba esté definido.
    const { AppModule } = await import("../../../app.module");

    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    expect(moduleRef).toBeDefined();
    await moduleRef.close();
  }, 60_000);
});
