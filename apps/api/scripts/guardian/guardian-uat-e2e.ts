/**
 * APPYRA Guardian AI — E2E de UAT sobre PostgreSQL real (proveedor simulado).
 *
 * Circuito: error -> cola local (simulada por el cliente) -> POST /guardian/incidents
 * -> incidente persistido -> alerta procesada (webhook simulado) -> diagnóstico IA
 * con evidencias -> consulta del panel.
 *
 * Requiere el API en ejecución apuntando a la base aislada de UAT:
 *   $env:DATABASE_URL='postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 *   $env:JWT_SECRET='guardian-uat-secret'; $env:PORT='4010'
 *   $env:GUARDIAN_ENABLED='true'; $env:GUARDIAN_INGEST_ENABLED='true'
 *   $env:GUARDIAN_DIAGNOSIS_ENABLED='true'; $env:GUARDIAN_ALERTS_ENABLED='true'
 *   $env:GUARDIAN_ALERT_RECIPIENT='18095550000'
 *   npm --workspace apps/api run start:dev
 *
 * Y luego:
 *   npm --workspace apps/api run guardian:e2e
 */
import http from 'node:http';
import jwt from 'jsonwebtoken';
import { PrismaClient } from '@prisma/client';
import { GuardianDiagnosisService } from '../../src/guardian/guardian.diagnosis.service';
import { GuardianToolsService } from '../../src/guardian/guardian.tools.service';
import { GuardianAlertService } from '../../src/guardian/guardian.alert.service';
import { GuardianIncidentsService } from '../../src/guardian/guardian.incidents.service';
import { HttpWebhookChannel } from '../../src/guardian/guardian.alert.channels';
import { MockGuardianAiProvider } from '../../src/guardian/ai/mock-guardian-ai.provider';

const DATABASE_URL = process.env.DATABASE_URL ?? '';
const API_BASE = (process.env.GUARDIAN_E2E_API_BASE ?? 'http://127.0.0.1:4010').replace(/\/+$/, '');
const JWT_SECRET = process.env.JWT_SECRET ?? '';
const RUN_ID = `e2e${Date.now().toString(36)}`;
const WEBHOOK_PORT = 45_998;

let failures = 0;
function check(label: string, condition: boolean, detail?: unknown) {
  const status = condition ? 'PASS' : 'FAIL';
  if (!condition) failures += 1;
  // eslint-disable-next-line no-console
  console.log(`[${status}] ${label}${detail === undefined ? '' : ` :: ${JSON.stringify(detail).slice(0, 300)}`}`);
}

async function main() {
  if (!DATABASE_URL) throw new Error('DATABASE_URL es requerido (base UAT aislada)');
  if (!JWT_SECRET) throw new Error('JWT_SECRET es requerido para firmar el token de UAT');

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
      res.statusCode = 200;
      res.end('ok');
    });
  });
  await new Promise<void>((resolve) => server.listen(WEBHOOK_PORT, '127.0.0.1', resolve));

  try {
    // ---------- Semilla de UAT ----------
    const company = await prisma.company.create({
      data: {
        name: `Guardian E2E ${RUN_ID}`,
        slug: `guardian-e2e-${RUN_ID}`,
        licenseStatus: 'TRIAL',
        trialEndsAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
      select: { id: true, name: true },
    });
    const otherCompany = await prisma.company.create({
      data: {
        name: `Guardian E2E Otro ${RUN_ID}`,
        slug: `guardian-e2e-otro-${RUN_ID}`,
        licenseStatus: 'TRIAL',
        trialEndsAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      },
      select: { id: true },
    });
    const user = await prisma.user.create({
      data: {
        companyId: company.id,
        email: `guardian-e2e-${RUN_ID}@uat.local`,
        passwordHash: 'uat-not-a-real-hash',
        nombreCompleto: 'Guardian UAT',
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
        refreshTokenHash: `uat-${RUN_ID}`,
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

    // ---------- 1. Ingesta por HTTP ----------
    const eventId = `evt-e2e-${RUN_ID}`;
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
          deviceId: `dev-e2e-${RUN_ID}`,
          occurredAt: new Date().toISOString(),
          message: 'fallo al cerrar turno con cliente juan@example.com',
          stack: 'Error: cierre\n    at GuardianIngestService.ingestBatch (guardian.ingest.service.ts:120:9)',
          context: { password: 'no-debe-verse', saleId: 'abc' },
        },
      ],
    };

    const startedAt = Date.now();
    const response = await fetch(`${API_BASE}/guardian/incidents`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(payload),
    });
    const body: any = await response.json().catch(() => ({}));
    const persistMs = Date.now() - startedAt;

    check('HTTP 202 en la ingesta', response.status === 202, response.status);
    check('evento aceptado', body?.accepted === 1, body?.results?.[0]);
    check(
      'requestId de correlación en la respuesta',
      Boolean(response.headers.get('x-request-id')),
      response.headers.get('x-request-id'),
    );

    const incidentId = body?.results?.[0]?.incidentId as string | undefined;
    check('incidentId devuelto', Boolean(incidentId), incidentId);

    // ---------- 2. Idempotencia (10 reenvíos) ----------
    let duplicates = 0;
    for (let attempt = 0; attempt < 10; attempt += 1) {
      const resend = await fetch(`${API_BASE}/guardian/incidents`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify(payload),
      });
      const resendBody: any = await resend.json().catch(() => ({}));
      duplicates += Number(resendBody?.duplicates ?? 0);
    }
    const storedCount = await prisma.guardianIncident.count({
      where: { companyId: company.id, eventId },
    });
    check('10 reenvíos = 10 duplicados y 1 fila', duplicates === 10 && storedCount === 1, {
      duplicates,
      storedCount,
    });

    // ---------- 3. Evidencia redactada ----------
    const stored = await prisma.guardianIncident.findFirstOrThrow({
      where: { companyId: company.id, eventId },
      include: { evidences: true },
    });
    const serialized = JSON.stringify(stored);
    check('no se guardó la contraseña', !serialized.includes('no-debe-verse'));
    check('no se guardó el correo del cliente', !serialized.includes('juan@example.com'));

    // ---------- 4. Alerta administrativa 24/7 ----------
    const alerts = new GuardianAlertService(prisma as any, {
      enqueueWhatsAppRawText: async () => ({ id: 'outbox-uat' }),
    } as any);
    const planned = await prisma.guardianAlert.findFirst({
      where: { incidentId: stored.id, kind: 'initial' },
    });
    check('alerta inicial planificada durante la ingesta', Boolean(planned), planned?.state);

    const webhook = new HttpWebhookChannel({ url: `http://127.0.0.1:${WEBHOOK_PORT}/guardian` });
    const alertStartedAt = Date.now();
    const attemptOutcome = planned ? await alerts.attempt(planned.id, [webhook]) : { ok: false };
    const alertMs = Date.now() - alertStartedAt;
    check('alerta enviada por el canal simulado', (attemptOutcome as any).ok === true, attemptOutcome);
    check('proveedor simulado recibió el mensaje', received.length === 1, received.length);
    check(
      'mensaje comprensible para administración',
      Boolean(received[0]?.text?.includes('APPYRA GUARDIAN')) &&
        Boolean(received[0]?.text?.includes(company.name)) &&
        Boolean(received[0]?.text?.includes('No se modificó información del cliente.')),
      received[0]?.text?.split('\n').slice(0, 3),
    );

    // ---------- 5. Diagnóstico con evidencias ----------
    const diagnosis = new GuardianDiagnosisService(
      prisma as any,
      new GuardianToolsService(prisma as any),
      new MockGuardianAiProvider(),
    );
    const diagnosisOutcome = await diagnosis.diagnose(stored.id);
    check('diagnóstico ejecutado', diagnosisOutcome.ok === true, diagnosisOutcome);

    const storedDiagnosis = await prisma.guardianDiagnosis.findFirstOrThrow({
      where: { incidentId: stored.id, status: 'DONE' },
      orderBy: { createdAt: 'desc' },
    });
    const refs = storedDiagnosis.evidenceRefs as unknown[];
    check('diagnóstico con evidencia verificable', Array.isArray(refs) && refs.length > 0, refs?.length);
    check(
      'veredicto válido (3 estados)',
      ['CONFIRMED', 'PROBABLE', 'INSUFFICIENT'].includes(String(storedDiagnosis.verdict)),
      storedDiagnosis.verdict,
    );

    // ---------- 6. Panel administrativo + aislamiento ----------
    const incidents = new GuardianIncidentsService(prisma as any);
    const list = await incidents.list({ companyId: company.id });
    check('el panel lista el incidente', list.items.some((item) => item.id === stored.id), list.items.length);

    const detail = await incidents.detail(company.id, stored.id);
    check(
      'el detalle incluye evidencias, diagnóstico e historial',
      detail.evidences.length > 0 && detail.diagnoses.length > 0 && detail.history.length > 0,
      {
        evidences: detail.evidences.length,
        diagnoses: detail.diagnoses.length,
        history: detail.history.length,
      },
    );

    const summary = await incidents.summary(company.id);
    check('el resumen cuenta incidentes', summary.total >= 1, summary);

    let crossTenantBlocked = false;
    try {
      await incidents.detail(otherCompany.id, stored.id);
    } catch {
      crossTenantBlocked = true;
    }
    check('otra empresa no puede ver el incidente', crossTenantBlocked);

    // ---------- 7. Métricas ----------
    // eslint-disable-next-line no-console
    console.log('\n--- MÉTRICAS UAT ---');
    // eslint-disable-next-line no-console
    console.log(
      JSON.stringify(
        {
          persistencia_ms: persistMs,
          alerta_primer_intento_ms: alertMs,
          duplicados_detectados: duplicates,
          incidentes_en_bd: storedCount,
          evidencias: detail.evidences.length,
          veredicto: String(storedDiagnosis.verdict),
          refs_evidencia: refs.length,
          alerta_estado_final: (
            await prisma.guardianAlert.findFirstOrThrow({ where: { incidentId: stored.id, kind: 'initial' } })
          ).state,
        },
        null,
        2,
      ),
    );
  } finally {
    await prisma.company.deleteMany({ where: { slug: { startsWith: 'guardian-e2e-' } } });
    await prisma.$disconnect();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }

  // eslint-disable-next-line no-console
  console.log(`\nRESULTADO E2E: ${failures === 0 ? 'GO (todas las comprobaciones OK)' : `NO-GO (${failures} fallos)`}`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error('[guardian-e2e] fallo fatal', error);
  process.exit(1);
});
