import { EcfCertificationStatus } from "@prisma/client";

/**
 * Política de AUTORIZACIÓN DE EMISIÓN por empresa.
 *
 * Problema que resuelve
 * ---------------------
 * `deriveCertificationStatus` (en `ecf.service.ts`) solo puede producir
 * `NOT_STARTED`, `IN_PROGRESS`, `BLOCKED` y `READY_FOR_REVIEW`: los mira desde
 * la evidencia interna. Los dos estados que el orquestador de emisión exige
 * para despachar (`AUTHORIZED_SANDBOX`, `PRODUCTION_READY`) no los escribía
 * ninguna ruta en ejecución, así que promover a un cliente real obligaba a un
 * `UPDATE` manual en la base: una dependencia que no es auditable ni repetible.
 *
 * Esta política es la ÚNICA puerta que puede escribir esos dos estados, y sólo
 * en la dirección de avance que se declara aquí.
 *
 * Lo que esta política NO hace
 * ----------------------------
 * No habilita la emisión por sí sola. `DosaEmissionDispatchService` sigue
 * exigiendo, además: configuración `enabled`, proveedor `DOSA`, credenciales
 * activas, compuerta fiscal y la bandera global `DOSA_EMISSION_ENABLED`. Un
 * error aquí no puede producir un comprobante: como mucho deja a una empresa
 * «autorizada» sin poder emitir.
 *
 * Función pura: recibe el estado actual y devuelve la decisión, sin tocar la
 * base ni el reloj, para poder probar cada transición de forma determinista.
 */

/** Estados que esta ruta puede ASIGNAR. Lista cerrada. */
export const ECF_CERTIFICATION_GRANT_TARGETS = [
  "AUTHORIZED_SANDBOX",
  "PRODUCTION_READY",
] as const;

export type EcfCertificationGrantTarget =
  (typeof ECF_CERTIFICATION_GRANT_TARGETS)[number];

/**
 * Estado que deja una REVOCACIÓN.
 *
 * `SUSPENDED` es pegajoso en `resolveCertificationStatus`: tocar una etapa de
 * onboarding no lo levanta. Levantarlo exige una autorización explícita por esta
 * misma vía, con motivo y actor.
 */
export const ECF_CERTIFICATION_REVOKED_STATE = EcfCertificationStatus.SUSPENDED;

/**
 * Desde qué estados se puede llegar a cada objetivo.
 *
 * El estado de destino se incluye a propósito: conceder dos veces lo mismo es
 * idempotente (`changed: false`), no un error. Un reintento de la interfaz no
 * debe fallar ni duplicar auditoría.
 *
 * `BLOCKED` NO aparece en ninguna lista: una etapa bloqueada es evidencia
 * vigente en contra. Autorizar por encima de ella daría una autorización que la
 * siguiente actualización de etapa revertiría, así que se rechaza con un código
 * propio y se pide resolver el bloqueo primero.
 */
const ALLOWED_FROM: Readonly<
  Record<EcfCertificationGrantTarget, readonly EcfCertificationStatus[]>
> = {
  AUTHORIZED_SANDBOX: [
    EcfCertificationStatus.NOT_STARTED,
    EcfCertificationStatus.IN_PROGRESS,
    EcfCertificationStatus.READY_FOR_REVIEW,
    EcfCertificationStatus.SUSPENDED,
    EcfCertificationStatus.AUTHORIZED_SANDBOX,
  ],
  // Producción solo se concede a quien YA pasó por sandbox: es la única forma de
  // garantizar que alguien probó el flujo antes de emitir con efecto fiscal.
  PRODUCTION_READY: [
    EcfCertificationStatus.AUTHORIZED_SANDBOX,
    EcfCertificationStatus.PRODUCTION_READY,
  ],
};

/** Desde qué estados se puede revocar. */
const REVOCABLE_FROM: readonly EcfCertificationStatus[] = [
  EcfCertificationStatus.AUTHORIZED_SANDBOX,
  EcfCertificationStatus.PRODUCTION_READY,
  // Repetir la revocación es idempotente, no un error.
  EcfCertificationStatus.SUSPENDED,
];

/** Códigos de rechazo. Viajan al cliente tal cual: no se reinterpretan. */
export const ECF_CERTIFICATION_REFUSALS = {
  CONFIGURATION_NOT_FOUND: "ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND",
  TARGET_NOT_ALLOWED: "ECF_CERTIFICATION_TARGET_NOT_ALLOWED",
  STATE_BLOCKED: "ECF_CERTIFICATION_STATE_BLOCKED",
  SANDBOX_REQUIRED: "ECF_CERTIFICATION_SANDBOX_REQUIRED",
  DOWNGRADE_NOT_ALLOWED: "ECF_CERTIFICATION_DOWNGRADE_NOT_ALLOWED",
  NOT_AUTHORIZED: "ECF_CERTIFICATION_NOT_AUTHORIZED",
  STATE_UNKNOWN: "ECF_CERTIFICATION_STATE_UNKNOWN",
} as const;

export type EcfCertificationRefusal =
  (typeof ECF_CERTIFICATION_REFUSALS)[keyof typeof ECF_CERTIFICATION_REFUSALS];

export type EcfCertificationDecision =
  | {
      ok: true;
      /** `false` cuando el estado ya era el pedido: no se escribe ni se audita. */
      changed: boolean;
      from: EcfCertificationStatus;
      to: EcfCertificationStatus;
    }
  | { ok: false; blockedReason: EcfCertificationRefusal };

/**
 * ¿Es un objetivo asignable por esta vía?
 *
 * Se comprueba también en el servicio, no solo en el DTO: el DTO valida la
 * petición HTTP, pero el servicio puede ser llamado desde una tarea interna.
 */
export function isCertificationGrantTarget(
  value: string,
): value is EcfCertificationGrantTarget {
  return (ECF_CERTIFICATION_GRANT_TARGETS as readonly string[]).includes(value);
}

/**
 * Decisión de AUTORIZAR una empresa.
 *
 * `current` es lo persistido. No se acepta `null`: sin configuración e-CF no
 * hay empresa que autorizar, y crear la fila aquí escondería que el cliente
 * nunca empezó el trámite. El servicio responde
 * `ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND`.
 */
export function decideCertificationGrant(input: {
  current: EcfCertificationStatus;
  target: string;
}): EcfCertificationDecision {
  const { current } = input;

  if (!isCertificationGrantTarget(input.target)) {
    return {
      ok: false,
      blockedReason: ECF_CERTIFICATION_REFUSALS.TARGET_NOT_ALLOWED,
    };
  }
  const target = input.target as EcfCertificationGrantTarget;

  // El bloqueo manda sobre cualquier autorización: es evidencia, no un estado
  // administrativo.
  if (current === EcfCertificationStatus.BLOCKED) {
    return { ok: false, blockedReason: ECF_CERTIFICATION_REFUSALS.STATE_BLOCKED };
  }

  if (!(ALLOWED_FROM[target] as readonly EcfCertificationStatus[]).includes(current)) {
    // Se distinguen los dos casos que un operador puede corregir solo, para que
    // el mensaje diga qué hacer en lugar de un genérico «no permitido».
    if (
      target === EcfCertificationStatus.PRODUCTION_READY &&
      (current === EcfCertificationStatus.NOT_STARTED ||
        current === EcfCertificationStatus.IN_PROGRESS ||
        current === EcfCertificationStatus.READY_FOR_REVIEW)
    ) {
      return {
        ok: false,
        blockedReason: ECF_CERTIFICATION_REFUSALS.SANDBOX_REQUIRED,
      };
    }
    if (
      target === EcfCertificationStatus.AUTHORIZED_SANDBOX &&
      current === EcfCertificationStatus.PRODUCTION_READY
    ) {
      return {
        ok: false,
        blockedReason: ECF_CERTIFICATION_REFUSALS.DOWNGRADE_NOT_ALLOWED,
      };
    }
    return {
      ok: false,
      blockedReason: ECF_CERTIFICATION_REFUSALS.STATE_UNKNOWN,
    };
  }

  return {
    ok: true,
    changed: current !== target,
    from: current,
    to: target,
  };
}

/**
 * Decisión de REVOCAR la autorización de una empresa.
 *
 * Revocar deja `SUSPENDED`, nunca `NOT_STARTED`: la diferencia importa porque
 * `NOT_STARTED` describe «no ha empezado» y lo ocurrido es «se le retiró la
 * autorización».
 */
export function decideCertificationRevoke(input: {
  current: EcfCertificationStatus;
}): EcfCertificationDecision {
  const { current } = input;

  if (current === EcfCertificationStatus.SUSPENDED) {
    return {
      ok: true,
      changed: false,
      from: current,
      to: ECF_CERTIFICATION_REVOKED_STATE,
    };
  }

  if (!(REVOCABLE_FROM as readonly EcfCertificationStatus[]).includes(current)) {
    // Retirar una autorización que no existe no es un éxito silencioso: deja
    // constancia de que el operador creía otra cosa.
    return { ok: false, blockedReason: ECF_CERTIFICATION_REFUSALS.NOT_AUTHORIZED };
  }

  return {
    ok: true,
    changed: true,
    from: current,
    to: ECF_CERTIFICATION_REVOKED_STATE,
  };
}
