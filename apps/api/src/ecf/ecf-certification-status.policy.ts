import { EcfCertificationStatus } from "@prisma/client";

/**
 * Transiciones del estado de certificación e-CF.
 *
 * El estado de una empresa se **deriva** de su evidencia (pasos de onboarding y
 * eventos autenticados del proveedor), pero derivar no puede significar
 * "reescribir lo que diga la columna": eso permitía que tocar una etapa
 * cualquiera degradara una empresa que ya tenía una autorización legítima.
 *
 * Reglas:
 *
 * 1. `BLOCKED` y `SUSPENDED` son pegajosos. Salir de ellos es un acto humano
 *    documentado, no el efecto secundario de una actualización de etapa.
 * 2. Solo se **promociona**. Un estado derivado inferior nunca rebaja el actual.
 * 3. `READY_FOR_REVIEW` lo único que afirma es «hay evidencia pendiente de
 *    revisión». No certifica, no autoriza y no habilita emisión.
 */

/** Orden de avance. `BLOCKED` y `SUSPENDED` quedan fuera: son pegajosos. */
const PROGRESSION: Partial<Record<EcfCertificationStatus, number>> = {
  [EcfCertificationStatus.NOT_STARTED]: 0,
  [EcfCertificationStatus.IN_PROGRESS]: 1,
  [EcfCertificationStatus.READY_FOR_REVIEW]: 2,
  [EcfCertificationStatus.AUTHORIZED_SANDBOX]: 3,
  [EcfCertificationStatus.PRODUCTION_READY]: 4,
};

const STICKY: ReadonlySet<EcfCertificationStatus> = new Set([
  EcfCertificationStatus.BLOCKED,
  EcfCertificationStatus.SUSPENDED,
]);

const UNRANKED = -1;

/**
 * Estado que debe quedar guardado.
 *
 * `derived` es lo que dice la evidencia ahora mismo; `current` es lo que ya
 * estaba persistido (o `null` si la configuración se está creando).
 */
export function resolveCertificationStatus(input: {
  current: EcfCertificationStatus | null;
  derived: EcfCertificationStatus;
}): EcfCertificationStatus {
  const { current, derived } = input;

  // Un bloqueo real detectado en la evidencia debe aflorar siempre: ocultarlo
  // sería peor que cualquier otra consideración.
  if (derived === EcfCertificationStatus.BLOCKED) return derived;

  if (current && STICKY.has(current)) return current;

  if (!current) return derived;

  const currentRank = PROGRESSION[current] ?? UNRANKED;
  const derivedRank = PROGRESSION[derived] ?? UNRANKED;

  // Estado actual fuera de la escala de avance pero no pegajoso: se respeta.
  if (currentRank === UNRANKED) return current;

  return derivedRank > currentRank ? derived : current;
}

/**
 * ¿Hay evidencia externa suficiente para afirmar que el caso está pendiente de
 * revisión?
 *
 * Solo cuenta un evento **autenticado y completo**. Un evento a medias
 * (`PENDING_CREDENTIALS`) no es evidencia de nada: es un fallo de guardado.
 */
export function isReadyForReviewEvidence(input: {
  completeWebhookEvents: number;
}): boolean {
  return input.completeWebhookEvents > 0;
}
