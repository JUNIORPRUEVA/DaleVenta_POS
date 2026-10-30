/**
 * Política de HABILITACIÓN DGII por empresa.
 *
 * Este módulo distingue dos cosas que NO son lo mismo:
 *
 *   A. El módulo e-CF está habilitado (configuración de la empresa).
 *   B. La empresa está FISCALMENTE AUTORIZADA para emitir.
 *
 * Una empresa puede tener A y NO tener B. La habilitación aquí implementada es
 * un registro de SEGUIMIENTO INTERNO: anotar un progreso nunca concede una
 * autorización oficial, y ninguna acción administrativa simple puede declarar a
 * una empresa oficialmente aprobada.
 *
 * Toda la política es pura y fail-closed: ante la duda, bloquea.
 */

/** Estados de seguimiento de la habilitación. Reflejan `EcfDgiiHabilitationState`. */
export const ECF_DGII_HABILITATION_STATES = [
  "NOT_STARTED",
  "PREPARING_REQUIREMENTS",
  "APPLICATION_PENDING",
  "IN_PROGRESS",
  "TESTS_PENDING",
  "IN_CERTIFICATION",
  "APPROVED",
  "REJECTED",
  "REQUIRES_CORRECTION",
] as const;
export type EcfDgiiHabilitationState = (typeof ECF_DGII_HABILITATION_STATES)[number];

/** Fuentes de verificación. Solo `DGII_OFFICIAL_RECORD` puede sustentar la autorización. */
export const ECF_DGII_VERIFICATION_SOURCES = [
  "NONE",
  "MANUAL_OPERATOR_DECLARATION",
  "PROVIDER_CONFIRMATION",
  "DGII_OFFICIAL_RECORD",
] as const;
export type EcfDgiiVerificationSource = (typeof ECF_DGII_VERIFICATION_SOURCES)[number];

/** Origen de una evidencia: separa declaración manual de documento oficial. */
export const ECF_EVIDENCE_SOURCES = [
  "MANUAL_DECLARATION",
  "OFFICIAL_DOCUMENT",
  "PROVIDER_ARTIFACT",
] as const;
export type EcfEvidenceSource = (typeof ECF_EVIDENCE_SOURCES)[number];

/** Estados terminales: no admiten transición saliente no revisada. */
const TERMINAL_STATES = new Set<EcfDgiiHabilitationState>(["APPROVED", "REJECTED"]);

/**
 * Transiciones permitidas. Deliberadamente conservadoras: todo lo que no figura
 * aquí se rechaza. `APPROVED` solo es alcanzable con autorización oficial
 * verificada (lo comprueba `canReachState`, no la tabla).
 */
export const ECF_DGII_ALLOWED_TRANSITIONS: Record<
  EcfDgiiHabilitationState,
  readonly EcfDgiiHabilitationState[]
> = {
  NOT_STARTED: ["PREPARING_REQUIREMENTS", "APPLICATION_PENDING"],
  PREPARING_REQUIREMENTS: [
    "APPLICATION_PENDING",
    "REQUIRES_CORRECTION",
    "REJECTED",
    "NOT_STARTED",
  ],
  APPLICATION_PENDING: ["IN_PROGRESS", "REQUIRES_CORRECTION", "REJECTED"],
  IN_PROGRESS: ["TESTS_PENDING", "IN_CERTIFICATION", "REQUIRES_CORRECTION", "REJECTED"],
  TESTS_PENDING: ["IN_CERTIFICATION", "REQUIRES_CORRECTION", "REJECTED"],
  IN_CERTIFICATION: ["APPROVED", "REQUIRES_CORRECTION", "REJECTED"],
  APPROVED: ["REQUIRES_CORRECTION", "REJECTED"],
  REJECTED: ["PREPARING_REQUIREMENTS", "APPLICATION_PENDING"],
  REQUIRES_CORRECTION: ["PREPARING_REQUIREMENTS", "APPLICATION_PENDING", "IN_PROGRESS"],
};

/**
 * DUEÑO de cada estado del expediente.
 *
 * La tabla de transiciones dice qué cambios son válidos; esta dice QUIÉN puede
 * declararlos. Sin esta separación una empresa podía escribir `IN_CERTIFICATION`
 * y presentar como hecho un estado que solo la DGII o el proveedor pueden
 * producir.
 *
 * `CUSTOMER_ACTION`: lo declara la propia empresa (iniciar, preparar, postular,
 * reanudar tras una corrección).
 * `SYSTEM_VERIFIED`: lo produce el sistema con una verificación real.
 * `PROVIDER_VERIFIED`: lo produce Alanube (p. ej. aceptación de la postulación).
 * `DGII_VERIFIED`: lo produce la DGII o queda acreditado con registro oficial.
 */
export type EcfStateOwner =
  | "CUSTOMER_ACTION"
  | "SYSTEM_VERIFIED"
  | "PROVIDER_VERIFIED"
  | "DGII_VERIFIED";

export const ECF_STATE_OWNERSHIP: Record<
  EcfDgiiHabilitationState,
  EcfStateOwner
> = {
  NOT_STARTED: "CUSTOMER_ACTION",
  PREPARING_REQUIREMENTS: "CUSTOMER_ACTION",
  APPLICATION_PENDING: "CUSTOMER_ACTION",
  // Aceptación de la postulación por parte de Alanube.
  IN_PROGRESS: "PROVIDER_VERIFIED",
  // Set de pruebas generado y validado por el sistema.
  TESTS_PENDING: "SYSTEM_VERIFIED",
  // La DGII toma el expediente para verificación.
  IN_CERTIFICATION: "DGII_VERIFIED",
  APPROVED: "DGII_VERIFIED",
  REJECTED: "DGII_VERIFIED",
  // Veredicto de una revisión; la empresa puede REANUDAR desde él, no fijarlo.
  REQUIRES_CORRECTION: "DGII_VERIFIED",
};

/**
 * Motivo por el que la EMPRESA no puede fijar este estado, o `null` si puede.
 *
 * Debe aplicarse en TODA vía que actúe en nombre de la empresa. El panel de
 * plataforma tiene su propio camino y no pasa por aquí, pero tampoco puede
 * aprobar: `APPROVED` sigue exigiendo registro oficial verificado.
 */
export function customerStateRefusal(to: string): string | null {
  if (!isKnownState(to)) return null; // el estado inválido lo rechaza la tabla
  if (ECF_STATE_OWNERSHIP[to] === "CUSTOMER_ACTION") return null;
  return "ECF_DGII_STATE_REQUIRES_EXTERNAL_EVIDENCE";
}

function isKnownState(value: string): value is EcfDgiiHabilitationState {
  return (ECF_DGII_HABILITATION_STATES as readonly string[]).includes(value);
}

/** `true` si `from -> to` figura en la tabla de transiciones autorizadas. */
export function isTransitionAllowed(from: string, to: string): boolean {
  if (!isKnownState(from) || !isKnownState(to)) return false;
  if (from === to) return true; // idempotente: reafirmar el mismo estado es inocuo
  return ECF_DGII_ALLOWED_TRANSITIONS[from].includes(to);
}

/** `true` cuando el estado no admite salidas hacia adelante sin corrección. */
export function isTerminalState(state: string): boolean {
  return isKnownState(state) && TERMINAL_STATES.has(state);
}

export type EcfOfficialAuthorization = {
  state: string;
  authorizationSource: string | null;
  authorizationEvidenceId: string | null;
  authorizedAt: Date | string | null;
  externalId: string | null;
};

/**
 * `true` solo si existe una autorización OFICIAL verificable: estado `APPROVED`,
 * fuente `DGII_OFFICIAL_RECORD`, evidencia documental referenciada, fecha de
 * autorización e identificador externo. Cualquier otro caso es `false`, aunque
 * el estado diga `APPROVED`: una declaración manual del operador no es una
 * autorización oficial.
 */
export function hasOfficialAuthorization(
  record: EcfOfficialAuthorization | null | undefined,
): boolean {
  if (!record) return false;
  return (
    record.state === "APPROVED" &&
    record.authorizationSource === "DGII_OFFICIAL_RECORD" &&
    Boolean(record.authorizationEvidenceId) &&
    Boolean(record.authorizedAt) &&
    Boolean(record.externalId)
  );
}

/** Motivo por el que NO se puede fijar el estado pedido, o `null` si es admisible. */
export function stateUpdateRefusal(
  current: string,
  next: string,
  officialAuthorizationPresent: boolean,
): string | null {
  if (!isKnownState(next)) return "ECF_DGII_STATE_UNKNOWN";
  if (!isTransitionAllowed(current, next)) return "ECF_DGII_TRANSITION_NOT_ALLOWED";
  // Anti-falsificación: una acción administrativa no puede declarar aprobación
  // oficial. `APPROVED` exige autorización oficial ya verificada y registrada.
  if (next === "APPROVED" && !officialAuthorizationPresent) {
    return "ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD";
  }
  return null;
}

/** Motivo por el que NO se puede registrar la autorización pedida, o `null`. */
export function authorizationRefusal(input: {
  source: string;
  evidenceId?: string | null;
  externalId?: string | null;
}): string | null {
  if (!(ECF_DGII_VERIFICATION_SOURCES as readonly string[]).includes(input.source)) {
    return "ECF_DGII_VERIFICATION_SOURCE_UNKNOWN";
  }
  if (input.source === "NONE") return "ECF_DGII_VERIFICATION_SOURCE_REQUIRED";
  if (input.source === "DGII_OFFICIAL_RECORD") {
    if (!input.evidenceId?.trim()) return "ECF_DGII_OFFICIAL_EVIDENCE_REQUIRED";
    if (!input.externalId?.trim()) return "ECF_DGII_OFFICIAL_EXTERNAL_ID_REQUIRED";
  }
  return null;
}

// ---------------------------------------------------------------------------
// Requisitos y progreso
// ---------------------------------------------------------------------------

export type EcfDgiiRequirement = {
  /** Clave estable del requisito. */
  key: string;
  /** Etiqueta para la interfaz. */
  label: string;
  /** Etapa canónica de `EcfOnboardingStepKey` que corresponde a este requisito. */
  stepKey: string;
  /** Un requisito obligatorio impide considerar completa la habilitación. */
  mandatory: boolean;
  /**
   * `true` si el requisito lo resuelve el producto automáticamente; `false` si
   * depende de un trámite externo (DGII / Alanube) que no se puede automatizar
   * sin evidencia oficial.
   */
  automatable: boolean;
};

/**
 * Catálogo de requisitos derivado de las etapas canónicas ya existentes.
 *
 * Es una vista informativa del proceso: no sustituye ninguna resolución oficial.
 * `automatable: false` marca los pasos que requieren trámite y evidencia externa.
 */
export const ECF_DGII_REQUIREMENT_CATALOG: readonly EcfDgiiRequirement[] = [
  { key: "FISCAL_DATA", label: "Datos fiscales de la empresa", stepKey: "FISCAL_CONFIG", mandatory: true, automatable: true },
  { key: "REQUIREMENTS", label: "Requisitos y documentación", stepKey: "REQUIREMENTS", mandatory: true, automatable: false },
  { key: "DIGITAL_CERTIFICATE", label: "Certificado digital", stepKey: "DIGITAL_CERTIFICATE", mandatory: true, automatable: false },
  { key: "ALANUBE_REGISTRATION", label: "Registro en el proveedor", stepKey: "ALANUBE_REGISTRATION", mandatory: true, automatable: false },
  { key: "DGII_POSTULATION", label: "Solicitud de incorporación", stepKey: "DGII_POSTULATION", mandatory: true, automatable: false },
  { key: "XML_SIGNATURE", label: "Firma XML", stepKey: "XML_SIGNATURE", mandatory: true, automatable: false },
  { key: "SET_TESTS", label: "Pruebas del SET", stepKey: "SET_TESTS", mandatory: true, automatable: false },
  { key: "SIMULATIONS", label: "Simulaciones", stepKey: "SIMULATIONS", mandatory: true, automatable: false },
  { key: "PRINTED_REPRESENTATION", label: "Representación impresa", stepKey: "PRINTED_REPRESENTATION", mandatory: false, automatable: true },
  { key: "SERVICE_URLS", label: "URLs de servicio", stepKey: "SERVICE_URLS", mandatory: true, automatable: false },
  { key: "SWORN_DECLARATION", label: "Declaración jurada", stepKey: "SWORN_DECLARATION", mandatory: true, automatable: false },
  { key: "FINAL_AUTHORIZATION", label: "Autorización final", stepKey: "FINAL_AUTHORIZATION", mandatory: true, automatable: false },
  { key: "ENCF_REQUEST", label: "Solicitud de e-NCF", stepKey: "ENCF_REQUEST", mandatory: true, automatable: false },
  { key: "ROLE_ASSIGNMENT", label: "Asignación de roles (OFV)", stepKey: "ROLE_ASSIGNMENT", mandatory: true, automatable: false },
  { key: "PRODUCTION_ENABLEMENT", label: "Habilitación de producción", stepKey: "PRODUCTION_ENABLEMENT", mandatory: true, automatable: false },
];

/** Estados de etapa que cuentan como resueltos. */
const RESOLVED_STEP_STATUSES = new Set(["COMPLETED", "CONFIRMED"]);

export type EcfDgiiRequirementProgress = {
  key: string;
  label: string;
  stepKey: string;
  mandatory: boolean;
  automatable: boolean;
  status: string;
  resolved: boolean;
};

export type EcfDgiiProgress = {
  requirements: EcfDgiiRequirementProgress[];
  total: number;
  resolvedCount: number;
  mandatoryTotal: number;
  mandatoryResolved: number;
  percent: number;
  pendingMandatory: string[];
};

/** Cruza el catálogo con el estado real de las etapas de la empresa. */
export function buildRequirementProgress(
  steps: readonly { stepKey: string; status: string }[],
): EcfDgiiProgress {
  const byStep = new Map(steps.map((step) => [step.stepKey, step.status]));
  const requirements = ECF_DGII_REQUIREMENT_CATALOG.map((requirement) => {
    const status = byStep.get(requirement.stepKey) ?? "PENDING";
    return {
      key: requirement.key,
      label: requirement.label,
      stepKey: requirement.stepKey,
      mandatory: requirement.mandatory,
      automatable: requirement.automatable,
      status,
      resolved: RESOLVED_STEP_STATUSES.has(status),
    };
  });

  const resolvedCount = requirements.filter((item) => item.resolved).length;
  const mandatory = requirements.filter((item) => item.mandatory);
  const mandatoryResolved = mandatory.filter((item) => item.resolved).length;
  const pendingMandatory = mandatory
    .filter((item) => !item.resolved)
    .map((item) => item.key);

  return {
    requirements,
    total: requirements.length,
    resolvedCount,
    mandatoryTotal: mandatory.length,
    mandatoryResolved,
    percent: requirements.length === 0
      ? 0
      : Math.round((resolvedCount / requirements.length) * 100),
    pendingMandatory,
  };
}

// ---------------------------------------------------------------------------
// Puerta de emisión (fail-closed)
// ---------------------------------------------------------------------------

/**
 * La emisión real NO está implementada en este producto. La constante es la
 * única fuente de verdad de ese hecho y no depende de configuración: mientras
 * sea `false`, ninguna combinación de estados puede autorizar emisión real.
 */
export const PRODUCTION_EMISSION_IMPLEMENTED = false;

export type EcfEmissionGateInput = {
  moduleEnabled: boolean;
  certificationStatus: string | null;
  productionEnabled: boolean;
  fiscalConfigurationValid: boolean;
  licenseAllowsEcf: boolean;
  environment: string;
  officialAuthorization: boolean;
  pendingMandatoryRequirements: readonly string[];
};

export type EcfEmissionGateBlocker = { code: string; message: string };

export type EcfEmissionGateResult = {
  /** Emisión real contra el proveedor/DGII. Siempre `false` en esta versión. */
  realEmissionAuthorized: boolean;
  /** Despacho contra el proveedor SIMULADO (solo UAT local). */
  simulatedDispatchAuthorized: boolean;
  /** Declara explícitamente que la emisión real no está implementada. */
  productionEmissionImplemented: boolean;
  blockers: EcfEmissionGateBlocker[];
};

const LOCAL_UAT_ENVIRONMENTS = new Set(["uat", "test"]);

/**
 * Evalúa si la empresa podría emitir. Devuelve SIEMPRE la lista de bloqueos
 * para que la interfaz pueda explicar qué falta, y `realEmissionAuthorized`
 * permanece `false` mientras la emisión real no esté implementada.
 */
export function evaluateEcfEmissionGate(
  input: EcfEmissionGateInput,
): EcfEmissionGateResult {
  const blockers: EcfEmissionGateBlocker[] = [];

  if (!input.moduleEnabled) {
    blockers.push({
      code: "ECF_MODULE_DISABLED",
      message: "El módulo e-CF está desactivado para esta empresa.",
    });
  }
  if (!input.fiscalConfigurationValid) {
    blockers.push({
      code: "ECF_FISCAL_CONFIGURATION_INVALID",
      message: "La configuración fiscal de la empresa no es válida.",
    });
  }
  if (!input.licenseAllowsEcf) {
    blockers.push({
      code: "ECF_LICENSE_NOT_ALLOWED",
      message: "La licencia o los permisos no permiten la operación e-CF.",
    });
  }
  if (input.pendingMandatoryRequirements.length > 0) {
    blockers.push({
      code: "ECF_DGII_REQUIREMENTS_PENDING",
      message: `Faltan requisitos obligatorios de habilitación (${input.pendingMandatoryRequirements.length}).`,
    });
  }
  if (!input.officialAuthorization) {
    blockers.push({
      code: "ECF_DGII_OFFICIAL_AUTHORIZATION_MISSING",
      message:
        "No existe una autorización oficial de emisión verificada para esta empresa.",
    });
  }
  if (!input.productionEnabled) {
    blockers.push({
      code: "ECF_PRODUCTION_NOT_ENABLED",
      message: "La habilitación productiva de la empresa no está habilitada.",
    });
  }
  if (input.certificationStatus !== "PRODUCTION_READY") {
    blockers.push({
      code: "ECF_CERTIFICATION_NOT_PRODUCTION_READY",
      message: "La certificación de la empresa no está lista para producción.",
    });
  }
  if (!PRODUCTION_EMISSION_IMPLEMENTED) {
    blockers.push({
      code: "ECF_REAL_EMISSION_NOT_IMPLEMENTED",
      message:
        "La emisión real contra el proveedor no está implementada en esta versión.",
    });
  }
  if (!LOCAL_UAT_ENVIRONMENTS.has((input.environment ?? "").trim().toLowerCase())) {
    blockers.push({
      code: "ECF_ENVIRONMENT_NOT_LOCAL_UAT",
      message: "El entorno no es UAT local autorizado.",
    });
  }

  const environmentIsLocalUat = LOCAL_UAT_ENVIRONMENTS.has(
    (input.environment ?? "").trim().toLowerCase(),
  );

  return {
    realEmissionAuthorized: false,
    // El simulador solo exige módulo activo y entorno UAT local: no consume
    // numeración oficial ni contacta al proveedor real.
    simulatedDispatchAuthorized: input.moduleEnabled && environmentIsLocalUat,
    productionEmissionImplemented: PRODUCTION_EMISSION_IMPLEMENTED,
    blockers,
  };
}

// ---------------------------------------------------------------------------
// Evidencias: origen, revisión y nivel de confianza
// ---------------------------------------------------------------------------

/** Estados de revisión INTERNA de una evidencia. */
export const ECF_EVIDENCE_REVIEW_STATUSES = [
  "PENDING",
  "REVIEWED",
  "REJECTED",
] as const;
export type EcfEvidenceReviewStatus =
  (typeof ECF_EVIDENCE_REVIEW_STATUSES)[number];

/**
 * Nivel de confianza de una evidencia.
 *
 * Es la combinación de DOS hechos independientes: quién la entregó (`source`) y
 * si alguien la revisó (`reviewStatus`). Ninguno de los dos, por sí solo,
 * equivale a una autorización oficial de la DGII.
 */
export const ECF_EVIDENCE_LEVELS = [
  "DECLARED_BY_COMPANY",
  "INTERNALLY_REVIEWED",
  "PROVIDER_ISSUED",
  "OFFICIAL_DOCUMENT_PENDING_REVIEW",
  "OFFICIAL_DOCUMENT_REVIEWED",
] as const;
export type EcfEvidenceLevel = (typeof ECF_EVIDENCE_LEVELS)[number];

/** Calcula el nivel a partir del origen y la revisión. */
export function evidenceLevel(input: {
  source: string;
  reviewStatus: string;
}): EcfEvidenceLevel {
  if (input.source === "OFFICIAL_DOCUMENT") {
    return input.reviewStatus === "REVIEWED"
      ? "OFFICIAL_DOCUMENT_REVIEWED"
      : "OFFICIAL_DOCUMENT_PENDING_REVIEW";
  }
  if (input.source === "PROVIDER_ARTIFACT") return "PROVIDER_ISSUED";
  if (input.reviewStatus === "REVIEWED") return "INTERNALLY_REVIEWED";
  return "DECLARED_BY_COMPANY";
}

/**
 * Una evidencia **nunca** concede autorización por sí misma, sea cual sea su
 * nivel: la autorización oficial es un registro aparte con fuente oficial.
 * Esta función existe para que esa afirmación sea comprobable, no retórica.
 */
export function evidenceGrantsOfficialAuthorization(): false {
  return false;
}

/** Motivo por el que NO se puede registrar la revisión pedida, o `null`. */
export function evidenceReviewRefusal(input: {
  decision: string;
  note?: string | null;
  currentStatus: string;
  reviewedBySameUser?: boolean;
}): string | null {
  if (!(ECF_EVIDENCE_REVIEW_STATUSES as readonly string[]).includes(input.decision)) {
    return "ECF_DGII_EVIDENCE_REVIEW_DECISION_UNKNOWN";
  }
  if (input.decision === "PENDING") {
    return "ECF_DGII_EVIDENCE_REVIEW_DECISION_REQUIRED";
  }
  // Rechazar exige motivo: un rechazo sin justificación no es auditable.
  if (input.decision === "REJECTED" && !(input.note ?? "").trim()) {
    return "ECF_DGII_EVIDENCE_REJECTION_REASON_REQUIRED";
  }
  if (
    input.currentStatus === input.decision &&
    input.reviewedBySameUser === true
  ) {
    return "ECF_DGII_EVIDENCE_REVIEW_UNCHANGED";
  }
  return null;
}

/**
 * `true` solo si la evidencia puede sustentar una autorización oficial:
 * documento OFICIAL **y** ya revisado internamente.
 *
 * Una declaración manual —revisada o no— y un artefacto del proveedor quedan
 * fuera: no son prueba de una resolución de la DGII.
 */
export function evidenceSupportsOfficialAuthorization(input: {
  source: string;
  reviewStatus: string;
}): boolean {
  return (
    input.source === "OFFICIAL_DOCUMENT" && input.reviewStatus === "REVIEWED"
  );
}

/** Motivo por el que una evidencia no sirve para registrar la autorización. */
export function evidenceQualityRefusal(input: {
  source: string;
  reviewStatus: string;
}): string | null {
  if (evidenceSupportsOfficialAuthorization(input)) return null;
  if (input.source !== "OFFICIAL_DOCUMENT") {
    return "ECF_DGII_AUTHORIZATION_REQUIRES_OFFICIAL_EVIDENCE";
  }
  return "ECF_DGII_AUTHORIZATION_REQUIRES_REVIEWED_EVIDENCE";
}
