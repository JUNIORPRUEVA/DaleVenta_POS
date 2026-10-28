/**
 * APPYRA Guardian AI — verificación del rol PostgreSQL de solo lectura.
 *
 *   $env:GUARDIAN_READER_DATABASE_URL = 'postgresql://guardian_reader:...@127.0.0.1:55661/daleventa_pos_uat'
 *   $env:GUARDIAN_UAT_DATABASE_URL    = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 */
import { PrismaClient } from '@prisma/client';
import { GuardianToolsService } from './guardian.tools.service';

const READER_URL = process.env.GUARDIAN_READER_DATABASE_URL ?? '';
const OWNER_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = READER_URL ? describe : describe.skip;

describeOnPg('guardian_reader — permisos reales en PostgreSQL', () => {
  let reader: PrismaClient;

  beforeAll(async () => {
    reader = new PrismaClient({ datasources: { db: { url: READER_URL } } });
    await reader.$connect();
  });

  afterAll(async () => {
    await reader?.$disconnect();
  });

  it('puede leer las tablas autorizadas', async () => {
    const companies = await reader.company.findMany({ take: 1, select: { id: true } });
    expect(Array.isArray(companies)).toBe(true);
  });

  it('no puede insertar, actualizar ni borrar', async () => {
    await expect(
      reader.company.create({
        data: { name: 'guardian-reader-should-fail', slug: `nope-${Date.now()}`, guardianEnabled: true },
      }),
    ).rejects.toThrow(/permission denied|denegado/i);

    await expect(
      reader.company.updateMany({ where: {}, data: { name: 'x' } }),
    ).rejects.toThrow(/permission denied|denegado/i);

    await expect(reader.company.deleteMany({ where: {} })).rejects.toThrow(
      /permission denied|denegado/i,
    );
  }, 30_000);

  it('tampoco puede escribir con SQL crudo', async () => {
    await expect(
      reader.$executeRawUnsafe(`INSERT INTO companies (id, name, slug) VALUES (gen_random_uuid(), 'x', 'y')`),
    ).rejects.toThrow(/permission denied|denegado/i);

    await expect(reader.$executeRawUnsafe('DROP TABLE IF EXISTS companies')).rejects.toThrow(
      /permission denied|must be owner|denegado/i,
    );
  }, 30_000);

  it('las herramientas de diagnóstico usan el cliente de solo lectura', async () => {
    const previous = process.env.GUARDIAN_READER_DATABASE_URL;
    process.env.GUARDIAN_READER_DATABASE_URL = READER_URL;
    const owner = OWNER_URL ? new PrismaClient({ datasources: { db: { url: OWNER_URL } } }) : null;

    try {
      const tools = new GuardianToolsService(owner as any);
      const rows = await tools.runPredefinedQuery('license_state', ['00000000-0000-0000-0000-000000000000']);
      expect(Array.isArray(rows)).toBe(true);
      await tools.onModuleDestroy();
    } finally {
      if (previous === undefined) delete process.env.GUARDIAN_READER_DATABASE_URL;
      else process.env.GUARDIAN_READER_DATABASE_URL = previous;
      await owner?.$disconnect();
    }
  }, 30_000);
});
