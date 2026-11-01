#!/usr/bin/env node
/**
 * Validación de configuración de APPYRA Guardian AI para el despliegue de
 * auto-enrolamiento. **Solo lectura**: no cambia nada, solo informa.
 *
 * Uso:
 *   docker service inspect daleventapos_backend \
 *     --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' \
 *     | node scripts/guardian/validate-guardian-config.cjs --phase 0
 *
 * Salida: líneas PASS / FAIL / WARN y código de salida 1 si hay algún FAIL.
 */
const { stdin } = process;

const args = process.argv.slice(2);
const phaseArg = args.find((a) => a.startsWith('--phase'));
const phase = Number.parseInt(
  (phaseArg && (phaseArg.split('=')[1] ?? args[args.indexOf(phaseArg) + 1])) || '0',
  10,
);

function readEnvFromStdin() {
  return new Promise((resolve) => {
    let data = '';
    if (stdin.isTTY) return resolve({});
    stdin.setEncoding('utf8');
    stdin.on('data', (chunk) => (data += chunk));
    stdin.on('end', () => {
      const env = {};
      for (const line of data.split(/\r?\n/)) {
        const match = /^([A-Z0-9_]+)=(.*)$/.exec(line.trim());
        if (match) env[match[1]] = match[2];
      }
      resolve(env);
    });
  });
}

const results = [];
function record(level, name, detail) {
  results.push({ level, name, detail });
  console.log(`${level.padEnd(4)} | ${name}${detail ? ' | ' + detail : ''}`);
}

function expect(env, key, wanted, { required = true } = {}) {
  const value = env[key];
  if (value === undefined || value === '') {
    record(required ? 'FAIL' : 'WARN', `${key} definido`, 'no configurado');
    return false;
  }
  if (wanted !== undefined && String(value) !== String(wanted)) {
    record('WARN', `${key} == ${wanted}`, `valor actual: ${value}`);
    return false;
  }
  record('PASS', `${key}`, value);
  return true;
}

function numericAtLeast(env, key, min) {
  const raw = env[key];
  if (raw === undefined) {
    record('WARN', `${key} >= ${min}`, 'no configurado (se usa el valor por defecto)');
    return;
  }
  const value = Number.parseInt(raw, 10);
  if (!Number.isFinite(value)) {
    record('FAIL', `${key} numérico`, `valor no numérico: ${raw}`);
    return;
  }
  if (value < min) {
    record('FAIL', `${key} >= ${min}`, `valor actual: ${value}`);
    return;
  }
  record('PASS', `${key} >= ${min}`, `${value}`);
}

(async () => {
  const env = await readEnvFromStdin();
  const keys = Object.keys(env);
  if (keys.length === 0) {
    console.error('No se recibió ninguna variable por stdin (KEY=VALUE).');
    process.exit(2);
  }
  console.log(`== Validación de configuración Guardian (fase ${phase}, ${keys.length} variables) ==`);

  // 1. Base de Guardian
  expect(env, 'GUARDIAN_ENABLED', 'true');
  // `GUARDIAN_INGEST_ENABLED` hereda de `GUARDIAN_ENABLED` cuando no se define,
  // así que su ausencia se informa como advertencia, no como fallo.
  if (String(env.GUARDIAN_INGEST_ENABLED ?? '').trim() === '') {
    record(
      'WARN',
      'GUARDIAN_INGEST_ENABLED definido',
      `no configurado; hereda GUARDIAN_ENABLED=${env.GUARDIAN_ENABLED ?? 'n/d'}`,
    );
  } else {
    expect(env, 'GUARDIAN_INGEST_ENABLED', 'true');
  }

  // 2. Diagnóstico real (bloqueante para dar valor al producto)
  expect(env, 'GUARDIAN_DIAGNOSIS_ENABLED', 'true');
  const provider = String(env.GUARDIAN_AI_PROVIDER ?? '').trim().toLowerCase();
  if (provider === 'deepseek') record('PASS', 'GUARDIAN_AI_PROVIDER', provider);
  else record('FAIL', 'GUARDIAN_AI_PROVIDER == deepseek', `valor actual: ${provider || 'no configurado'}`);

  // 3. Credencial de IA presente (admite *_FILE de Docker Secrets)
  const hasKey =
    Boolean(String(env.GUARDIAN_AI_API_KEY ?? '').trim()) ||
    Boolean(String(env.GUARDIAN_AI_API_KEY_FILE ?? '').trim());
  record(hasKey ? 'PASS' : 'FAIL', 'credencial de IA configurada', hasKey ? 'presente' : 'ausente');

  // 4. Sin cuotas de tokens (fueron retiradas deliberadamente)
  const leftover = keys.filter((key) => /^GUARDIAN_AI_TOKENS_/.test(key));
  if (leftover.length === 0) record('PASS', 'sin cuotas de tokens', 'ninguna variable GUARDIAN_AI_TOKENS_*');
  else record('WARN', 'variables de cuota obsoletas', leftover.join(', ') + ' (ya no se aplican)');

  // 5. Salvaguardas que deben permanecer
  numericAtLeast(env, 'GUARDIAN_AI_MAX_CONCURRENCY', 1);
  numericAtLeast(env, 'GUARDIAN_DIAGNOSIS_MAX_ATTEMPTS', 1);

  // 6. Alertas administrativas centralizadas (WhatsApp)
  const recipients = String(
    env.GUARDIAN_ALERT_RECIPIENTS ?? env.GUARDIAN_ALERT_RECIPIENT ?? '',
  ).trim();
  record(
    recipients ? 'PASS' : 'FAIL',
    'destinatarios administrativos',
    recipients ? `${recipients.split(/[,;]+/).filter(Boolean).length} destinatario(s)` : 'sin configurar',
  );
  const waToken =
    Boolean(String(env.GUARDIAN_WA_CLOUD_TOKEN ?? '').trim()) ||
    Boolean(String(env.GUARDIAN_WA_CLOUD_TOKEN_FILE ?? '').trim());
  record(waToken ? 'PASS' : 'FAIL', 'token de WhatsApp Cloud', waToken ? 'presente' : 'ausente');
  record(
    String(env.GUARDIAN_WA_PHONE_NUMBER_ID ?? '').trim() ? 'PASS' : 'FAIL',
    'GUARDIAN_WA_PHONE_NUMBER_ID',
    env.GUARDIAN_WA_PHONE_NUMBER_ID ?? 'no configurado',
  );
  if (String(env.GUARDIAN_WA_BILLING_TEMPLATE_NAME ?? '').trim()) {
    record('PASS', 'plantilla de aviso de facturación', env.GUARDIAN_WA_BILLING_TEMPLATE_NAME);
  } else {
    record(
      'WARN',
      'plantilla de aviso de facturación',
      'no configurada: se usará guardian_billing_alert (debe estar aprobada en Meta)',
    );
  }

  // 7. Saldo de IA
  numericAtLeast(env, 'GUARDIAN_AI_BALANCE_CHECK_MINUTES', 5);

  // 8. Auto-enrolamiento
  if (phase <= 0) {
    const enabled = String(env.GUARDIAN_AUTO_ENROLL_ENABLED ?? '').trim().toLowerCase();
    if (enabled === '' || ['0', 'false', 'no', 'off'].includes(enabled)) {
      record('PASS', 'auto-enrolamiento inerte en fase 0', enabled || 'no definido');
    } else {
      record('FAIL', 'auto-enrolamiento inerte en fase 0', `valor actual: ${enabled}`);
    }
  } else {
    expect(env, 'GUARDIAN_AUTO_ENROLL_ENABLED', 'true');
    const companies = String(env.GUARDIAN_AUTO_ENROLL_COMPANIES ?? '').trim();
    if (!companies) record('FAIL', 'lista de empresas autorizadas', 'vacía: nadie se auto-enrolaría');
    else if (companies === '*') record('WARN', 'lista de empresas autorizadas', '* (todas) — solo para la fase final');
    else record('PASS', 'lista de empresas autorizadas', `${companies.split(',').filter(Boolean).length} empresa(s)`);
    numericAtLeast(env, 'GUARDIAN_MAX_INSTALLATIONS_PER_COMPANY', 10);
  }

  const failed = results.filter((r) => r.level === 'FAIL').length;
  const warned = results.filter((r) => r.level === 'WARN').length;
  console.log(`\nRESUMEN: ${results.length - failed - warned} PASS, ${warned} WARN, ${failed} FAIL`);
  process.exit(failed > 0 ? 1 : 0);
})();
