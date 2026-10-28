/**
 * FASE A2 — estados de entrega reales (SENT/DELIVERED/READ/FAILED) sobre PostgreSQL.
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 *
 * Verifica que un HTTP 200 aceptado por Meta nunca se confunde con entrega, que
 * los webhooks desordenados no degradan el estado y que un fallo asíncrono
 * posterior a la entrega no borra la evidencia de entrega.
 */
import { PrismaClient } from '@prisma/client';
import { GuardianAlertService } from './guardian.alert.service';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianAlertChannel, GuardianChannelResult } from './guardian.alert.channels';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `dl${Date.now().toString(36)}`;

function event(overrides: Partial<GuardianIngestEventDto> = {}): GuardianIngestEventDto {
  return {
    eventId: `evt-${Math.random().toString(36).slice(2, 12)}-${Date.now().toString(36)}`,
    severity: 'SEV1',
    module: 'cash',
    operation: 'closeSession',
    exceptionType: 'CashCloseError',
    platform: 'windows',
    appVersion: '1.4.5',
    deviceId: `dev-${RUN_ID}`,
    occurredAt: new Date().toISOString(),
    message: 'fallo al cerrar turno',
    ...overrides,
  } as GuardianIngestEventDto;
}

function fakeChannel(name: string, result: GuardianChannelResult): GuardianAlertChannel & { send: jest.Mock } {
  return {
    name,
    isConfigured: () => true,
    send: jest.fn(async () => result),
  } as any;
}

describeOnPg('Guardian entrega real de alertas sobre PostgreSQL', () => {
  let prisma: PrismaClient;
  let alerts: GuardianAlertService;
  let ingest: GuardianIngestService;
  let company: { id: string };

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_ALERTS_ENABLED = 'true';
    process.env.GUARDIAN_ALERT_RECIPIENT = '18095550000';
    delete process.env.GUARDIAN_ALERT_RECIPIENTS;
    process.env.GUARDIAN_ALERTS_EVOLUTION_ENABLED = 'false';

    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();

    const notificationsStub = { enqueueWhatsAppRawText: jest.fn(async () => ({ id: 'outbox-1' })) } as any;
    alerts = new GuardianAlertService(prisma as any, notificationsStub);
    ingest = new GuardianIngestService(prisma as any, new GuardianQuotaService(prisma as any));

    company = await prisma.company.create({
      data: { name: `Guardian Entrega ${RUN_ID}`, slug: `guardian-delivery-${RUN_ID}`, guardianEnabled: true },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-delivery-' } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_ALERTS_ENABLED;
    delete process.env.GUARDIAN_ALERT_RECIPIENT;
    delete process.env.GUARDIAN_ALERTS_EVOLUTION_ENABLED;
  });

  const seedAlert = async (messageId: string) => {
    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;
    const plan = await alerts.planForIncident(incidentId);
    expect(plan.created).toBe(true);
    await prisma.guardianAlert.update({
      where: { id: plan.alertId! },
      data: { state: 'SENT', providerMessageId: messageId, sentAt: new Date(), lastProviderStatus: 'accepted' },
    });
    return plan.alertId!;
  };

  it('conserva el destinatario administrativo en la alerta', async () => {
    const alertId = await seedAlert(`wamid.rec.${RUN_ID}`);
    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: alertId } });
    expect(row.recipientNumber).toBe('18095550000');
  }, 60_000);

  it('aplica el ciclo SENT → DELIVERED → READ sin degradar', async () => {
    const alertId = await seedAlert(`wamid.cycle.${RUN_ID}`);

    expect((await alerts.markDelivery(`wamid.cycle.${RUN_ID}`, 'sent')).state).toBe('SENT');

    const delivered = await alerts.markDelivery(`wamid.cycle.${RUN_ID}`, 'delivered');
    expect(delivered.state).toBe('DELIVERED');
    let row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: alertId } });
    expect(row.deliveredAt).toBeTruthy();
    expect(row.readAt).toBeNull();

    const read = await alerts.markDelivery(`wamid.cycle.${RUN_ID}`, 'read');
    expect(read.state).toBe('READ');
    row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: alertId } });
    expect(row.readAt).toBeTruthy();
    expect(row.lastProviderStatus).toBe('read');
  }, 60_000);

  it('un webhook desordenado no hace retroceder el estado', async () => {
    const alertId = await seedAlert(`wamid.order.${RUN_ID}`);
    await alerts.markDelivery(`wamid.order.${RUN_ID}`, 'read');

    const late = await alerts.markDelivery(`wamid.order.${RUN_ID}`, 'delivered');
    expect(late.state).toBe('READ');

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: alertId } });
    expect(row.state).toBe('READ');
    expect(row.readAt).toBeTruthy();
  }, 60_000);

  it('un failed antes de entregar marca FAILED_PERMANENT', async () => {
    const alertId = await seedAlert(`wamid.fail.${RUN_ID}`);
    const outcome = await alerts.markDelivery(`wamid.fail.${RUN_ID}`, 'failed', '131026 destinatario inválido');
    expect(outcome.state).toBe('FAILED_PERMANENT');

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: alertId } });
    expect(row.lastError).toContain('131026');
  }, 60_000);

  it('un failed posterior a la entrega conserva la evidencia de entrega', async () => {
    const alertId = await seedAlert(`wamid.late.${RUN_ID}`);
    await alerts.markDelivery(`wamid.late.${RUN_ID}`, 'delivered');
    await alerts.markDelivery(`wamid.late.${RUN_ID}`, 'failed', 'error asíncrono del proveedor');

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: alertId } });
    expect(row.state).toBe('DELIVERED');
    expect(row.deliveredAt).toBeTruthy();
    expect(row.lastError).toContain('asíncrono');
  }, 60_000);

  it('respeta Retry-After del proveedor al reprogramar un 429', async () => {
    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const plan = await alerts.planForIncident(outcome.results[0].incidentId!);
    const before = Date.now();

    const throttled = fakeChannel('whatsapp_cloud', {
      ok: false,
      httpStatus: 429,
      error: 'HTTP 429 (131056)',
      classification: 'transient',
      retryAfterMs: 10 * 60_000,
    });

    await alerts.attempt(plan.alertId!, [throttled]);

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    expect(row.state).toBe('PENDING');
    expect(row.nextAttemptAt.getTime()).toBeGreaterThanOrEqual(before + 10 * 60_000 - 5_000);
  }, 60_000);

  it('crea una alerta por cada destinatario administrativo', async () => {
    process.env.GUARDIAN_ALERT_RECIPIENTS = '18095550000,18095550001';
    try {
      const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
      const plan = await alerts.planForIncident(outcome.results[0].incidentId!);
      expect(plan.created).toBe(true);

      const rows = await prisma.guardianAlert.findMany({
        where: { incidentId: outcome.results[0].incidentId!, kind: 'initial' },
        select: { recipientNumber: true, dedupeKey: true },
      });
      expect(rows).toHaveLength(2);
      expect(rows.map((row) => row.recipientNumber).sort()).toEqual(['18095550000', '18095550001']);
      expect(new Set(rows.map((row) => row.dedupeKey)).size).toBe(2);
    } finally {
      delete process.env.GUARDIAN_ALERT_RECIPIENTS;
    }
  }, 60_000);
});
