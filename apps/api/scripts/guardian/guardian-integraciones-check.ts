/**
 * APPYRA Guardian AI — validador de configuración de integraciones externas.
 *
 * Comprueba, SIN llamar a ningún proveedor y SIN tocar la base de datos, si el
 * entorno está listo para la primera prueba real de WhatsApp Cloud API y
 * DeepSeek. Nunca imprime credenciales: solo presencia, host y modelo.
 *
 * Uso:
 *   npm --workspace apps/api run guardian:integraciones-check
 *   npm --workspace apps/api run guardian:integraciones-check -- --json
 *
 * Códigos de salida:
 *   0 = listo (todas las piezas presentes y coherentes)
 *   2 = faltan piezas externas (no es un error del código)
 *   3 = configuración incoherente (revisar antes de cualquier prueba)
 *
 * Nota: este script NO envía WhatsApp, NO consume DeepSeek y NO escribe en la
 * base. La prueba real tiene su propio procedimiento documentado en
 * `docs/guardian/WHATSAPP_DEEPSEEK_ACCEPTANCE.md`.
 */
import { resolveGuardianAiRuntime, describeGuardianAiRuntime } from '../../src/guardian/ai/guardian.ai.runtime';
import {
  GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS,
  resolveGuardianWhatsAppProfile,
} from '../../src/guardian/guardian.whatsapp.config';
import { resolveGuardianSecret } from '../../src/guardian/guardian.secret';

type Check = {
  key: string;
  ok: boolean;
  detail: string;
  /** `external` = falta una pieza que solo puede aportar el responsable. */
  kind: 'code' | 'external' | 'config';
};

function has(env: NodeJS.ProcessEnv, name: string): boolean {
  return String(env[name] ?? '').trim().length > 0;
}

/**
 * Presencia de una credencial admitiendo `NAME` o `NAME_FILE` (Docker Secrets).
 * Devuelve además el origen para que el informe diga de dónde salió el valor.
 */
function secretOrigin(env: NodeJS.ProcessEnv, name: string): string {
  const resolved = resolveGuardianSecret(env, name);
  if (resolved.source === 'env') return `${name} presente (variable)`;
  if (resolved.source === 'file') return `${name} presente (archivo de secreto)`;
  return resolved.problem ?? `${name} ausente`;
}

function hasSecret(env: NodeJS.ProcessEnv, name: string): boolean {
  return resolveGuardianSecret(env, name).value.length > 0;
}

function buildChecks(env: NodeJS.ProcessEnv): Check[] {
  const checks: Check[] = [];
  const profile = resolveGuardianWhatsAppProfile(env);
  const ai = resolveGuardianAiRuntime(env);

  // ---------- Proveedor de IA ----------
  checks.push({
    key: 'ai.deepseek.selected',
    ok: ai.adapter === 'deepseek',
    detail:
      ai.adapter === 'deepseek'
        ? `adaptador=${ai.adapter} host=${ai.baseUrlHost} modelo=${ai.model}`
        : `adaptador efectivo=${ai.adapter} (se esperaba deepseek)`,
    kind: ai.adapter === 'deepseek' ? 'code' : 'external',
  });

  checks.push({
    key: 'ai.api_key',
    ok: ai.apiKeyPresent,
    detail: ai.apiKeyPresent ? 'GUARDIAN_AI_API_KEY presente (valor no mostrado)' : 'falta GUARDIAN_AI_API_KEY',
    kind: 'external',
  });

  checks.push({
    key: 'ai.model_supported',
    ok: ai.modelSupported,
    detail: ai.modelSupported ? `modelo admitido: ${ai.model}` : `modelo no admitido: ${ai.model}`,
    kind: ai.modelSupported ? 'code' : 'config',
  });

  checks.push({
    key: 'ai.configuration_errors',
    ok: ai.errors.length === 0,
    detail: ai.errors.length ? ai.errors.join(', ') : 'sin errores de configuración',
    kind: 'config',
  });

  // ---------- WhatsApp Cloud API ----------
  checks.push({
    key: 'wa.sender',
    ok: profile.provider === 'meta_cloud',
    detail:
      profile.provider === 'meta_cloud'
        ? `phone_number_id presente=${has(env, 'GUARDIAN_WA_PHONE_NUMBER_ID')} waba presente=${Boolean(profile.sender.wabaId)}`
        : 'faltan GUARDIAN_WA_CLOUD_TOKEN y/o GUARDIAN_WA_PHONE_NUMBER_ID',
    kind: profile.provider === 'meta_cloud' ? 'code' : 'external',
  });

  checks.push({
    key: 'wa.app_secret',
    ok: hasSecret(env, 'GUARDIAN_WA_APP_SECRET'),
    detail: hasSecret(env, 'GUARDIAN_WA_APP_SECRET')
      ? `${secretOrigin(env, 'GUARDIAN_WA_APP_SECRET')} (el webhook validará la firma)`
      : 'sin GUARDIAN_WA_APP_SECRET el webhook responde 503 (fail-closed)',
    kind: 'external',
  });

  checks.push({
    key: 'wa.verify_token',
    ok: hasSecret(env, 'GUARDIAN_WA_VERIFY_TOKEN'),
    detail: hasSecret(env, 'GUARDIAN_WA_VERIFY_TOKEN')
      ? secretOrigin(env, 'GUARDIAN_WA_VERIFY_TOKEN')
      : 'sin GUARDIAN_WA_VERIFY_TOKEN Meta no puede verificar el webhook (403)',
    kind: 'external',
  });

  checks.push({
    key: 'wa.recipients',
    ok: profile.adminRecipients.length > 0,
    detail:
      profile.adminRecipients.length > 0
        ? `${profile.adminRecipients.length} destinatario(s) administrativo(s) válido(s)`
        : 'falta GUARDIAN_ALERT_RECIPIENTS con al menos un número E.164',
    kind: 'external',
  });

  checks.push({
    key: 'wa.template',
    ok: profile.templates.incidentAlert.paramCount === GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS.length,
    detail:
      `plantilla=${profile.templates.incidentAlert.name} idioma=${profile.templates.incidentAlert.language} ` +
      `categoría=${profile.templates.incidentAlert.category} parámetros=${profile.templates.incidentAlert.paramCount}`,
    kind: 'code',
  });

  checks.push({
    key: 'wa.template_name_explicit',
    ok: has(env, 'GUARDIAN_WA_TEMPLATE_NAME'),
    detail: has(env, 'GUARDIAN_WA_TEMPLATE_NAME')
      ? 'GUARDIAN_WA_TEMPLATE_NAME definido explícitamente'
      : 'se usa el valor por defecto guardian_incident_alert',
    kind: 'external',
  });

  checks.push({
    key: 'wa.can_send',
    ok: profile.canSend,
    detail: profile.canSend ? 'remitente y destinatarios listos' : `bloqueado: ${profile.blockedReason}`,
    kind: profile.canSend ? 'code' : 'external',
  });

  checks.push({
    key: 'wa.no_cross_product_credentials',
    ok: !has(env, 'META_WA_TOKEN') && !has(env, 'EVOLUTION_API_KEY'),
    detail:
      has(env, 'META_WA_TOKEN') || has(env, 'EVOLUTION_API_KEY')
        ? 'hay credenciales de otro producto en el entorno: no deben usarse para Guardian'
        : 'sin credenciales heredadas de otros productos',
    kind: 'config',
  });

  // ---------- Guardian activo ----------
  checks.push({
    key: 'guardian.enabled',
    ok: /^(1|true|yes|on)$/i.test(String(env.GUARDIAN_ENABLED ?? '').trim()),
    detail: `GUARDIAN_ENABLED=${String(env.GUARDIAN_ENABLED ?? '(sin definir)')}`,
    kind: 'config',
  });

  return checks;
}

function main() {
  const asJson = process.argv.includes('--json');
  const checks = buildChecks(process.env);
  const external = checks.filter((check) => !check.ok && check.kind === 'external');
  const broken = checks.filter((check) => !check.ok && check.kind !== 'external');
  const aiRuntime = resolveGuardianAiRuntime();

  const report = {
    generatedAt: new Date().toISOString(),
    aiRuntime: describeGuardianAiRuntime(aiRuntime),
    aiWarnings: aiRuntime.warnings,
    checks,
    readyForFirstRealTest: external.length === 0 && broken.length === 0,
    pendingExternal: external.map((check) => check.key),
    configurationErrors: broken.map((check) => check.key),
  };

  if (asJson) {
    // eslint-disable-next-line no-console
    console.log(JSON.stringify(report, null, 2));
  } else {
    // eslint-disable-next-line no-console
    console.log('APPYRA Guardian — verificación de integraciones externas\n');
    for (const check of checks) {
      const status = check.ok ? 'OK  ' : check.kind === 'external' ? 'PEND' : 'FALLA';
      // eslint-disable-next-line no-console
      console.log(`[${status}] ${check.key.padEnd(34)} ${check.detail}`);
    }
    // eslint-disable-next-line no-console
    console.log('\nResumen:');
    // eslint-disable-next-line no-console
    console.log(`  IA efectiva          : ${report.aiRuntime}`);
    // eslint-disable-next-line no-console
    console.log(`  Listo para prueba real: ${report.readyForFirstRealTest ? 'SÍ' : 'NO'}`);
    if (report.pendingExternal.length) {
      // eslint-disable-next-line no-console
      console.log(`  Pendiente externo     : ${report.pendingExternal.join(', ')}`);
    }
    if (report.configurationErrors.length) {
      // eslint-disable-next-line no-console
      console.log(`  Errores de configuración: ${report.configurationErrors.join(', ')}`);
    }
    for (const warning of aiRuntime.warnings) {
      // eslint-disable-next-line no-console
      console.log(`  Aviso IA              : ${warning}`);
    }
    // eslint-disable-next-line no-console
    console.log('\nEste script no envía WhatsApp ni consume DeepSeek.');
  }

  if (broken.length) process.exitCode = 3;
  else if (external.length) process.exitCode = 2;
  else process.exitCode = 0;
}

main();
