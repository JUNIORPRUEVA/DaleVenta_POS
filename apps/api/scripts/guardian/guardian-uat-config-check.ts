/**
 * APPYRA Guardian AI — validador de configuración UAT.
 *
 * Comprueba que un archivo de entorno privado contiene lo que el código real
 * necesita, SIN imprimir valores. Solo emite nombres, booleanos y conteos.
 *
 * Uso:
 *   GUARDIAN_ENV_FILE=C:\Users\<usuario>\.guardian-uat\fullpos-backend.env \
 *     npx ts-node --transpile-only -P tsconfig.scripts.json scripts/guardian/guardian-uat-config-check.ts
 *
 * No hace peticiones a Meta ni a DeepSeek. No escribe nada.
 */
import * as fs from 'node:fs';
import * as dotenv from 'dotenv';
import { resolveGuardianWhatsAppProfile } from '../../src/guardian/guardian.whatsapp.config';
import { describeGuardianAiRuntime } from '../../src/guardian/guardian.config';
import { OpenAiGuardianAiProvider } from '../../src/guardian/ai/openai-guardian-ai.provider';

const AI_KEYS = ['GUARDIAN_AI_API_KEY', 'GUARDIAN_AI_BASE_URL', 'GUARDIAN_AI_MODEL'];
const WA_IDENTITY = ['GUARDIAN_WA_CLOUD_TOKEN', 'GUARDIAN_WA_PHONE_NUMBER_ID', 'GUARDIAN_WA_WABA_ID'];

/** Requisitos reales por proceso (ver guardian.module/webhook/scripts). */
const PROFILE_REQUIRED: Record<string, string[]> = {
  api: [
    ...WA_IDENTITY,
    'GUARDIAN_WA_APP_SECRET',
    'GUARDIAN_WA_VERIFY_TOKEN',
    ...AI_KEYS,
    'GUARDIAN_PLATFORM_TOKEN',
  ],
  workers: [...WA_IDENTITY, ...AI_KEYS],
  // El script lanza si falta la cadena de conexion, aunque admite 3 fallbacks.
  watchdog: ['GUARDIAN_WATCHDOG_WEBHOOK_TOKEN', 'GUARDIAN_WATCHDOG_DATABASE_URL'],
  // Proxy de Appyra: solo habla con el backend Guardian, nunca con Meta ni IA.
  appyra: ['GUARDIAN_API_BASE_URL', 'GUARDIAN_PLATFORM_TOKEN'],
};

const REQUIRED = PROFILE_REQUIRED.api;

/** `--profile=api|workers|watchdog` (por defecto `api`). */
function resolveProfileName(): string {
  const arg = process.argv.find((value) => value.startsWith('--profile='));
  const name = arg ? arg.split('=')[1] : 'api';
  return PROFILE_REQUIRED[name] ? name : 'api';
}

const OPTIONAL_WITH_DEFAULT = [
  'GUARDIAN_WA_TEMPLATE_NAME',
  'GUARDIAN_WA_TEMPLATE_LANG',
  'GUARDIAN_ALERT_RECIPIENTS',
];

function main(): void {
  const envFile = String(process.env.GUARDIAN_ENV_FILE ?? '').trim();
  if (!envFile || !fs.existsSync(envFile)) {
    console.log(JSON.stringify({ ok: false, reason: 'ENV_FILE_NOT_FOUND' }));
    process.exitCode = 1;
    return;
  }

  // `override: true` para que el archivo privado mande sobre el entorno actual.
  dotenv.config({ path: envFile, override: true, quiet: true });

  const profileName = resolveProfileName();
  const required = PROFILE_REQUIRED[profileName];
  const missing = required.filter((key) => !String(process.env[key] ?? '').trim());  const emptyOrMissingOptional = OPTIONAL_WITH_DEFAULT.filter(
    (key) => !String(process.env[key] ?? '').trim(),
  );

  const profile = resolveGuardianWhatsAppProfile();
  const ai = new OpenAiGuardianAiProvider({
    apiKey: String(process.env.GUARDIAN_AI_API_KEY ?? ''),
    baseUrl: process.env.GUARDIAN_AI_BASE_URL,
    model: process.env.GUARDIAN_AI_MODEL,
    timeoutMs: Number(process.env.GUARDIAN_AI_TIMEOUT_MS ?? 20_000),
    maxTokens: Number(process.env.GUARDIAN_AI_MAX_TOKENS ?? 900),
    maxConcurrent: Number(process.env.GUARDIAN_AI_MAX_CONCURRENCY ?? 1),
  });

  let aiHost = 'n/a';
  try {
    aiHost = new URL(String(process.env.GUARDIAN_AI_BASE_URL ?? '')).host;
  } catch {
    aiHost = 'URL_INVALIDA';
  }

  const modelName = String(process.env.GUARDIAN_AI_MODEL ?? '');
  const platformTokenLength = String(process.env.GUARDIAN_PLATFORM_TOKEN ?? '').length;

  console.log(
    JSON.stringify(
      {
        profile: profileName,
        ok: missing.length === 0,
        missing,
        optionalWithCodeDefault: emptyOrMissingOptional,
        whatsapp: {
          provider: profile.provider,
          canSend: profile.canSend,
          blockedReason: profile.blockedReason,
          adminRecipientCount: profile.adminRecipients.length,
          recipientLengthsValid: profile.adminRecipients.every(
            (value) => value.length >= 8 && value.length <= 15,
          ),
          wabaPresent: Boolean(profile.sender.wabaId),
          phoneNumberIdDigits: /^\d+$/.test(String(profile.sender.phoneNumberId ?? '')),
          apiVersion: profile.sender.apiVersion,
          apiVersionDefault: profile.sender.apiVersion === 'v21.0',
          templateNameIsCodeDefault: profile.templates.incidentAlert.name === 'guardian_incident_alert',
          templateLanguage: profile.templates.incidentAlert.language,
          templateParamCount: profile.templates.incidentAlert.paramCount,
          watchdogTemplateUsesCodeDefault:
            profile.templates.watchdogAlert.name === 'guardian_watchdog_alert',
          watchdogParamCount: profile.templates.watchdogAlert.paramCount,
        },
        ai: {
          adapter: describeGuardianAiRuntime().adapter,
          providerVariableHonored: describeGuardianAiRuntime().providerVariableHonored,
          warnings: describeGuardianAiRuntime().warnings,
          compatibleOpenAiStyle: true,
          isConfigured: ai.isConfigured(),
          host: aiHost,
          modelLength: modelName.length,
          modelFormatPlausible: /^[a-z0-9][a-z0-9._-]*$/i.test(modelName),
          timeoutMs: Number(process.env.GUARDIAN_AI_TIMEOUT_MS ?? 20_000),
          maxTokens: Number(process.env.GUARDIAN_AI_MAX_TOKENS ?? 900),
        },
        platformToken: {
          present: platformTokenLength > 0,
          lengthAtLeast32: platformTokenLength >= 32,
        },
      },
      null,
      2,
    ),
  );

  if (missing.length > 0) process.exitCode = 1;
}

main();

