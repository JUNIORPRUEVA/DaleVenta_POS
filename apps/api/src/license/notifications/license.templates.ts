import { LicenseNotificationKind } from '@prisma/client';

export type LicenseTemplateName =
  | 'licencia_pago_por_verificar'
  | 'licencia_por_vencer_5d'
  | 'licencia_por_vencer_1d';

/**
 * Plantillas aprobadas en Meta. Los nombres y el orden de las variables son
 * parte del contrato con WhatsApp: cambiarlos exige volver a aprobarlas.
 */
export const LICENSE_TEMPLATES: Record<LicenseNotificationKind, LicenseTemplateName> = {
  ADMIN_EVIDENCE: 'licencia_pago_por_verificar',
  REMINDER_5D: 'licencia_por_vencer_5d',
  REMINDER_1D: 'licencia_por_vencer_1d',
};

export function buildAdminEvidenceParams(input: {
  companyName: string | null;
  planName: string | null;
  amount: number;
  reference: string;
  receivedAt: Date;
}) {
  return [
    input.companyName ?? 'Empresa sin nombre',
    input.planName ?? 'Plan',
    formatMoney(input.amount),
    input.reference,
    formatDate(input.receivedAt),
  ];
}

/**
 * Cuerpo detallado para la plantilla de soporte: los diez datos que el
 * administrador necesita para decidir sin preguntar al cliente.
 *
 * Se usa cuando `LICENSE_WA_ADMIN_DETAILED=true` y la plantilla aprobada en
 * Meta tiene esos diez parametros. El orden **no se cambia** sin actualizar la
 * plantilla.
 */
export function buildAdminEvidenceDetailedParams(input: {
  companyName: string | null;
  planName: string | null;
  operationType: string;
  expectedAmount: number;
  readAmount: number | null;
  internalReference: string;
  bankReference: string | null;
  occurredAt: string | null;
  analysisResult: string;
  licenseState: string;
}) {
  return [
    input.companyName ?? 'Empresa sin nombre',
    input.planName ?? 'Plan',
    input.operationType,
    formatMoney(input.expectedAmount),
    input.readAmount == null ? 'No leido' : formatMoney(input.readAmount),
    input.internalReference,
    input.bankReference ?? 'No visible',
    input.occurredAt ?? 'No visible',
    input.analysisResult,
    input.licenseState,
  ];
}

export function buildReminderParams(input: {
  companyName: string | null;
  planName: string | null;
  periodEnd: Date;
  reference: string | null;
}) {
  return [
    input.companyName ?? 'Empresa sin nombre',
    formatDate(input.periodEnd),
    input.reference?.trim() || 'Genera tu orden desde la seccion Planes',
  ];
}

export function formatMoney(amount: number) {
  const value = Number.isFinite(amount) ? amount : 0;
  return `RD$${value.toLocaleString('es-DO', {
    minimumFractionDigits: value % 1 === 0 ? 0 : 2,
    maximumFractionDigits: 2,
  })}`;
}

/** dd/mm/aaaa en hora de Republica Dominicana (UTC-4). */
export function formatDate(value: Date) {
  const local = new Date(value.getTime() - 4 * 60 * 60 * 1000);
  const day = String(local.getUTCDate()).padStart(2, '0');
  const month = String(local.getUTCMonth() + 1).padStart(2, '0');
  return `${day}/${month}/${local.getUTCFullYear()}`;
}
