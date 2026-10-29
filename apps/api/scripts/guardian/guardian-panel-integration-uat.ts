/**
 * APPYRA Guardian AI — E2E de integración Fullpos ↔ Appyra (UAT aislado).
 *
 * Recorre el circuito completo de la FASE 5:
 *   incidente sintético (API real) → persistencia → alerta 24/7 → diagnóstico IA
 *   → panel Appyra (proxy backend-to-backend) → reconocer → resolver → historial
 *   → estado de workers.
 *
 * Requisitos de entorno (locales, nunca producción):
 *   DATABASE_URL                      base UAT aislada del backend
 *   JWT_SECRET                        secreto local para firmar el token de UAT
 *   GUARDIAN_E2E_API_BASE             API Fullpos (por defecto http://127.0.0.1:4010)
 *   APPYRA_BASE                       backend del panel (por defecto http://127.0.0.1:3100)
 *   APPYRA_ADMIN_USER / APPYRA_ADMIN_PASSWORD
 *   GUARDIAN_E2E_KEEP=1               conserva la empresa sintética para la revisión visual
 */
import http from 'node:http';
import jwt from 'jsonwebtoken';
import { PrismaClient } from '@prisma/client';
import { GuardianAlertService } from '../../src/guardian/guardian.alert.service';
import { GuardianDiagnosisService } from '../../src/guardian/guardian.diagnosis.service';
import { GuardianToolsService } from '../../src/guardian/guardian.tools.service';
import { HttpWebhookChannel } from '../../src/guardian/guardian.alert.channels';
import { MockGuardianAiProvider } from '../../src/guardian/ai/mock-guardian-ai.provider';

const DATABASE_URL = process.env.DATABASE_URL ?? '';
const JWT_SECRET = process.env.JWT_SECRET ?? '';
const API_BASE = (process.env.GUARDIAN_E2E_API_BASE ?? 'http://127.0.0.1:4010').replace(/\/+$/, '');
const APPYRA_BASE = (process.env.APPYRA_BASE ?? 'http://127.0.0.1:3100').replace(/\/+$/, '');
const APPYRA_USER = process.env.APPYRA_ADMIN_USER ?? '';
const APPYRA_PASSWORD = process.env.APPYRA_ADMIN_PASSWORD ?? '';
const KEEP = String(process.env.GUARDIAN_E2E_KEEP ?? '') === '1';
const RUN_ID = `int${Date.now().toString(36)}`;
const WEBHOOK_PORT = 45_997;

let failures = 0;
function check(label: string, condition: boolean, detail?: unknown) {
  const status = condition ? 'PASS' : 'FAIL';
  if (!condition) failures += 1;
  // eslint-disable-next-line no-console
  console.log(`[${status}] ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail).slice(0, 300)}`}`);
}

async function main() {
  if (!DATABASE_URL) throw new Error('DATABASE_URL es requerido (base UAT aislada)');
  if (!JWT_SECRET) throw new Error('JWT_SECRET es requerido');
  if (!APPYRA_USER || !APPYRA_PASSWORD) throw new Error('Credenciales administrativas de UAT requeridas');

  const prisma = new PrismaClient({ datasources: { db: { url: DATABASE_URL } } });
  const received: Array<{ text: string; at: number }> = [];
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
    });
    req.on('end', () => {
      try {
        received.push({ text: String(JSON.parse(body).text ?? ''), at: Date.now() });
      } catch {
        received.push({ text: '', at: Date.now() });
      }
      res.statusCode = 202;
      res.end('ok');
    });
  });
  await new Promise<void>((resolve) => server.listen(WEBHOOK_PORT, '127.0.0.1', resolve));

  let companyId: string | null = null;

  try {
    // ---------- Semilla ----------
    const company = await prisma.company.create({
      data: {
        name: `Guardian Integración ${RUN_ID}`,
        slug: `guardian-integration-${RUN_ID}`,
        licenseStatus: 'TRIAL',
        trialEndsAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
      select: { id: true, name: true },
    });
    companyId = company.id;
    const user = await prisma.user.create({
      data: {
        companyId: company.id,
        email: `guardian-integration-${RUN_ID}@uat.local`,
        passwordHash: 'uat-not-a-real-hash',
        nombreCompleto: 'Guardian Integración',
        telefono: '18095550000',
        edad: 30,
        role: 'ADMIN',
      },
      select: { id: true },
    });
    const session = await prisma.authSession.create({
      data: {
        userId: user.id,
        companyId: company.id,
        refreshTokenHash: `uat-int-${RUN_ID}`,
        tokenFamily: user.id,
        expiresAt: new Date(Date.now() + 60 * 60 * 1000),
      },
      select: { id: true },
    });
    const token = jwt.sign(
      { sub: user.id, sessionId: session.id, companyId: company.id, tokenType: 'access', role: 'ADMIN' },
      JWT_SECRET,
      { expiresIn: '1h' },
    );

    // ---------- 1-2. Ingesta real por HTTP ----------
    const eventId = `evt-int-${RUN_ID}`;
    const payload = {
      events: [
        {
          eventId,
          severity: 'SEV1',
          module: 'cash',
          operation: 'closeSession',
          exceptionType: 'CashCloseError',
          platform: 'windows',
          appVersion: '1.4.5+145',
          deviceId: `dev-int-${RUN_ID}`,
          occurredAt: new Date().toISOString(),
          message: 'fallo al cerrar turno con cliente juan@example.com',
          stack: 'Error: cierre\n    at CashService.close (cash.service.ts:120:9)',
          context: { password: 'no-debe-verse', saleId: 'abc' },
        },
      ],
    };
    const response = await fetch(`${API_BASE}/guardian/incidents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(payload),
    });
    const body: any = await response.json().catch(() => ({}));
    check('ingesta responde 202', response.status === 202, response.status);
    const incidentId = body?.results?.[0]?.incidentId as string | undefined;
    check('incidente persistido y devuelto', Boolean(incidentId), body?.results?.[0]);

    const stored = await prisma.guardianIncident.findFirstOrThrow({
      where: { companyId: company.id, eventId },
      include: { evidences: true },
    });
    const serialized = JSON.stringify(stored);
    check('evidencia redactada (sin contraseña ni correo)', !serialized.includes('no-debe-verse') && !serialized.includes('juan@example.com'));

    // ---------- 3. Alerta 24/7 ----------
    const alerts = new GuardianAlertService(prisma as any, {
      enqueueWhatsAppRawText: async () => ({ id: 'outbox-integration' }),
    } as any);
    const planned = await prisma.guardianAlert.findFirst({
      where: { incidentId: stored.id, kind: 'initial' },
    });
    check('alerta inicial planificada en la ingesta', Boolean(planned), planned?.state);

    const webhook = new HttpWebhookChannel({ url: `http://127.0.0.1:${WEBHOOK_PORT}/guardian` });
    const sendOutcome = planned ? await alerts.attempt(planned.id, [webhook]) : { ok: false };
    check('alerta enviada por canal simulado', (sendOutcome as any).ok === true, sendOutcome);
    check('proveedor simulado recibió el mensaje', received.length === 1, received.length);

    if (planned) {
      const sentAlert = await prisma.guardianAlert.findUniqueOrThrow({ where: { id: planned.id } });
      const receiptId = String(sentAlert.providerMessageId ?? '');
      check('la alerta guarda un acuse único del canal', receiptId.length > 0, receiptId);
      const delivered = await alerts.markDelivery(receiptId, 'delivered');
      check('estado de entrega DELIVERED aplicado', delivered.state === 'DELIVERED', delivered);
      const read = await alerts.markDelivery(receiptId, 'read');
      check('estado de lectura READ aplicado', read.state === 'READ', read);
    }

    // ---------- 4. Diagnóstico IA ----------
    const diagnosisService = new GuardianDiagnosisService(
      prisma as any,
      new GuardianToolsService(prisma as any),
      new MockGuardianAiProvider(),
    );
    const diagnosisOutcome = await diagnosisService.diagnose(stored.id);
    check('diagnóstico ejecutado', diagnosisOutcome.ok === true, diagnosisOutcome);
    const storedDiagnosis = await prisma.guardianDiagnosis.findFirstOrThrow({
      where: { incidentId: stored.id, status: 'DONE' },
      orderBy: { createdAt: 'desc' },
    });
    check(
      'veredicto válido con evidencia',
      ['CONFIRMED', 'PROBABLE', 'INSUFFICIENT'].includes(String(storedDiagnosis.verdict)) &&
        Array.isArray(storedDiagnosis.evidenceRefs) &&
        (storedDiagnosis.evidenceRefs as unknown[]).length > 0,
      { verdict: storedDiagnosis.verdict, evidence: (storedDiagnosis.evidenceRefs as unknown[]).length },
    );

    // ---------- 5-8. Panel Appyra (proxy backend-to-backend) ----------
    const login = await fetch(`${APPYRA_BASE}/api/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: APPYRA_USER, password: APPYRA_PASSWORD }),
    });
    const loginBody: any = await login.json().catch(() => ({}));
    const sessionId = String(loginBody?.sessionId ?? '');
    check('sesión administrativa de Appyra', login.ok && sessionId.length > 0, login.status);

    const admin = async (path: string, init: RequestInit = {}) => {
      const res = await fetch(`${APPYRA_BASE}${path}`, {
        ...init,
        headers: {
          'Content-Type': 'application/json',
          'x-session-id': sessionId,
          ...(init.headers ?? {}),
        },
      });
      const json = await res.json().catch(() => null);
      return { status: res.status, ok: res.ok, body: json as any };
    };

    const health = await admin('/api/admin/guardian/health');
    check('panel: health accesible por el proxy', health.ok && typeof health.body?.guardianEnabled === 'boolean', health.body);

    const summary = await admin('/api/admin/guardian/summary');
    check('panel: summary accesible', summary.ok && typeof summary.body?.totalIncidents === 'number', summary.body?.totalIncidents);

    const companies = await admin('/api/admin/guardian/companies');
    check(
      'panel: la empresa aparece en companies',
      companies.ok && Array.isArray(companies.body?.companies) && companies.body.companies.some((c: any) => c.id === company.id),
    );

    const list = await admin(`/api/admin/guardian/incidents?companyId=${company.id}&limit=20`);
    check(
      'panel: lista el incidente sintético',
      list.ok && Array.isArray(list.body?.items) && list.body.items.some((item: any) => item.id === stored.id),
      list.body?.items?.length,
    );

    const detail = await admin(`/api/admin/guardian/incidents/${stored.id}`);
    check(
      'panel: expediente con evidencias, diagnóstico, alerta e historial',
      detail.ok &&
        Array.isArray(detail.body?.evidences) &&
        detail.body.evidences.length > 0 &&
        Array.isArray(detail.body?.diagnoses) &&
        detail.body.diagnoses.length > 0 &&
        Array.isArray(detail.body?.alerts) &&
        detail.body.alerts.length > 0 &&
        Array.isArray(detail.body?.history) &&
        detail.body.history.length > 0,
      {
        evidences: detail.body?.evidences?.length,
        diagnoses: detail.body?.diagnoses?.length,
        alerts: detail.body?.alerts?.length,
        history: detail.body?.history?.length,
      },
    );
    const attempts = (detail.body?.alerts ?? []).flatMap((row: any) => row.attemptsLog ?? []);
    check('panel: historial de intentos de alerta serializable', attempts.length > 0 && !('id' in attempts[0]), attempts[0]);
    check('panel: alerta refleja el estado real de lectura', (detail.body?.alerts ?? []).some((row: any) => row.state === 'READ'));

    // ---------- 6-7. Reconocer y resolver desde el panel ----------
    const ack = await admin(`/api/admin/guardian/incidents/${stored.id}/ack`, {
      method: 'POST',
      body: JSON.stringify({ note: 'Reconocido en UAT integrada' }),
    });
    check('panel: reconocer cambia el estado', ack.ok && ack.body?.status === 'ACKNOWLEDGED', ack.body?.status);

    const resolve = await admin(`/api/admin/guardian/incidents/${stored.id}/resolve`, {
      method: 'POST',
      body: JSON.stringify({ note: 'Resuelto en UAT integrada' }),
    });
    check('panel: resolver cambia el estado', resolve.ok && resolve.body?.status === 'RESOLVED', resolve.body?.status);

    const after = await admin(`/api/admin/guardian/incidents/${stored.id}`);
    const actors = (after.body?.history ?? []).map((row: any) => String(row.actor));
    check(
      'panel: historial auditable con origen de cada acción',
      after.ok && actors.includes('platform:ack') && actors.includes('platform:resolve'),
      actors,
    );

    // ---------- 9. Estado de los workers ----------
    // Se parte de un estado conocido: la base UAT clonada puede traer latidos
    // históricos de ejecuciones anteriores.
    await prisma.guardianWorkerHeartbeat.deleteMany({
      where: { workerName: { in: ['alerts', 'diagnosis'] } },
    });
    const beforeWorkers = await admin('/api/admin/guardian/workers');
    check(
      'panel: workers sin latido se declaran como missing',
      beforeWorkers.ok && Array.isArray(beforeWorkers.body?.workers) &&
        beforeWorkers.body.workers.every((worker: any) => worker.status === 'missing'),
      beforeWorkers.body,
    );

    const now = new Date();
    for (const name of ['alerts', 'diagnosis']) {
      await prisma.guardianWorkerHeartbeat.upsert({
        where: { workerName: name },
        create: { workerName: name, lastSeenAt: now, cycleCount: BigInt(1), processedLastCycle: 0 },
        update: { lastSeenAt: now, cycleCount: { increment: 1 } },
      });
    }
    const liveWorkers = await admin('/api/admin/guardian/workers');
    check(
      'panel: workers con latido real aparecen disponibles',
      liveWorkers.ok && liveWorkers.body?.available === true &&
        liveWorkers.body.workers.every((worker: any) => worker.status === 'ok'),
      liveWorkers.body,
    );

    await prisma.guardianWorkerHeartbeat.update({
      where: { workerName: 'diagnosis' },
      data: { lastSeenAt: new Date(Date.now() - 45 * 60_000) },
    });
    const degradedWorkers = await admin('/api/admin/guardian/workers');
    check(
      'panel: un worker detenido se detecta como degradado',
      degradedWorkers.ok && degradedWorkers.body?.available === false &&
        degradedWorkers.body.workers.some((worker: any) => worker.status === 'stale'),
      degradedWorkers.body?.workers,
    );

    // ---------- Aislamiento multiempresa ----------
    const otherCompany = await prisma.company.create({
      data: { name: `Guardian Integración Otro ${RUN_ID}`, slug: `guardian-integration-otro-${RUN_ID}` },
      select: { id: true },
    });
    const otherList = await admin(`/api/admin/guardian/incidents?companyId=${otherCompany.id}`);
    check(
      'aislamiento: otra empresa no ve el incidente',
      otherList.ok && Array.isArray(otherList.body?.items) && otherList.body.items.length === 0,
      otherList.body?.items?.length,
    );
    await prisma.company.delete({ where: { id: otherCompany.id } });

    // eslint-disable-next-line no-console
    console.log('\n--- MÉTRICAS INTEGRACIÓN ---');
    // eslint-disable-next-line no-console
    console.log(
      JSON.stringify(
        {
          incidente: stored.id,
          empresa: company.name,
          alerta_estado: (await prisma.guardianAlert.findFirst({ where: { incidentId: stored.id } }))?.state,
          diagnostico: storedDiagnosis.verdict,
          evidencias: stored.evidences.length,
          panel_historial: after.body?.history?.length ?? 0,
          workers_disponibles: liveWorkers.body?.available ?? false,
        },
        null,
        2,
      ),
    );
  } finally {
    await prisma.guardianWorkerHeartbeat
      .deleteMany({ where: { workerName: { in: ['alerts', 'diagnosis'] } } })
      .catch(() => undefined);
    if (!KEEP && companyId) {
      await prisma.company.deleteMany({ where: { id: companyId } }).catch(() => undefined);
    }
    await prisma.$disconnect();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }

  // eslint-disable-next-line no-console
  console.log(`\nRESULTADO INTEGRACIÓN E2E: ${failures === 0 ? 'GO' : `NO-GO (${failures} fallos)`}`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('[guardian-integration-e2e] fallo fatal', error);
  process.exit(1);
});
