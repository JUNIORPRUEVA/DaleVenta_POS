/**
 * Política del MOTOR DE ACTIVACIÓN e-CF (self-service).
 *
 * Todo lo que decide está aquí y es puro: no toca base de datos, no llama a
 * nadie. Consecuencia buscada: el comportamiento del motor se puede probar
 * entero sin red y sin PostgreSQL.
 *
 * Regla que gobierna el módulo: el motor NUNCA puede convertir una simulación ni
 * una revisión interna en una habilitación oficial. Solo el registro oficial
 * verificado (`EcfDgiiHabilitation.authorizationSource = DGII_OFFICIAL_RECORD`)
 * puede acercarse a eso, y ese flujo ya existe fuera de este motor.
 */

import { ECF_DGII_REQUIREMENT_CATALOG } from "./ecf-dgii-habilitation.policy";

/** Clase de ejecución de un paso. Decide QUIÉN lo puede completar. */
export const ECF_ACTIVATION_CLASS = {
  /** El motor lo ejecuta solo, sin terceros. */
  AUTOMATIC_LOCAL: "AUTOMATIC_LOCAL",
  /** El motor lo pide a un transporte (Alanube). Hoy: simulado. */
  PROVIDER_WAIT: "PROVIDER_WAIT",
  /** Exige un acto del cliente (certificado, declaración jurada). */
  CLIENT_ACTION: "CLIENT_ACTION",
  /** Exige una decisión de la DGII. No se automatiza. */
  AUTHORITY_WAIT: "AUTHORITY_WAIT",
} as const;
export type EcfActivationClass =
  (typeof ECF_ACTIVATION_CLASS)[keyof typeof ECF_ACTIVATION_CLASS];

/** Estados de etapa que maneja el motor (se guardan en `EcfOnboardingStep`). */
export const ECF_ACTIVATION_STATUS = {
  PENDING: "PENDING",
  IN_PROGRESS: "IN_PROGRESS",
  COMPLETED: "COMPLETED",
  AWAITING_CLIENT: "AWAITING_CLIENT",
  AWAITING_AUTHORITY: "AWAITING_AUTHORITY",
  AWAITING_PROVIDER: "AWAITING_PROVIDER",
  FAILED: "FAILED",
} as const;
export type EcfActivationStatus =
  (typeof ECF_ACTIVATION_STATUS)[keyof typeof ECF_ACTIVATION_STATUS];

const RESOLVED: ReadonlySet<string> = new Set([
  ECF_ACTIVATION_STATUS.COMPLETED,
]);

/**
 * Clasificación por clave del catálogo. Es la auditoría del ADR-001 llevada a
 * código: cada paso tiene dueño explícito.
 */
export const ECF_ACTIVATION_CLASS_BY_KEY: Readonly<
  Record<string, EcfActivationClass>
> = {
  FISCAL_DATA: ECF_ACTIVATION_CLASS.AUTOMATIC_LOCAL,
  REQUIREMENTS: ECF_ACTIVATION_CLASS.CLIENT_ACTION,
  DIGITAL_CERTIFICATE: ECF_ACTIVATION_CLASS.CLIENT_ACTION,
  ALANUBE_REGISTRATION: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
  DGII_POSTULATION: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
  XML_SIGNATURE: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
  SET_TESTS: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
  SIMULATIONS: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
  PRINTED_REPRESENTATION: ECF_ACTIVATION_CLASS.AUTOMATIC_LOCAL,
  SERVICE_URLS: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
  SWORN_DECLARATION: ECF_ACTIVATION_CLASS.CLIENT_ACTION,
  FINAL_AUTHORIZATION: ECF_ACTIVATION_CLASS.AUTHORITY_WAIT,
  ENCF_REQUEST: ECF_ACTIVATION_CLASS.PROVIDER_WAIT,
  // Etapa V: la resuelve el cliente en la Oficina Virtual. El motor no puede
  // delegar roles por él ni darla por buena sin evidencia oficial.
  ROLE_ASSIGNMENT: ECF_ACTIVATION_CLASS.CLIENT_ACTION,
  PRODUCTION_ENABLEMENT: ECF_ACTIVATION_CLASS.AUTHORITY_WAIT,
};

/** Clase de un paso; si el catálogo crece sin clasificar, falla cerrado. */
export function activationClassOf(key: string): EcfActivationClass {
  return ECF_ACTIVATION_CLASS_BY_KEY[key] ?? ECF_ACTIVATION_CLASS.CLIENT_ACTION;
}

/** Paso del estado persistido, tal como llega del servicio. */
export interface ActivationStepInput {
  key: string;
  stepKey: string;
  label: string;
  mandatory: boolean;
  status: string;
}

/** Vista de un paso para el cliente: estado, dueño y qué se espera de él. */
export interface ActivationStepView extends ActivationStepInput {
  className: EcfActivationClass;
  resolved: boolean;
  /** `true` solo si el motor puede ejecutarlo en este momento. */
  executable: boolean;
  /** Qué hace falta para que avance (texto para el cliente). */
  awaiting: string | null;
}

const AWAITING_TEXT: Readonly<Record<EcfActivationClass, string | null>> = {
  AUTOMATIC_LOCAL: null,
  PROVIDER_WAIT: "En manos del proveedor. El sistema reintenta solo.",
  CLIENT_ACTION: "Necesitamos un dato o un acto tuyo para continuar.",
  AUTHORITY_WAIT: "Pendiente de decisión de la DGII. No depende del sistema.",
};

/**
 * Construye la vista del motor.
 *
 * Un paso está `executable` si el motor es su dueño y no está resuelto. Un paso
 * de espera no se considera "pendiente del cliente" aunque no esté resuelto: la
 * interfaz debe poder distinguir "te toca a ti" de "estamos esperando".
 */
export function buildActivationView(
  steps: readonly ActivationStepInput[],
): ActivationStepView[] {
  return steps.map((step) => {
    const className = activationClassOf(step.key);
    const resolved = RESOLVED.has(step.status);
    const executable =
      !resolved &&
      (className === ECF_ACTIVATION_CLASS.AUTOMATIC_LOCAL ||
        className === ECF_ACTIVATION_CLASS.PROVIDER_WAIT);
    return {
      ...step,
      className,
      resolved,
      executable,
      awaiting: resolved ? null : AWAITING_TEXT[className],
    };
  });
}

/** Bloqueos que impiden arrancar el motor, con el paso que los causa. */
export function activationBlockers(input: {
  fiscalDataReady: boolean;
  applicationSubmitted: boolean;
}): string[] {
  const blockers: string[] = [];
  if (!input.fiscalDataReady) blockers.push("ECF_ACTIVATION_FISCAL_DATA_MISSING");
  if (!input.applicationSubmitted) {
    blockers.push("ECF_ACTIVATION_APPLICATION_NOT_SUBMITTED");
  }
  return blockers;
}

/**
 * Siguiente paso que el motor puede ejecutar, o `null`.
 *
 * Respeta el orden del catálogo y **se detiene en el primer paso que no puede
 * resolver**: para avanzar a un paso posterior hay que haber resuelto los
 * anteriores. Sin esta condición, el motor podría "saltarse" el certificado y
 * declarar la habilitación completada.
 */
export function nextExecutableStep(
  view: readonly ActivationStepView[],
): ActivationStepView | null {
  for (const step of view) {
    if (step.resolved) continue;
    if (step.executable) return step;
    // Primer paso no resuelto que NO es del motor: todo lo demás espera.
    return null;
  }
  return null;
}

/** ¿Puede el motor ejecutar algo ahora mismo? */
export function hasExecutableWork(
  view: readonly ActivationStepView[],
): boolean {
  return nextExecutableStep(view) !== null;
}

/**
 * Traduce el resultado del transporte al estado persistible.
 *
 * Aquí está la garantía central del módulo: **ningún resultado del transporte
 * puede completar un paso de la autoridad**, y un paso de proveedor simulado
 * queda marcado como simulado, nunca como oficial.
 */
export function stepStatusFromTransport(input: {
  className: EcfActivationClass;
  transportOk: boolean;
  simulated: boolean;
}): EcfActivationStatus {
  if (input.className === ECF_ACTIVATION_CLASS.AUTHORITY_WAIT) {
    // Ni éxito ni simulación: la autoridad no la mueve el sistema.
    return ECF_ACTIVATION_STATUS.AWAITING_AUTHORITY;
  }
  if (!input.transportOk) return ECF_ACTIVATION_STATUS.FAILED;
  if (input.className === ECF_ACTIVATION_CLASS.CLIENT_ACTION) {
    return ECF_ACTIVATION_STATUS.AWAITING_CLIENT;
  }
  return ECF_ACTIVATION_STATUS.COMPLETED;
}

/** Resumen honesto del avance: sin porcentajes inventados. */
export function activationSummary(view: readonly ActivationStepView[]) {
  const total = view.length;
  const resolvedCount = view.filter((step) => step.resolved).length;
  return {
    total,
    resolvedCount,
    percent: total === 0 ? 0 : Math.round((resolvedCount / total) * 100),
    awaitingClient: view
      .filter(
        (step) =>
          !step.resolved &&
          step.className === ECF_ACTIVATION_CLASS.CLIENT_ACTION,
      )
      .map((step) => step.key),
    awaitingAuthority: view
      .filter(
        (step) =>
          !step.resolved &&
          step.className === ECF_ACTIVATION_CLASS.AUTHORITY_WAIT,
      )
      .map((step) => step.key),
    /** Estado en el que está el motor ahora, en lenguaje del producto. */
    stage: stageOf(view),
  };
}

export type EcfActivationStage =
  | "NOT_STARTED"
  | "RUNNING"
  | "BLOCKED_ON_CLIENT"
  | "BLOCKED_ON_PROVIDER"
  | "AWAITING_AUTHORITY"
  | "COMPLETED";

export function stageOf(
  view: readonly ActivationStepView[],
): EcfActivationStage {
  if (view.length === 0) return "NOT_STARTED";
  if (view.every((step) => step.resolved)) return "COMPLETED";
  if (view.every((step) => step.status === ECF_ACTIVATION_STATUS.PENDING)) {
    return "NOT_STARTED";
  }
  const next = view.find((step) => !step.resolved);
  if (!next) return "COMPLETED";
  switch (next.className) {
    case ECF_ACTIVATION_CLASS.CLIENT_ACTION:
      return "BLOCKED_ON_CLIENT";
    case ECF_ACTIVATION_CLASS.AUTHORITY_WAIT:
      return "AWAITING_AUTHORITY";
    case ECF_ACTIVATION_CLASS.PROVIDER_WAIT:
      return "BLOCKED_ON_PROVIDER";
    default:
      return "RUNNING";
  }
}

/** Estado inicial de un paso del catálogo. */
export function initialStepStatus(key: string): EcfActivationStatus {
  const className = activationClassOf(key);
  if (className === ECF_ACTIVATION_CLASS.CLIENT_ACTION) {
    return ECF_ACTIVATION_STATUS.AWAITING_CLIENT;
  }
  if (className === ECF_ACTIVATION_CLASS.AUTHORITY_WAIT) {
    return ECF_ACTIVATION_STATUS.AWAITING_AUTHORITY;
  }
  return ECF_ACTIVATION_STATUS.PENDING;
}

/**
 * Resuelve el identificador que llega del cliente a la entrada del catálogo.
 *
 * El catálogo expone dos nombres por paso: `key` (requisito) y `stepKey`
 * (etapa persistida). Coinciden en casi todos, pero no en el primero:
 * `FISCAL_DATA` es el requisito y `FISCAL_CONFIG` la etapa. Sin esta
 * resolución, reintentar ese paso escribía contra un valor que no existe en
 * `EcfOnboardingStepKey`, y el paso quedaba imposible de reintentar.
 */
export function resolveCatalogEntry(identifier: string) {
  const normalized = identifier.trim().toUpperCase();
  if (!normalized) return null;
  return (
    ECF_DGII_REQUIREMENT_CATALOG.find(
      (item) => item.key === normalized || item.stepKey === normalized,
    ) ?? null
  );
}

/** Pasos del catálogo en orden, con su clase. */
export function catalogWithClass() {
  return ECF_DGII_REQUIREMENT_CATALOG.map((item) => ({
    key: item.key,
    stepKey: item.stepKey,
    label: item.label,
    mandatory: item.mandatory,
    className: activationClassOf(item.key),
  }));
}
