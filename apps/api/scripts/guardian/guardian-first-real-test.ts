/**
 * APPYRA Guardian AI — PRIMERA PRUEBA REAL (WhatsApp Cloud API + DeepSeek).
 *
 * ⚠️ Este script SÍ puede generar tráfico real:
 *   - 1 llamada a DeepSeek (diagnóstico sintético, sin datos de clientes).
 *   - 1 envío de plantilla WhatsApp al número administrativo autorizado.
 *
 * Por eso es fail-closed: sin el flag explícito `--confirm-first-real-test`
 * termina sin hacer nada. Además:
 *   - Exige que el destinatario esté en `GUARDIAN_ALERT_RECIPIENTS`
 *     (lista de autorizados); no acepta números ad-hoc.
 *   - Envía como máximo UN mensaje por ejecución (no hay bucles).
 *   - No escribe en la base de datos ni modifica empresas, ventas ni caja.
 *   - No imprime credenciales ni el cuerpo completo de la respuesta.
 *
 * Uso (SOLO con autorización explícita del responsable):
 *   npm --workspace apps/api run guardian:first-real-test -- --confirm-first-real-test
 *   npm --workspace apps/api run guardian:first-real-test -- --confirm-first-real-test --skip-whatsapp
 *   npm --workspace apps/api run guardian:first-real-test -- --confirm-first-real-test --skip-ai
 *
 * Procedimiento completo: `docs/guardian/WHATSAPP_DEEPSEEK_ACCEPTANCE.md`.
 */
import { GuardianDiagnosisVerdict, GuardianSeverity } from '@prisma/client';
import { OpenAiGuardianAiProvider } from '../../src/guardian/ai/openai-guardian-ai.provider';
import { resolveGuardianAiRuntime } from '../../src/guardian/ai/guardian.ai.runtime';
import type { GuardianAiRequest } from '../../src/guardian/ai/guardian-ai.provider';
import { WhatsAppCloudChannel } from '../../src/guardian/guardian.alert.channels';
import { buildGuardianAlertTemplateParams } from '../../src/guardian/guardian.alert.service';
import {
  GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT,
  resolveGuardianWhatsAppProfile,
} from '../../src/guardian/guardian.whatsapp.config';

const CONFIRM_FLAG = '--confirm-first-real-test';

/** Incidente SINTÉTICO: no contiene datos de clientes ni de empresas reales. */
function syntheticIncident(): GuardianAiRequest {
  return {
    incident: {
      id: '00000000-0000-4000-8000-00000000e2e1',
      module: 'cash',
      operation: 'closeSession',
      severity: 'SEV1',
      exceptionType: 'CashCloseError',
      platform: 'windows',
      appVersion: '0.0.0-uat',
      occurredAt: new Date().toISOString(),
      message: 'Prueba de integración Guardian: el cierre de caja de un negocio sintético no completa el cálculo.',
      stack: 'at CashService.close (synthetic)',
      impactSummary: 'Turno sintético sin cerrar; ningún dato real fue tocado.',
    },
    similarIncidents: [],
    company: {
      id: '00000000-0000-4000-8000-0000000000e2',
      plan: 'UAT',
      licenseStatus: 'ACTIVE',
      createdAt: new Date().toISOString(),
    },
    businessFacts: { note: 'datos sintéticos de prueba' },
    codeMatches: [],
    versionTimeline: [],
  };
}

function usage(): void {
  // eslint-disable-next-line no-console
  console.log(
    [
      'PRIMERA PRUEBA REAL — no se ejecutó nada.',
      '',
      `Este script envía 1 mensaje real de WhatsApp y consume tokens de DeepSeek.`,
      `Para ejecutarlo hace falta el flag explícito: ${CONFIRM_FLAG}`,
      '',
      'Antes de ejecutarlo:',
      '  1. npm --workspace apps/api run guardian:integraciones-check',
      '  2. Confirmar que la plantilla guardian_incident_alert está APROBADA en Meta.',
      '  3. Confirmar que el destinatario está en GUARDIAN_ALERT_RECIPIENTS.',
      '  4. Revisar docs/guardian/WHATSAPP_DEEPSEEK_ACCEPTANCE.md.',
    ].join('\n'),
  );
}

async function runDeepSeekProbe(): Promise<{ ok: boolean; detail: string }> {
  const runtime = resolveGuardianAiRuntime();
  if (runtime.adapter === 'mock') {
    return {
      ok: false,
      detail: `proveedor mock (${runtime.errors.join(', ') || 'sin credencial'}) — no se llamó a DeepSeek`,
    };
  }

  const provider = new OpenAiGuardianAiProvider({
    apiKey: String(process.env.GUARDIAN_AI_API_KEY ?? '').trim(),
    baseUrl: runtime.baseUrl ?? undefined,
    model: runtime.model,
    timeoutMs: runtime.timeoutMs,
    maxTokens: runtime.maxTokens,
    maxConcurrent: 1,
    adapter: runtime.adapter,
  });

  const startedAt = Date.now();
  const result = await provider.analyze(syntheticIncident());
  const verdictOk =
    result.verdict === GuardianDiagnosisVerdict.CONFIRMED ||
    result.verdict === GuardianDiagnosisVerdict.PROBABLE ||
    result.verdict === GuardianDiagnosisVerdict.INSUFFICIENT;

  return {
    ok: verdictOk && result.tokensUsed > 0,
    detail:
      `adaptador=${runtime.adapter} modelo=${result.model} veredicto=${result.verdict} ` +
      `evidencia=${result.evidenceRefs.length} tokens=${result.tokensUsed} ms=${Date.now() - startedAt}`,
  };
}

async function runWhatsAppProbe(): Promise<{ ok: boolean; detail: string }> {
  const profile = resolveGuardianWhatsAppProfile();
  if (!profile.canSend) {
    return { ok: false, detail: `WhatsApp no configurado (${profile.blockedReason})` };
  }

  const recipient = profile.adminRecipients[0];
  if (!profile.adminRecipients.includes(recipient)) {
    return { ok: false, detail: 'el destinatario no está en la lista de autorizados' };
  }

  const params = buildGuardianAlertTemplateParams({
    severity: GuardianSeverity.SEV1,
    companyName: 'EMPRESA SINTÉTICA DE PRUEBA',
    module: 'caja',
    operation: 'cierre de sesión',
    occurredAt: new Date(),
    problem: 'Prueba de integración: incidente sintético, sin datos de clientes.',
    diagnosis: 'Verificación de canal; no corresponde a un incidente real.',
    impact: 'Ninguno: prueba controlada de una sola alerta.',
    incidentId: '00000000-0000-4000-8000-00000000e2e1',
  });

  if (params.length !== GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT) {
    return {
      ok: false,
      detail: `la plantilla espera ${GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT} parámetros y hay ${params.length}`,
    };
  }

  const channel = new WhatsAppCloudChannel({
    token: String(process.env.GUARDIAN_WA_CLOUD_TOKEN ?? '').trim(),
    phoneNumberId: profile.sender.phoneNumberId ?? '',
    apiVersion: profile.sender.apiVersion,
    templateName: profile.templates.incidentAlert.name,
    templateLanguage: profile.templates.incidentAlert.language,
  });

  // Un único envío: no hay reintentos ni bucles en la primera prueba.
  const result = await channel.send({
    to: recipient,
    text: 'Prueba de integración APPYRA Guardian (mensaje sintético).',
    dedupeKey: `first-real-test-${Date.now()}`,
    allowOutsideBusinessHours: true,
    templateName: profile.templates.incidentAlert.name,
    templateLanguage: profile.templates.incidentAlert.language,
    templateParams: params,
  });

  return {
    ok: result.ok && Boolean(result.providerMessageId),
    detail: result.ok
      ? `aceptado por Meta (mensaje=${result.providerMessageId}) — esperar webhook sent/delivered/read`
      : `fallo: ${result.error ?? 'sin detalle'} (clasificación ${result.classification ?? 'n/d'})`,
  };
}

async function main() {
  if (!process.argv.includes(CONFIRM_FLAG)) {
    usage();
    process.exitCode = 1;
    return;
  }

  const skipAi = process.argv.includes('--skip-ai');
  const skipWhatsApp = process.argv.includes('--skip-whatsapp');

  // eslint-disable-next-line no-console
  console.log(`Primera prueba real iniciada ${new Date().toISOString()}`);

  if (!skipAi) {
    const ai = await runDeepSeekProbe();
    // eslint-disable-next-line no-console
    console.log(`[${ai.ok ? 'OK' : 'FALLA'}] DeepSeek: ${ai.detail}`);
    if (!ai.ok) process.exitCode = 2;
  }

  if (!skipWhatsApp) {
    const wa = await runWhatsAppProbe();
    // eslint-disable-next-line no-console
    console.log(`[${wa.ok ? 'OK' : 'FALLA'}] WhatsApp: ${wa.detail}`);
    if (!wa.ok) process.exitCode = 3;
  }

  // eslint-disable-next-line no-console
  console.log(
    'Siguiente paso: verificar el estado de entrega en el panel APPYRA (#/admin/guardian) ' +
      'y en el historial de intentos de la alerta. Registrar el resultado sin secretos.',
  );
}

main().catch((error) => {
  // eslint-disable-next-line no-console
  console.error(`Primera prueba real falló: ${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 4;
});
