/**
 * FASE 13 — Recuperación de alertas tras diagnóstico (`planMissingForDiagnosed`)
 * contra PostgreSQL REAL, aislado.
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 *
 * Cubre el defecto observado en la aceptación real: la alerta se planificaba
 * solo en la ingesta y, si las alertas estaban apagadas en ese instante, el
 * incidente quedaba diagnosticado sin aviso para siempre.
 */
import { PrismaClient } from '@prisma/client';
import { GuardianAlertService } from './guardian.alert.service';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `rec${Date.now().toString(36)}`;

let prisma: PrismaClient;
let alerts: GuardianAlertService;
let companyId: string;
let disabledCompanyId: string;
const notifications = { enqueueWhatsAppRawText: jest.fn(async () => ({ id: 'outbox-x' })) } as any;

async function seedIncident(
  targetCompanyId: string,
  options: { diagnosisAgeMinutes?: number; withAlert?: boolean } = {},
): Promise<{ incidentId: string; alertId?: string }> {
  const incident = await prisma.guardianIncident.create({
    data: {
      eventId: `evt-${RUN_ID}-${Math.random().toString(36).slice(2, 10)}`,
      companyId: targetCompanyId,
      fingerprint: `fp-${Math.random().toString(36).slice(2, 12)}`,
      module: 'cash',
      operation: 'closeSession',
      severity: 'SEV1',
      occurredAt: new Date(),
      status: 'OPEN',
    },
    select: { id: true },
  });

  const age = options.diagnosisAgeMinutes ?? 0;
  await prisma.guardianDiagnosis.create({
    data: {
      incidentId: incident.id,
      status: 'DONE',
      verdict: 'PROBABLE',
      model: 'test-model',
      tokensUsed: 0,
      createdAt: new Date(Date.now() - age * 60_000),
    },
  });

  let alertId: string | undefined;
  if (options.withAlert) {
    const created = await prisma.guardianAlert.create({
      data: {
        incidentId: incident.id,
        channel: 'whatsapp_cloud',
        recipientHash: 'hash-test',
        recipientNumber: '18095550000',
        dedupeKey: `guardian:alert:initial:${incident.id}`,
        kind: 'initial',
        state: 'PENDING',
        nextAttemptAt: new Date(),
      },
      select: { id: true },
    });
    alertId = created.id;
  }

  return { incidentId: incident.id, alertId };
}

describeOnPg('Recuperación de alertas tras diagnóstico (PostgreSQL real)', () => {
  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_ALERTS_ENABLED = 'true';
    process.env.GUARDIAN_ALERT_RECIPIENT = '18095550000';
    process.env.GUARDIAN_DIAGNOSIS_ENABLED = 'false';
    process.env.GUARDIAN_AI_PROVIDER = 'mock';
    process.env.NOTIFICATIONS_ENABLED = '0';

    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    alerts = new GuardianAlertService(prisma as any, notifications);

    const company = await prisma.company.create({
      data: { name: `Guardian Recupera ${RUN_ID}`, slug: `guardian-recovery-${RUN_ID}`, guardianEnabled: true },
      select: { id: true },
    });
    companyId = company.id;

    const disabled = await prisma.company.create({
      data: { name: `Guardian Recupera Off ${RUN_ID}`, slug: `guardian-recovery-off-${RUN_ID}`, guardianEnabled: false },
      select: { id: true },
    });
    disabledCompanyId = disabled.id;
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-recovery-' } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_ALERTS_ENABLED;
    delete process.env.GUARDIAN_DIAGNOSIS_ENABLED;
    delete process.env.GUARDIAN_AI_PROVIDER;
    delete process.env.GUARDIAN_ALERT_RECIPIENT;
    delete process.env.NOTIFICATIONS_ENABLED;
  });

  beforeEach(() => {
    notifications.enqueueWhatsAppRawText.mockClear();
  });

  it('planifica exactamente una alerta para un incidente diagnosticado', async () => {
    const { incidentId } = await seedIncident(companyId);

    const planned = await alerts.planMissingForDiagnosed(10);

    expect(planned).toBe(1);
    const rows = await prisma.guardianAlert.findMany({ where: { incidentId } });
    expect(rows).toHaveLength(1);
    expect(rows[0].dedupeKey).toBe(`guardian:alert:initial:${incidentId}`);
    expect(rows[0].kind).toBe('initial');
  }, 60_000);

  it('repetir el proceso no duplica alertas', async () => {
    const { incidentId } = await seedIncident(companyId);

    expect(await alerts.planMissingForDiagnosed(10)).toBe(1);
    expect(await alerts.planMissingForDiagnosed(10)).toBe(0);
    expect(await alerts.planMissingForDiagnosed(10)).toBe(0);

    const rows = await prisma.guardianAlert.findMany({ where: { incidentId } });
    expect(rows).toHaveLength(1);
  }, 60_000);

  it('no recrea una alerta ya existente', async () => {
    const { incidentId, alertId } = await seedIncident(companyId, { withAlert: true });

    const planned = await alerts.planMissingForDiagnosed(10);

    expect(planned).toBe(0);
    const rows = await prisma.guardianAlert.findMany({ where: { incidentId } });
    expect(rows).toHaveLength(1);
    expect(rows[0].id).toBe(alertId);
  }, 60_000);

  it('ignora incidentes fuera de la ventana de recuperación', async () => {
    const { incidentId } = await seedIncident(companyId, { diagnosisAgeMinutes: 120 });

    const planned = await alerts.planMissingForDiagnosed(10, 10);

    expect(planned).toBe(0);
    expect(await prisma.guardianAlert.count({ where: { incidentId } })).toBe(0);
  }, 60_000);

  it('nunca planifica alertas para empresas con Guardian desactivado', async () => {
    const { incidentId } = await seedIncident(disabledCompanyId);

    const planned = await alerts.planMissingForDiagnosed(10);

    expect(planned).toBe(0);
    expect(await prisma.guardianAlert.count({ where: { incidentId } })).toBe(0);
  }, 60_000);

  it('con las alertas apagadas no planifica nada', async () => {
    const { incidentId } = await seedIncident(companyId);
    process.env.GUARDIAN_ALERTS_ENABLED = 'false';
    try {
      expect(await alerts.planMissingForDiagnosed(10)).toBe(0);
      expect(await prisma.guardianAlert.count({ where: { incidentId } })).toBe(0);
    } finally {
      process.env.GUARDIAN_ALERTS_ENABLED = 'true';
    }
  }, 60_000);

  it('no provoca llamadas de IA ni envíos reales', async () => {
    const diagnosis = new GuardianDiagnosisService(prisma as any, [] as any);
    const run = await diagnosis.runBatch(5);

    // El diagnóstico está apagado explícitamente en este entorno de prueba.
    expect(run.enabled).toBe(false);
    expect(run.processed).toBe(0);

    await alerts.planMissingForDiagnosed(10);
    // La planificación solo crea la fila en la cola; no envía nada por sí misma.
    expect(notifications.enqueueWhatsAppRawText).not.toHaveBeenCalled();
  }, 60_000);
});
