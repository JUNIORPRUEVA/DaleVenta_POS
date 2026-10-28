/**
 * FASE 4 — Despacho de alertas consciente del diagnóstico sobre PostgreSQL real.
 *
 * Canal de entrega: `http_webhook` apuntando a un receptor HTTP local (mock de
 * WhatsApp). **Nunca** se configura WhatsApp real en esta prueba: si el canal
 * Cloud no está configurado, la alerta va por el webhook.
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55501/guardian_uat_test'
 *   npx jest --runInBand src/guardian/guardian.alert.readiness.pg.integration-spec.ts
 */
import { createServer, type Server } from 'node:http';
import { AddressInfo } from 'node:net';
import { PrismaClient } from '@prisma/client';
import { GuardianAlertService } from './guardian.alert.service';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';
import { GuardianToolsService } from './guardian.tools.service';
import { MockGuardianAiProvider } from './ai/mock-guardian-ai.provider';
import { ALERT_DIAGNOSIS_FALLBACK_TEXT } from './guardian.alert.readiness';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;

const RUN_ID = `ar${Date.now().toString(36)}`;
const RECIPIENT = '18095550123';
const WAIT_SECONDS = 90;

type CapturedMessage = { dedupeKey: string; to: string; text: string; at: number };

describeOnPg('despacho de alertas con diagnóstico (PostgreSQL real)', () => {
  let prisma: PrismaClient;
  let alerts: GuardianAlertService;
  let company: { id: string };
  let server: Server;
  let webhookUrl: string;
  let received: CapturedMessage[] = [];
  const savedEnv: Record<string, string | undefined> = {};

  const patchEnv = (values: Record<string, string | undefined>) => {
    for (const [key, value] of Object.entries(values)) {
      if (!(key in savedEnv)) savedEnv[key] = process.env[key];
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  };

  beforeAll(async () => {
    server = createServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on('data', (chunk) => chunks.push(chunk as Buffer));
      req.on('end', () => {
        const body = Buffer.concat(chunks).toString('utf8');
        try {
          received.push({ ...JSON.parse(body), at: Date.now() });
        } catch {
          received.push({ dedupeKey: '', to: '', text: body, at: Date.now() });
        }
        res.writeHead(200, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ id: `mock-${received.length}` }));
      });
    });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    webhookUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}/guardian/alert`;

    patchEnv({
      GUARDIAN_ENABLED: 'true',
      GUARDIAN_ALERTS_ENABLED: 'true',
      GUARDIAN_ALERT_RECIPIENT: RECIPIENT,
      GUARDIAN_ALERT_FALLBACK_WEBHOOK_URL: webhookUrl,
      GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS: String(WAIT_SECONDS),
      // Ningún canal real de WhatsApp puede quedar configurado.
      GUARDIAN_WA_CLOUD_TOKEN: undefined,
      GUARDIAN_WA_CLOUD_TOKEN_FILE: undefined,
      GUARDIAN_WA_PHONE_NUMBER_ID: undefined,
      GUARDIAN_WA_APP_SECRET: undefined,
      GUARDIAN_WA_APP_SECRET_FILE: undefined,
      GUARDIAN_ALERTS_EVOLUTION_ENABLED: undefined,
      NOTIFICATIONS_ENABLED: '0',
      // IA en modo mock: el diagnóstico se genera sin llamadas externas.
      GUARDIAN_AI_PROVIDER: 'mock',
      GUARDIAN_DIAGNOSIS_ENABLED: 'true',
    });

    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    const notificationsStub = { enqueueWhatsAppRawText: jest.fn(async () => ({ id: 'outbox-1' })) } as any;
    alerts = new GuardianAlertService(prisma as any, notificationsStub);

    company = await prisma.company.create({
      data: { name: `Alert readiness ${RUN_ID}`, slug: `alert-readiness-${RUN_ID}`, guardianEnabled: true },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'alert-readiness-' } } });
    await prisma?.$disconnect();
    for (const [key, value] of Object.entries(savedEnv)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  beforeEach(async () => {
    received = [];
    // Cada caso arranca sin alertas pendientes de la compañía de prueba: evita
    // que una alerta diferida de otro caso se despache en este.
    await prisma.guardianAlert.deleteMany({ where: { incident: { companyId: company.id } } });
  });

  const makeIncident = async (params: {
    suffix: string;
    severity: 'SEV1' | 'SEV2' | 'SEV3';
    receivedAt?: Date;
  }) =>
    prisma.guardianIncident.create({
      data: {
        eventId: `evt-${params.suffix}-${RUN_ID}`,
        companyId: company.id,
        fingerprint: `fp-${params.suffix}-${RUN_ID}`,
        module: 'cash',
        operation: 'POST /api/v1/cash/close',
        platform: 'backend',
        severity: params.severity,
        exceptionType: 'CashCloseError',
        occurredAt: params.receivedAt ?? new Date(),
        receivedAt: params.receivedAt ?? new Date(),
        payload: { message: 'no se pudo calcular el efectivo esperado' },
        impactSummary: 'Turno de caja abierto',
      },
      select: { id: true },
    });

  const addDiagnosis = async (incidentId: string, summary: string) => {
    await prisma.guardianDiagnosis.create({
      data: {
        incidentId,
        status: 'DONE',
        verdict: 'PROBABLE',
        confidence: 0.62,
        summary,
        impact: 'El turno queda abierto y no se puede facturar',
        model: 'mock-guardian-1',
        tokensUsed: 0,
      },
    });
  };

  const alertsFor = (incidentId: string) =>
    prisma.guardianAlert.findMany({ where: { incidentId }, orderBy: { createdAt: 'asc' } });

  /** Número de alertas de ESE incidente ya aceptadas por el canal. */
  const sentFor = async (incidentId: string) => {
    const rows = await alertsFor(incidentId);
    return rows.filter((row) => Boolean(row.providerMessageId)).length;
  };

  it('SEV2 sin diagnóstico: la alerta espera y no se envía nada', async () => {
    const incident = await makeIncident({ suffix: 'sev2-wait', severity: 'SEV2' });
    const plan = await alerts.planForIncident(incident.id);
    expect(plan.created).toBe(true);

    const outcome = await alerts.processDue(10);
    expect(outcome.processed).toBe(0);
    expect(outcome.sent).toBe(0);
    expect(outcome.deferred).toBe(1);
    expect(received).toHaveLength(0);

    const [alert] = await alertsFor(incident.id);
    expect(alert.state).toBe('PENDING');
  }, 60_000);

  it('cuando el diagnóstico está DONE se envía y la posición 6 lleva el resumen real', async () => {
    const incident = await makeIncident({ suffix: 'sev2-done', severity: 'SEV2' });
    await alerts.planForIncident(incident.id);

    const summary = 'La suma de movimientos no coincide con el saldo de apertura del turno.';
    await addDiagnosis(incident.id, summary);

    const outcome = await alerts.processDue(10);
    expect(outcome.sent).toBe(1);
    expect(received).toHaveLength(1);

    // El mensaje real que saldría por WhatsApp contiene el diagnóstico validado.
    expect(received[0].text).toContain(summary);
    expect(received[0].text).not.toContain(ALERT_DIAGNOSIS_FALLBACK_TEXT);
    // La posición 6 (Diagnóstico) es la que lleva el resumen de la IA.
    expect(received[0].text).toMatch(/Diagn[oó]stico:\s*\n?\s*La suma de movimientos/);

    const [alert] = await alertsFor(incident.id);
    expect(alert.providerMessageId).toBeTruthy();
    expect(['QUEUED', 'ACCEPTED', 'SENT']).toContain(alert.state);
  }, 60_000);

  it('SEV1 se envía de inmediato sin diagnóstico y con texto de respaldo', async () => {
    const incident = await makeIncident({ suffix: 'sev1-fast', severity: 'SEV1' });
    await alerts.planForIncident(incident.id);

    const outcome = await alerts.processDue(10);
    expect(outcome.sent).toBe(1);
    expect(received).toHaveLength(1);
    expect(received[0].text).toContain(ALERT_DIAGNOSIS_FALLBACK_TEXT);
    expect(received[0].text).toContain('CRÍTICO');
  }, 60_000);

  it('al vencer el plazo se envía el respaldo aunque no haya diagnóstico', async () => {
    const incident = await makeIncident({
      suffix: 'sev2-deadline',
      severity: 'SEV2',
      receivedAt: new Date(Date.now() - (WAIT_SECONDS + 5) * 1000),
    });
    await alerts.planForIncident(incident.id);

    const outcome = await alerts.processDue(10);
    expect(outcome.sent).toBe(1);
    expect(received).toHaveLength(1);
    expect(received[0].text).toContain(ALERT_DIAGNOSIS_FALLBACK_TEXT);
  }, 60_000);

  it('dos workers concurrentes no duplican el envío', async () => {
    const incident = await makeIncident({ suffix: 'sev2-race', severity: 'SEV2' });
    await alerts.planForIncident(incident.id);
    await addDiagnosis(incident.id, 'Diagnóstico para prueba de concurrencia.');

    await Promise.all([alerts.processDue(10), alerts.processDue(10)]);
    expect(await sentFor(incident.id)).toBe(1);
    expect(received).toHaveLength(1);

    const list = await alertsFor(incident.id);
    expect(list).toHaveLength(1);
  }, 60_000);

  it('un reinicio tras el envío no reenvía la alerta', async () => {
    const incident = await makeIncident({ suffix: 'sev2-restart', severity: 'SEV2' });
    await alerts.planForIncident(incident.id);
    await addDiagnosis(incident.id, 'Diagnóstico para prueba de reinicio.');

    expect(await alerts.processDue(10).then((outcome) => outcome.sent)).toBe(1);
    expect(received).toHaveLength(1);

    // Simula reinicio del worker: nueva instancia, misma base de datos.
    const restarted = new GuardianAlertService(prisma as any, {
      enqueueWhatsAppRawText: jest.fn(async () => ({ id: 'outbox-1' })),
    } as any);
    const outcome = await restarted.processDue(10);
    expect(outcome.sent).toBe(0);
    expect(received).toHaveLength(1);
    expect(await sentFor(incident.id)).toBe(1);
  }, 60_000);

  it('planificar dos veces el mismo incidente deja una sola alerta inicial', async () => {
    const incident = await makeIncident({ suffix: 'sev2-dupe', severity: 'SEV2' });

    const results = await Promise.all([
      alerts.planForIncident(incident.id),
      alerts.planForIncident(incident.id),
    ]);
    expect(results.filter((result) => result.created).length).toBe(1);

    const list = await alertsFor(incident.id);
    expect(list).toHaveLength(1);
  }, 60_000);

  it('fin a fin con IA mock: diagnóstico generado y enviado dentro de la alerta', async () => {
    const incident = await makeIncident({ suffix: 'e2e-mock', severity: 'SEV2' });
    await alerts.planForIncident(incident.id);

    // 1. El worker diagnostica con el proveedor mock (sin llamadas externas).
    const diagnosisService = new GuardianDiagnosisService(
      prisma as any,
      new GuardianToolsService(prisma as any),
      new MockGuardianAiProvider(),
    );
    // Varios ciclos de worker (como en producción), hasta que este incidente
    // tenga su diagnóstico: otros incidentes de la suite también están en cola.
    let diagnosis = null as Awaited<ReturnType<typeof prisma.guardianDiagnosis.findFirst>>;
    for (let cycle = 0; cycle < 12 && !diagnosis; cycle += 1) {
      await diagnosisService.runBatch(10);
      diagnosis = await prisma.guardianDiagnosis.findFirst({
        where: { incidentId: incident.id },
        orderBy: { createdAt: 'desc' },
      });
    }
    expect(diagnosis?.status).toBe('DONE');
    expect(diagnosis?.model).toBe('mock-guardian-1');

    // 2. La alerta se despacha y lleva ese diagnóstico en la posición 6.
    const outcome = await alerts.processDue(10);
    expect(outcome.sent).toBe(1);
    expect(received).toHaveLength(1);
    expect(received[0].text).toContain(diagnosis!.summary!);
    expect(received[0].text).not.toContain(ALERT_DIAGNOSIS_FALLBACK_TEXT);

    // 3. Un segundo ciclo no vuelve a enviar (idempotencia de extremo a extremo).
    const again = await alerts.processDue(10);
    expect(again.sent).toBe(0);
    expect(received).toHaveLength(1);
  }, 90_000);

  it('con la espera desactivada el comportamiento vuelve a ser inmediato', async () => {    patchEnv({ GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS: '0' });
    try {
      const incident = await makeIncident({ suffix: 'sev2-nowait', severity: 'SEV2' });
      await alerts.planForIncident(incident.id);

      const outcome = await alerts.processDue(10);
      expect(outcome.sent).toBe(1);
      expect(received).toHaveLength(1);
      expect(received[0].text).toContain(ALERT_DIAGNOSIS_FALLBACK_TEXT);
      expect(await sentFor(incident.id)).toBe(1);
    } finally {
      patchEnv({ GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS: String(WAIT_SECONDS) });
    }
  }, 60_000);
});
