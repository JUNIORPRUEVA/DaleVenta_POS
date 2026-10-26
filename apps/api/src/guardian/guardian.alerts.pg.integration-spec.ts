/**
 * FASE 4 — Alertas administrativas 24/7 contra PostgreSQL REAL.
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 */
import { createHmac } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { GuardianAlertService, buildGuardianAlertMessage } from './guardian.alert.service';
import { GuardianWebhookController } from './guardian.webhook.controller';
import { GuardianAlertChannel, GuardianChannelResult } from './guardian.alert.channels';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `al${Date.now().toString(36)}`;

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

describe('Guardian alert message', () => {
  it('genera un mensaje comprensible para administración', () => {
    const text = buildGuardianAlertMessage({
      severity: 'SEV1' as any,
      companyName: 'Antonio Celulares',
      module: 'cash',
      operation: 'closeSession',
      occurredAt: new Date('2026-10-25T07:14:00.000Z'),
      problem: 'Se detectó una posible inconsistencia en operaciones asociadas a turnos.',
      diagnosis: null,
      impact: 'Posible diferencia en cierre de caja.',
      incidentId: 'abcd-1234-ef56-7890',
      relatedCount: 3,
    });

    expect(text).toContain('APPYRA GUARDIAN — INCIDENTE CRÍTICO');
    expect(text).toContain('Empresa: Antonio Celulares');
    expect(text).toContain('Módulo: cash / closeSession');
    expect(text).toContain('Diagnóstico:');
    expect(text).toContain('Información pendiente de confirmar.');
    expect(text).toContain('Eventos similares en curso: 3');
    expect(text).toContain('ID: INC-ABCD12');
    expect(text).toContain('No se modificó información del cliente.');
  });
});

describeOnPg('Guardian alertas sobre PostgreSQL real', () => {
  let prisma: PrismaClient;
  let alerts: GuardianAlertService;
  let ingest: GuardianIngestService;
  let company: { id: string };

  const seedIncident = async (overrides: Partial<GuardianIngestEventDto> = {}) => {
    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event(overrides)] });
    const incidentId = outcome.results[0].incidentId!;
    expect(incidentId).toBeTruthy();
    return incidentId;
  };

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_ALERTS_ENABLED = 'true';
    process.env.GUARDIAN_ALERT_RECIPIENT = '18095550000';
    process.env.NOTIFICATIONS_ENABLED = '0';

    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();

    const notificationsStub = { enqueueWhatsAppRawText: jest.fn(async () => ({ id: 'outbox-1' })) } as any;
    alerts = new GuardianAlertService(prisma as any, notificationsStub);
    ingest = new GuardianIngestService(prisma as any, new GuardianQuotaService(prisma as any));

    company = await prisma.company.create({
      data: { name: `Guardian Alertas ${RUN_ID}`, slug: `guardian-alert-${RUN_ID}` },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-alert-' } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_ALERTS_ENABLED;
    delete process.env.GUARDIAN_ALERT_RECIPIENT;
    delete process.env.NOTIFICATIONS_ENABLED;
  });

  it('SEV1 a las 03:00 se encola para envío inmediato (sin horario comercial)', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    const fixedNow = new Date('2026-10-25T07:00:00.000Z');

    const plan = await alerts.planForIncident(incidentId, fixedNow);

    expect(plan.created).toBe(true);
    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    expect(Math.abs(row.nextAttemptAt.getTime() - fixedNow.getTime())).toBeLessThan(1_000);
    expect(row.state).toBe('PENDING');
  }, 60_000);

  it('no duplica la alerta inicial del mismo incidente', async () => {
    const incidentId = await seedIncident({ severity: 'SEV2' });

    const first = await alerts.planForIncident(incidentId);
    const second = await alerts.planForIncident(incidentId);

    expect(first.created).toBe(true);
    expect(second.created).toBe(false);
    expect(second.skipped).toBe('ALREADY_QUEUED');
    expect(second.alertId).toBe(first.alertId);

    const count = await prisma.guardianAlert.count({
      where: { incidentId, kind: 'initial' },
    });
    expect(count).toBe(1);
  }, 60_000);

  it('SEV4 no despierta al administrador por defecto (solo se registra)', async () => {
    const incidentId = await seedIncident({ severity: 'SEV4' });
    const plan = await alerts.planForIncident(incidentId);
    expect(plan.created).toBe(false);
    expect(plan.skipped).toBe('SEV4_RECORDED_ONLY');
  }, 60_000);

  it('los workers reclaman alertas sin solaparse', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    await alerts.planForIncident(incidentId);

    const [claimA, claimB] = await Promise.all([alerts.claimDue(50), alerts.claimDue(50)]);
    const idsA = claimA.map((row) => row.id);
    const idsB = claimB.map((row) => row.id);

    expect(idsA.filter((id) => idsB.includes(id))).toEqual([]);
    expect(idsA.length + idsB.length).toBeGreaterThan(0);
  }, 60_000);

  it('un fallo transitorio reprograma con backoff y deja historial de intento', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    const plan = await alerts.planForIncident(incidentId);

    const transient = fakeChannel('whatsapp_cloud', {
      ok: false,
      error: 'HTTP 503',
      httpStatus: 503,
      classification: 'transient',
    });

    const outcome = await alerts.attempt(plan.alertId!, [transient]);
    expect(outcome.ok).toBe(false);

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    const attempts = await prisma.guardianAlertAttempt.findMany({
      where: { alertId: plan.alertId! },
    });

    expect(row.state).toBe('PENDING');
    expect(row.attempts).toBe(1);
    expect(row.nextAttemptAt.getTime()).toBeGreaterThan(Date.now());
    expect(row.lockedAt).toBeNull();
    expect(attempts).toHaveLength(1);
    expect(attempts[0].outcome).toBe('transient');
  }, 60_000);

  it('tras dos intentos fallidos usa el canal de respaldo independiente', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    const plan = await alerts.planForIncident(incidentId);
    await prisma.guardianAlert.update({
      where: { id: plan.alertId! },
      data: { attempts: 2, state: 'PENDING', nextAttemptAt: new Date(Date.now() - 1_000) },
    });

    const primary = fakeChannel('whatsapp_cloud', {
      ok: false,
      error: 'HTTP 500',
      httpStatus: 500,
      classification: 'transient',
    });
    const fallback = fakeChannel('http_webhook', { ok: true, providerMessageId: 'webhook-accepted' });

    const outcome = await alerts.attempt(plan.alertId!, [primary, fallback]);
    expect(outcome.ok).toBe(true);
    expect(primary.send).not.toHaveBeenCalled();
    expect(fallback.send).toHaveBeenCalledTimes(1);

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    expect(row.state).toBe('SENT');
    expect(row.channel).toBe('http_webhook');
    // El canal es un doble de prueba: se conserva el id que devuelve el doble.
    expect(row.providerMessageId).toBe('webhook-accepted');
  }, 60_000);

  it('un canal de outbox deja la alerta en QUEUED y no la marca como enviada', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    const plan = await alerts.planForIncident(incidentId);

    const queued = fakeChannel('whatsapp_evolution', { ok: true, providerMessageId: 'outbox-123', acceptance: 'queued' });
    const outcome = await alerts.attempt(plan.alertId!, [queued]);
    expect(outcome.ok).toBe(true);

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    expect(row.state).toBe('QUEUED');
    expect(row.acceptedAt).toBeNull();
    expect(row.providerMessageId).toBe('outbox-123');

    const attemptLog = await prisma.guardianAlertAttempt.findFirst({
      where: { alertId: plan.alertId! },
      orderBy: { createdAt: 'desc' },
    });
    expect(attemptLog?.outcome).toBe('queued');
    expect(attemptLog?.detail).toContain('acceptance=queued');

    // El acuse real del proveedor sigue avanzando el ciclo desde QUEUED.
    const delivered = await alerts.markDelivery('outbox-123', 'delivered');
    expect(delivered.state).toBe('DELIVERED');
  }, 60_000);

  it('un proveedor que confirma con id deja la alerta en ACCEPTED', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    const plan = await alerts.planForIncident(incidentId);

    const accepted = fakeChannel('whatsapp_cloud', {
      ok: true,
      providerMessageId: `wamid.accepted.${RUN_ID}`,
      acceptance: 'accepted',
    });
    const outcome = await alerts.attempt(plan.alertId!, [accepted]);
    expect(outcome.ok).toBe(true);

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    expect(row.state).toBe('ACCEPTED');
    expect(row.acceptedAt).toBeTruthy();
    expect(row.sentAt).toBeTruthy();
  }, 60_000);

  it('un fallo permanente marca la alerta y genera escalamiento', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    const plan = await alerts.planForIncident(incidentId);

    const permanent = fakeChannel('whatsapp_cloud', {
      ok: false,
      error: 'número inválido',
      httpStatus: 400,
      classification: 'permanent',
    });
    const fallback = fakeChannel('http_webhook', { ok: false, error: 'sin ruta', classification: 'transient' });

    const outcome = await alerts.attempt(plan.alertId!, [permanent, fallback]);
    expect(outcome.ok).toBe(false);

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    expect(row.state).toBe('FAILED_PERMANENT');

    const escalation = await prisma.guardianAlert.findFirst({
      where: { incidentId, kind: 'escalation' },
    });
    expect(escalation).toBeTruthy();
    expect(escalation!.channel).toBe('http_webhook');
  }, 60_000);

  it('el webhook de entrega marca la alerta como entregada', async () => {
    const incidentId = await seedIncident({ severity: 'SEV1' });
    const plan = await alerts.planForIncident(incidentId);
    await prisma.guardianAlert.update({
      where: { id: plan.alertId! },
      data: { state: 'SENT', providerMessageId: `wamid.${RUN_ID}`, sentAt: new Date() },
    });

    const outcome = await alerts.markDelivery(`wamid.${RUN_ID}`, 'delivered');
    expect(outcome.updated).toBe(1);

    const row = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: plan.alertId! } });
    expect(row.state).toBe('DELIVERED');
    expect(row.deliveredAt).toBeTruthy();
  }, 60_000);
});

describe('Guardian webhook de WhatsApp', () => {
  const controller = new GuardianWebhookController({ markDelivery: jest.fn(async () => ({ updated: 1 })) } as any);

  function responseDouble() {
    const captured: { status?: number; body?: any } = {};
    return {
      captured,
      res: {
        status(code: number) {
          captured.status = code;
          return this;
        },
        json(body: any) {
          captured.body = body;
          return this;
        },
        send(value: any) {
          captured.body = value;
          return this;
        },
      } as any,
    };
  }

  it('rechaza el POST si no hay secreto configurado (fail-closed)', async () => {
    delete process.env.GUARDIAN_WA_APP_SECRET;
    const { captured, res } = responseDouble();
    await controller.receive({ header: () => '', rawBody: Buffer.from('{}') } as any, res);
    expect(captured.status).toBe(503);
  });

  it('rechaza una firma inválida', async () => {
    process.env.GUARDIAN_WA_APP_SECRET = 'secreto-uat';
    const { captured, res } = responseDouble();
    await controller.receive(
      { header: () => 'sha256=deadbeef', rawBody: Buffer.from('{"entry":[]}') } as any,
      res,
    );
    expect(captured.status).toBe(401);
    delete process.env.GUARDIAN_WA_APP_SECRET;
  });

  it('acepta una firma válida y procesa estados', async () => {
    process.env.GUARDIAN_WA_APP_SECRET = 'secreto-uat';
    const raw = Buffer.from(
      JSON.stringify({
        entry: [{ changes: [{ value: { statuses: [{ id: 'wamid.X', status: 'delivered' }] } }] }],
      }),
    );
    const signature = `sha256=${createHmac('sha256', 'secreto-uat').update(raw).digest('hex')}`;
    const { captured, res } = responseDouble();

    await controller.receive({ header: () => signature, rawBody: raw } as any, res);

    expect(captured.status).toBe(200);
    expect(captured.body.processed).toBe(1);
    delete process.env.GUARDIAN_WA_APP_SECRET;
  });
});
