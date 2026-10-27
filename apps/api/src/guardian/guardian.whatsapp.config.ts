/**
 * APPYRA Guardian AI — identidad del remitente oficial de WhatsApp.
 *
 * Separación explícita exigida por la arquitectura:
 * - Proveedor (Meta Cloud API, y en el futuro otros).
 * - Identidad del remitente (WABA, Phone Number ID, número visible).
 * - Plantillas HSM (nombre, idioma, número de parámetros).
 * - Destinatarios administrativos.
 *
 * Regla dura: Guardian SOLO usa credenciales propias (`GUARDIAN_WA_*`).
 * Nunca hereda el número comercial ni los tokens Meta de otros productos
 * (por ejemplo el WhatsApp de Phytoemagry): reutilizarlos mezclaría la
 * identidad de dos negocios y rompería el aislamiento.
 */

export type GuardianWhatsAppProvider = 'meta_cloud' | 'none';

export type GuardianWhatsAppSender = {
  provider: GuardianWhatsAppProvider;
  wabaId: string | null;
  phoneNumberId: string | null;
  /** Número visible del remitente (E.164). No es un secreto. */
  displayNumber: string | null;
  displayName: string;
  apiVersion: string;
  /** Solo indica presencia; el token nunca sale de la capa de canal. */
  tokenPresent: boolean;
};

export type GuardianWhatsAppTemplate = {
  key: string;
  name: string;
  language: string;
  category: 'UTILITY';
  paramCount: number;
  description: string;
};

export type GuardianWhatsAppProfile = {
  provider: GuardianWhatsAppProvider;
  sender: GuardianWhatsAppSender;
  templates: {
    incidentAlert: GuardianWhatsAppTemplate;
    watchdogAlert: GuardianWhatsAppTemplate;
  };
  adminRecipients: string[];
  /** true solo si hay remitente configurado y al menos un destinatario válido. */
  canSend: boolean;
  /** Motivo legible cuando `canSend` es false. */
  blockedReason: string | null;
};

export const GUARDIAN_WHATSAPP_DEFAULT_API_VERSION = 'v21.0';
export const GUARDIAN_WHATSAPP_DEFAULT_TEMPLATE = 'guardian_incident_alert';
export const GUARDIAN_WHATSAPP_DEFAULT_LANGUAGE = 'es';

/**
 * Contrato EXACTO de la plantilla administrativa `guardian_incident_alert`.
 *
 * Fuente única de verdad compartida por:
 * - el texto que se introduce en WhatsApp Manager (ver
 *   `docs/guardian/WHATSAPP_TEMPLATE_GUARDIAN_INCIDENT_ALERT.md`),
 * - `buildGuardianAlertTemplateParams` en `guardian.alert.service.ts`,
 * - las pruebas que vigilan que el número y el orden de parámetros no cambien.
 *
 * Los ejemplos son SINTÉTICOS y no contienen datos fiscales, datos de clientes
 * finales ni información sensible: el cuerpo de la plantilla tampoco los pide.
 */
export const GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS = [
  {
    position: 1,
    key: 'severity',
    label: 'Nivel',
    sample: 'CRÍTICO',
    maxChars: 40,
    description: 'CRÍTICO | ALTO | MEDIO | BAJO',
  },
  {
    position: 2,
    key: 'company',
    label: 'Empresa',
    sample: 'Comercial Ejemplo SRL',
    maxChars: 120,
    description: 'Nombre comercial de la empresa afectada',
  },
  {
    position: 3,
    key: 'moduleOperation',
    label: 'Módulo / operación',
    sample: 'caja / cierre de sesión',
    maxChars: 120,
    description: 'Módulo y operación donde ocurrió el incidente',
  },
  {
    position: 4,
    key: 'occurredAtLocal',
    label: 'Fecha y hora',
    sample: '26/10, 03:15 a. m.',
    maxChars: 60,
    description: 'Día/mes y hora local en es-DO, formato corto (dd/MM, hh:mm a. m.)',
  },
  {
    position: 5,
    key: 'problem',
    label: 'Problema',
    sample: 'El cierre de caja no completa el cálculo del efectivo esperado',
    maxChars: 400,
    description: 'Resumen sanitizado del síntoma (sin datos de clientes)',
  },
  {
    position: 6,
    key: 'diagnosis',
    label: 'Diagnóstico',
    sample: 'Información pendiente de confirmar.',
    maxChars: 400,
    description: 'Hipótesis con evidencia o texto de pendiente',
  },
  {
    position: 7,
    key: 'impact',
    label: 'Impacto',
    sample: 'La sesión de caja queda abierta y no se puede facturar con turno cerrado',
    maxChars: 400,
    description: 'Impacto operativo estimado',
  },
  {
    position: 8,
    key: 'incidentShortId',
    label: 'ID corto',
    sample: 'INC-4F2A9C',
    maxChars: 20,
    description: 'Identificador corto del incidente (formato INC-XXXXXX)',
  },
] as const;

export const GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT =
  GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAMS.length;

/**
 * Cuerpo exacto de la plantilla, listo para WhatsApp Manager.
 *
 * Se usa categoría UTILITY: es un aviso operativo solicitado por el negocio, no
 * marketing. El estado del incidente va en texto fijo, no como parámetro, para
 * no alterar el contrato de 8 variables ya probado.
 */
export const GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_BODY = [
  'APPYRA Guardian — alerta de incidente',
  '',
  'Nivel: {{1}}',
  'Empresa: {{2}}',
  'Módulo: {{3}}',
  'Fecha y hora: {{4}}',
  '',
  'Problema: {{5}}',
  'Diagnóstico: {{6}}',
  'Impacto: {{7}}',
  '',
  'Estado: incidente registrado, investigación en curso.',
  'ID: {{8}}',
  '',
  'Mensaje automático de monitoreo. No se modificó información de tus clientes.',
].join('\n');

function read(env: NodeJS.ProcessEnv, name: string): string {
  return String(env[name] ?? '').trim();
}

/**
 * Normaliza un destinatario a dígitos E.164 (sin `+`).
 * Rechaza longitudes imposibles en lugar de enviar a un número truncado.
 */
export function normalizeWhatsAppRecipient(raw: unknown): string | null {
  const digits = String(raw ?? '').replace(/[^\d]/g, '');
  if (digits.length < 8 || digits.length > 15) return null;
  return digits;
}

/**
 * Acepta una lista separada por comas o punto y coma.
 * Mantiene el orden de configuración y elimina duplicados exactos.
 */
export function parseAdminRecipients(raw: string | undefined | null): string[] {
  const seen = new Set<string>();
  for (const part of String(raw ?? '').split(/[,;]+/)) {
    const normalized = normalizeWhatsAppRecipient(part);
    if (normalized) seen.add(normalized);
  }
  return [...seen];
}

export function resolveGuardianWhatsAppProfile(
  env: NodeJS.ProcessEnv = process.env,
): GuardianWhatsAppProfile {
  const token = read(env, 'GUARDIAN_WA_CLOUD_TOKEN');
  const phoneNumberId = read(env, 'GUARDIAN_WA_PHONE_NUMBER_ID');
  const configuredRecipients =
    read(env, 'GUARDIAN_ALERT_RECIPIENTS') || read(env, 'GUARDIAN_ALERT_RECIPIENT');
  const adminRecipients = parseAdminRecipients(configuredRecipients);

  const provider: GuardianWhatsAppProvider =
    token.length > 0 && phoneNumberId.length > 0 ? 'meta_cloud' : 'none';

  const sender: GuardianWhatsAppSender = {
    provider,
    wabaId: read(env, 'GUARDIAN_WA_WABA_ID') || null,
    phoneNumberId: phoneNumberId || null,
    displayNumber: normalizeWhatsAppRecipient(read(env, 'GUARDIAN_WA_DISPLAY_NUMBER')),
    displayName: read(env, 'GUARDIAN_WA_DISPLAY_NAME') || 'APPYRA',
    apiVersion: read(env, 'GUARDIAN_WA_API_VERSION') || GUARDIAN_WHATSAPP_DEFAULT_API_VERSION,
    tokenPresent: token.length > 0,
  };

  const incidentAlert: GuardianWhatsAppTemplate = {
    key: 'incidentAlert',
    name: read(env, 'GUARDIAN_WA_TEMPLATE_NAME') || GUARDIAN_WHATSAPP_DEFAULT_TEMPLATE,
    language: read(env, 'GUARDIAN_WA_TEMPLATE_LANG') || GUARDIAN_WHATSAPP_DEFAULT_LANGUAGE,
    category: 'UTILITY',
    paramCount: GUARDIAN_WHATSAPP_INCIDENT_TEMPLATE_PARAM_COUNT,
    description: 'Alerta administrativa de incidente Guardian (24/7).',
  };

  const watchdogAlert: GuardianWhatsAppTemplate = {
    key: 'watchdogAlert',
    name: read(env, 'GUARDIAN_WA_WATCHDOG_TEMPLATE_NAME') || 'guardian_watchdog_alert',
    language: read(env, 'GUARDIAN_WA_TEMPLATE_LANG') || GUARDIAN_WHATSAPP_DEFAULT_LANGUAGE,
    category: 'UTILITY',
    paramCount: 4,
    description: 'Aviso del watchdog independiente cuando Guardian no responde.',
  };

  const blockedReason =
    provider === 'none'
      ? 'WHATSAPP_SENDER_NOT_CONFIGURED'
      : adminRecipients.length === 0
        ? 'ALERT_RECIPIENT_NOT_CONFIGURED'
        : null;

  return {
    provider,
    sender,
    templates: { incidentAlert, watchdogAlert },
    adminRecipients,
    canSend: blockedReason === null,
    blockedReason,
  };
}
