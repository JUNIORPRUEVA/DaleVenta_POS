/**
 * APPYRA Guardian AI — reglas de auditoría preventiva sobre PostgreSQL REAL
 * con datos SINTÉTICOS (no se usa ningún dato de clientes reales).
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 */
import { PrismaClient } from '@prisma/client';
import { GuardianIntegrityService } from './guardian.integrity.service';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `ig${Date.now().toString(36)}`;

describeOnPg('Guardian auditoría preventiva — PostgreSQL real con datos sintéticos', () => {
  let prisma: PrismaClient;
  let service: GuardianIntegrityService;
  let dirty: { id: string };
  let clean: { id: string };
  let userId: string;

  beforeAll(async () => {
    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    service = new GuardianIntegrityService(prisma as any);

    dirty = await prisma.company.create({
      data: { name: `Guardian Integridad ${RUN_ID}`, slug: `guardian-integrity-${RUN_ID}`, guardianEnabled: true },
      select: { id: true },
    });
    clean = await prisma.company.create({
      data: { name: `Guardian Limpia ${RUN_ID}`, slug: `guardian-clean-${RUN_ID}`, guardianEnabled: true },
      select: { id: true },
    });

    const user = await prisma.user.create({
      data: {
        companyId: dirty.id,
        email: `guardian-integrity-${RUN_ID}@uat.local`,
        passwordHash: 'uat-not-a-real-hash',
        nombreCompleto: 'UAT Integridad',
        telefono: '18095550001',
        edad: 30,
        role: 'ADMIN',
      },
      select: { id: true },
    });
    userId = user.id;

    // --- Caso 1: turno abierto hace 30 h (CASH_STALE_OPEN_SESSION)
    // --- Caso 2: dos turnos abiertos en el mismo terminal (DUPLICATE)
    await prisma.$executeRawUnsafe(
      `INSERT INTO cash_sessions (id, company_id, "openedByUserId", "openedAt", "status", "updatedAt")
       VALUES (gen_random_uuid(), $1::uuid, $2::uuid, (now() AT TIME ZONE 'UTC') - interval '30 hours', 'OPEN', (now() AT TIME ZONE 'UTC'))`,
      dirty.id,
      userId,
    );
    await prisma.$executeRawUnsafe(
      `INSERT INTO cash_sessions (id, company_id, "openedByUserId", "openedAt", "status", "updatedAt")
       VALUES (gen_random_uuid(), $1::uuid, $2::uuid, (now() AT TIME ZONE 'UTC') - interval '2 hours', 'OPEN', (now() AT TIME ZONE 'UTC'))`,
      dirty.id,
      userId,
    );

    // --- Caso 3: sesión cerrada con venta posterior (patrón de cierre contaminado)
    await prisma.$executeRawUnsafe(
      `INSERT INTO cash_sessions (id, company_id, "openedByUserId", "openedAt", "closedAt", "status", "updatedAt")
       VALUES ('11111111-1111-4111-8111-111111111111'::uuid, $1::uuid, $2::uuid, (now() AT TIME ZONE 'UTC') - interval '8 hours', (now() AT TIME ZONE 'UTC') - interval '4 hours', 'CLOSED', (now() AT TIME ZONE 'UTC'))`,
      dirty.id,
      userId,
    );
    await prisma.$executeRawUnsafe(
      `INSERT INTO "Sale" (id, company_id, "userId", "saleDate", "createdAt", "totalSold", "totalCost", "totalProfit",
                           "commissionAmount", "paymentCashAmount", "paymentTransferAmount", "creditAmount",
                           "isDeleted", "cashSessionId", "updatedAt")
       VALUES ('22222222-2222-4222-8222-222222222222'::uuid, $1::uuid, $2::uuid, (now() AT TIME ZONE 'UTC') - interval '5 hours', (now() AT TIME ZONE 'UTC') - interval '1 hour',
               100, 0, 0, 0, 80, 0, 0, false, '11111111-1111-4111-8111-111111111111'::uuid, (now() AT TIME ZONE 'UTC'))`,
      dirty.id,
      userId,
    );

    // Turno sano para la empresa limpia (sin hallazgos).
    await prisma.$executeRawUnsafe(
      `INSERT INTO cash_sessions (id, company_id, "openedByUserId", "openedAt", "status", "updatedAt")
       VALUES (gen_random_uuid(), $1::uuid, $2::uuid, (now() AT TIME ZONE 'UTC') - interval '1 hour', 'OPEN', (now() AT TIME ZONE 'UTC'))`,
      clean.id,
      userId,
    );

    // --- Caso 4: venta con fecha futura (reloj/sincronización incorrectos)
    await prisma.$executeRawUnsafe(
      `INSERT INTO "Sale" (id, company_id, "userId", "saleDate", "createdAt", "totalSold", "totalCost", "totalProfit",
                           "commissionAmount", "paymentCashAmount", "isDeleted", "updatedAt")
       VALUES ('44444444-4444-4444-8444-444444444444'::uuid, $1::uuid, $2::uuid, (now() AT TIME ZONE 'UTC') + interval '2 hours', (now() AT TIME ZONE 'UTC') + interval '2 hours',
               70, 0, 0, 0, 70, false, (now() AT TIME ZONE 'UTC'))`,
      dirty.id,
      userId,
    );

    // --- Caso 6: venta anulada que conserva pagos
    await prisma.$executeRawUnsafe(
      `INSERT INTO "Sale" (id, company_id, "userId", "saleDate", "createdAt", "totalSold", "totalCost", "totalProfit",
                           "commissionAmount", "paymentCashAmount", "cancelled_at", "isDeleted", "updatedAt")
       VALUES ('55555555-5555-4555-8555-555555555555'::uuid, $1::uuid, $2::uuid, (now() AT TIME ZONE 'UTC') - interval '3 hours', (now() AT TIME ZONE 'UTC') - interval '3 hours',
               90, 0, 0, 0, 90, (now() AT TIME ZONE 'UTC') - interval '2 hours', false, (now() AT TIME ZONE 'UTC'))`,
      dirty.id,
      userId,
    );
  }, 90_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-integrity-' } } });
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-clean-' } } });
    await prisma?.$disconnect();
  });

  it('expone el catálogo de reglas', () => {
    const checks = service.listChecks();
    expect(checks.map((check) => check.code)).toEqual(
      expect.arrayContaining([
        'CASH_STALE_OPEN_SESSION',
        'CASH_DUPLICATE_OPEN_PER_TERMINAL',
        'SALE_AFTER_SESSION_CLOSED',
        'SALE_WITHOUT_ITEMS',
        'SALE_PAYMENT_MISMATCH',
        'SYNC_OUTBOX_STUCK',
      ]),
    );
  });

  it('detecta los patrones sembrados en la empresa de prueba', async () => {
    const result = await service.runForCompany(dirty.id);
    const codes = result.findings.map((finding) => finding.checkCode);

    expect(codes).toContain('CASH_STALE_OPEN_SESSION');
    expect(codes).toContain('CASH_DUPLICATE_OPEN_PER_TERMINAL');
    expect(codes).toContain('SALE_AFTER_SESSION_CLOSED');
    expect(codes).toContain('SALE_PAYMENT_MISMATCH');
      expect(codes).toContain('SALE_FUTURE_DATED');
      expect(codes).toContain('SALE_CANCELLED_WITH_PAYMENT');
      expect(result.totalFindings).toBeGreaterThanOrEqual(6);
  }, 60_000);

  it('no genera falsos positivos en una empresa con operación normal', async () => {
    const result = await service.runForCompany(clean.id);
    expect(result.findings).toEqual([]);
    expect(result.totalFindings).toBe(0);
  }, 60_000);

  it('aísla empresas: los hallazgos de una no aparecen en la otra', async () => {
    const dirtyResult = await service.runForCompany(dirty.id);
    const cleanResult = await service.runForCompany(clean.id);

    const dirtySaleIds = dirtyResult.findings
      .flatMap((finding) => finding.samples)
      .map((sample) => sample.sale_id)
      .filter(Boolean);
    const cleanSaleIds = cleanResult.findings
      .flatMap((finding) => finding.samples)
      .map((sample) => sample.sale_id)
      .filter(Boolean);

    expect(cleanSaleIds).toEqual([]);
    expect(dirtySaleIds).not.toEqual([]);
  }, 60_000);

  it('permite ejecutar un subconjunto de reglas', async () => {
    const result = await service.runForCompany(dirty.id, { codes: ['SALE_PAYMENT_MISMATCH'] });
    expect(result.checksRun).toBe(1);
    expect(result.findings.map((f) => f.checkCode)).toEqual(['SALE_PAYMENT_MISMATCH']);
  }, 60_000);
});
