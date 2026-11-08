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
 * 1. **Un bloqueo real aflora siempre**: si la evidencia dice `BLOCKED`, ese es
 *    el estado, incluso por encima de una autorización previa.
 * 2. **`SUSPENDED` es pegajoso**: es un acto administrativo externo y este
 *    módulo no puede levantarlo por el efecto secundario de una etapa.
 * 3. **`BLOCKED` NO es pegajoso**: se deriva de que exista una etapa bloqueada,
 *    así que cuando esa etapa se resuelve el estado debe dejar de estar
 *    bloqueado. Mantenerlo pegajoso lo volvía **irreversible** (defecto
 *    corregido en la auditoría del 07/11/2026).
 * 4. Solo se **promociona**: un estado derivado inferior nunca rebaja el actual.
 * 5. `READY_FOR_REVIEW` lo único que afirma es «hay evidencia pendiente de
 *    revisión». No certifica, no autoriza y no habilita emisión.
 */

/** Orden de avance. `SUSPENDED` queda fuera: es pegajoso. */
const PROGRESSION: Partial<Record<EcfCertificationStatus, number>> = {
  [EcfCertificationStatus.NOT_STARTED]: 0,
  // `BLOCKED` comparte nivel con NOT_STARTED a propósito: es «no ha avanzado»,
  // no un escalón superior. Así, cuando la etapa bloqueada se resuelve, el
  // estado derivado sube a IN_PROGRESS y el bloqueo se levanta. Antes se trataba
  // como pegajoso y el bloqueo resultaba IRREVERSIBLE: ninguna otra ruta de este
  // módulo escribe `certification_status`.
  [EcfCertificationStatus.BLOCKED]: 0,
  [EcfCertificationStatus.IN_PROGRESS]: 1,
  [EcfCertificationStatus.READY_FOR_REVIEW]: 2,
  [EcfCertificationStatus.AUTHORIZED_SANDBOX]: 3,
  [EcfCertificationStatus.PRODUCTION_READY]: 4,
};

/**
 * Estados que este módulo no puede levantar por inferencia.
 *
 * `SUSPENDED` es un acto administrativo externo. `BLOCKED` NO está aquí: se
 * deriva de la evidencia (alguna etapa bloqueada) y debe desaparecer cuando esa
 * evidencia desaparece.
 */
const STICKY: ReadonlySet<EcfCertificationStatus> = new Set([
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

  // Un bloqueo real detectado en la evidencia debe aflorar siempre, incluso por
  // encima de una autorizacion previa: la evidencia manda.
  if (derived === EcfCertificationStatus.BLOCKED) return derived;

  if (current && STICKY.has(current)) return current;

  if (!current) return derived;

  const currentRank = PROGRESSION[current] ?? UNRANKED;
  const derivedRank = PROGRESSION[derived] ?? UNRANKED;

  // Estado actual fuera de la escala y no pegajoso: se respeta.
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
