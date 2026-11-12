/**
 * Catálogo del onboarding de activación «Activa tu FullPOS».
 *
 * Fuente única de la lista de tareas. El backend decide el ESTADO de cada
 * tarea a partir de datos reales de la empresa; este archivo solo declara
 * qué tareas existen, en qué fase viven y cómo se presentan.
 *
 * Reglas:
 * - `optional` = se puede omitir sin marcarla como completada.
 * - `minutes` = duración estimada, solo informativa.
 * - Ninguna tarea crea, modifica ni elimina datos por sí misma.
 */

export const ACTIVATION_PHASE_KEYS = ["sell", "customize"] as const;
export type ActivationPhaseKey = (typeof ACTIVATION_PHASE_KEYS)[number];

export const ACTIVATION_TASK_KEYS = [
  "account",
  "products",
  "firstSale",
  "business",
  "taxes",
  "tickets",
  "ecf",
] as const;
export type ActivationTaskKey = (typeof ACTIVATION_TASK_KEYS)[number];

export type ActivationTaskDefinition = {
  key: ActivationTaskKey;
  phase: ActivationPhaseKey;
  title: string;
  description: string;
  minutes: number;
  actionLabel: string;
  /** Clave semántica de destino; el cliente la traduce a su propia ruta. */
  destination: string;
  /** Nombre del icono en el cliente; no se envía SVG ni asset. */
  icon: string;
  optional: boolean;
  tourSteps: number;
};

export type ActivationPhaseDefinition = {
  key: ActivationPhaseKey;
  title: string;
  subtitle: string;
};

export const ACTIVATION_PHASES: readonly ActivationPhaseDefinition[] = [
  {
    key: "sell",
    title: "Empieza a vender",
    subtitle: "Lo mínimo para cobrar hoy.",
  },
  {
    key: "customize",
    title: "Personaliza tu FullPOS",
    subtitle: "Deja el sistema a la medida de tu negocio.",
  },
] as const;

export const ACTIVATION_TASKS: readonly ActivationTaskDefinition[] = [
  {
    key: "account",
    phase: "sell",
    title: "Crea tu cuenta",
    description:
      "Tu cuenta está lista. Ya puedes configurar tu negocio y empezar a cobrar.",
    minutes: 0,
    actionLabel: "Continuar",
    destination: "pos",
    icon: "check",
    optional: false,
    tourSteps: 0,
  },
  {
    key: "products",
    phase: "sell",
    title: "Registra tus productos",
    description:
      "Con tu catálogo cargado, cobrar una venta toma segundos.",
    minutes: 2,
    actionLabel: "Registrar productos",
    destination: "catalog",
    icon: "box",
    optional: true,
    tourSteps: 2,
  },
  {
    key: "firstSale",
    phase: "sell",
    title: "Haz tu primera venta",
    description:
      "Cobra tu primera venta y comprueba el flujo completo del punto de venta.",
    minutes: 2,
    actionLabel: "Empezar",
    destination: "pos",
    icon: "receipt",
    optional: true,
    tourSteps: 3,
  },
  {
    key: "business",
    phase: "customize",
    title: "Completa los datos de tu negocio",
    description:
      "Nombre comercial, RNC y teléfono: lo que aparece impreso en cada comprobante.",
    minutes: 2,
    actionLabel: "Completar datos",
    destination: "company",
    icon: "store",
    // Omitible: no todas las empresas tienen RNC (informal / solo tickets).
    // Bloquear el flujo por un dato que no todos pueden aportar dejaría el
    // asistente imposible de cerrar.
    optional: true,
    tourSteps: 0,
  },
  {
    key: "taxes",
    phase: "customize",
    title: "Configura impuestos",
    description:
      "Define si tus precios llevan ITBIS y con qué tasa trabajas.",
    minutes: 2,
    actionLabel: "Configurar",
    // El interruptor de impuestos y el panel «Impuestos y e-CF» viven dentro de
    // Configuración › Empresa, no en «Parámetros» (que es una ficha informativa).
    destination: "company",
    icon: "percent",
    optional: true,
    tourSteps: 0,
  },
  {
    key: "tickets",
    phase: "customize",
    title: "Personaliza tus tickets con tu logo",
    description:
      "Sube el logo y los datos de tu negocio que aparecen impresos en cada ticket.",
    minutes: 1,
    actionLabel: "Personalizar",
    // La señal medida es el logo y se carga en Configuración › Empresa.
    destination: "company",
    icon: "printer",
    optional: true,
    tourSteps: 0,
  },
  {
    key: "ecf",
    phase: "customize",
    title: "Activa la factura electrónica",
    description:
      "Emite comprobantes que cumplen los requisitos de la DGII desde el POS.",
    minutes: 5,
    actionLabel: "Activar",
    destination: "ecf",
    icon: "shield",
    optional: true,
    tourSteps: 0,
  },
] as const;

export const ACTIVATION_TASK_BY_KEY: Record<
  ActivationTaskKey,
  ActivationTaskDefinition
> = ACTIVATION_TASKS.reduce(
  (acc, task) => {
    acc[task.key] = task;
    return acc;
  },
  {} as Record<ActivationTaskKey, ActivationTaskDefinition>,
);

export function isActivationTaskKey(value: string): value is ActivationTaskKey {
  return Object.prototype.hasOwnProperty.call(ACTIVATION_TASK_BY_KEY, value);
}

/**
 * Estado final de una tarea para el cliente.
 *
 * - `DONE`    → se deduce de los datos reales; no se puede forzar.
 * - `SKIPPED` → el usuario la omitió explícitamente (override persistido).
 * - `PENDING` → sigue pendiente.
 */
export const ACTIVATION_TASK_STATE = {
  DONE: "DONE",
  SKIPPED: "SKIPPED",
  PENDING: "PENDING",
} as const;

export type ActivationTaskState =
  (typeof ACTIVATION_TASK_STATE)[keyof typeof ACTIVATION_TASK_STATE];
