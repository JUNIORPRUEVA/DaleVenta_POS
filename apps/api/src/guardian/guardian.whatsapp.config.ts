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
    paramCount: 8,
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
