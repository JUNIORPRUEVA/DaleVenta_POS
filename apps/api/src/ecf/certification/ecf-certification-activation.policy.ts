import { EcfCertificationStatus } from "@prisma/client";

/**
 * Derivación del estado de certificación a partir de las CREDENCIALES.
 *
 * Por qué existe
 * --------------
 * El objetivo del producto es que el cliente haga todo su trámite sin que nadie
 * de Fulltech intervenga. La cadena que lleva una credencial de DOSA a `ACTIVE`
 * es **evidencia que produce el propio cliente** (`DosaActivationService`):
 *
 *   sesión que vincula el RNC  →  webhook DOSA «finalizado»
 *   →  habilitación DGII APPROVED por registro oficial
 *   →  autorización administrativa registrada por el cliente
 *
 * Una credencial `ACTIVE` significa, por tanto, que la DGII ya autorizó a esa
 * empresa: el control regulatorio no lo ejerce Fulltech. Ese es el único hecho
 * del que este módulo deriva una autorización de emisión, y lo hace 1:1:
 *
 * | Credencial | Estado de certificación |
 * | --- | --- |
 * | `production` en `ACTIVE` | `PRODUCTION_READY` |
 * | `test` en `ACTIVE` | `AUTHORIZED_SANDBOX` |
 *
 * Lo que esta función NO hace
 * ---------------------------
 * No decide por ausencia: si no hay credencial activa devuelve `null`, y quien
 * la llama conserva el estado que ya había. Una credencial `REVOKED` tampoco
 * autoriza ni degrada: retirar una autorización es un acto administrativo con
 * motivo (ruta de plataforma), no un efecto secundario de una revocación de
 * credencial. Igual que con `SUSPENDED` y `BLOCKED`: esta función no los levanta,
 * porque `resolveCertificationStatus` es la que aplica esas reglas.
 *
 * Función pura: sin base de datos, sin reloj, sin efectos. Así se puede probar
 * cada combinación de estados sin infraestructura.
 */

export type ActivationCredentialLike = {
  environment: string;
  status: string;
};

/** ¿Está esta credencial habilitada para emitir? */
function isActive(credential: ActivationCredentialLike): boolean {
  return `${credential.status ?? ""}`.toUpperCase() === "ACTIVE";
}

/**
 * Estado de certificación que la evidencia de credenciales sostiene, o `null`
 * si no sostiene ninguno.
 *
 * Se evalúa producción primero: tener credencial de producción implica haber
 * pasado por todo lo anterior.
 */
export function deriveCertificationFromCredentials(
  credentials: readonly ActivationCredentialLike[],
): EcfCertificationStatus | null {
  const activeEnvironments = new Set(
    credentials
      .filter(isActive)
      .map((credential) => `${credential.environment ?? ""}`.trim().toLowerCase()),
  );

  if (activeEnvironments.has("production")) {
    return EcfCertificationStatus.PRODUCTION_READY;
  }
  if (activeEnvironments.has("test")) {
    return EcfCertificationStatus.AUTHORIZED_SANDBOX;
  }
  return null;
}

/**
 * ¿Se puede derivar una promoción sobre este estado actual?
 *
 * `BLOCKED` significa que hay evidencia vigente en contra (una etapa de
 * onboarding bloqueada). Promocionar por encima de un bloqueo produciría una
 * autorización que la siguiente actualización de etapa revertiría, así que se
 * rechaza igual que en la ruta administrativa. La razón es la misma en los dos
 * caminos: un bloqueo se resuelve, no se salta.
 */
export function canDerivePromotion(input: {
  current: EcfCertificationStatus;
}): boolean {
  return input.current !== EcfCertificationStatus.BLOCKED;
}
