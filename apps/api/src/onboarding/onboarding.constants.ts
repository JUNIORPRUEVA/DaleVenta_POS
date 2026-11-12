export const ONBOARDING_STATUS = {
  NOT_REQUIRED: "NOT_REQUIRED",
  WELCOME_PENDING: "WELCOME_PENDING",
  IN_PROGRESS: "IN_PROGRESS",
  COMPLETED: "COMPLETED",
  SKIPPED: "SKIPPED",
} as const;

export const ONBOARDING_STEP_STATUS = {
  PENDING: "PENDING",
  COMPLETED: "COMPLETED",
  SKIPPED: "SKIPPED",
} as const;

export const TUTORIAL_STATUS = {
  NOT_REQUIRED: "NOT_REQUIRED",
  PENDING: "PENDING",
  STARTED: "STARTED",
  COMPLETED: "COMPLETED",
  SKIPPED: "SKIPPED",
} as const;

export type OnboardingStepKey = "company" | "billing" | "product" | "ready";

/**
 * Opciones validas de la pantalla de bienvenida.
 *
 * Es la unica lista que acepta el backend: el sitio publico puede mostrar
 * otras etiquetas, pero solo estas se guardan. "Otros" cierra la lista de
 * tipos de negocio.
 */
export const WELCOME_BUSINESS_TYPES = [
  "Farmacia",
  "Colmado",
  "Minimarket",
  "Supermercado",
  "Ferretería",
  "Boutique",
  "Licorería",
  "Restaurante",
  "Cafetería",
  "Panadería",
  "Repostería",
  "Barbería",
  "Salón de belleza",
  "Distribuidora",
  "Repuestos",
  "Taller mecánico",
  "Librería",
  "Papelería",
  "Tienda de celulares",
  "Agropecuaria",
  "Hotel",
  "Vinatería",
  "Heladería",
  "Joyería",
  "Zapatería",
  "Tienda de ropa",
  "Bodega",
  "Almacén",
  "Otros",
] as const;

export const WELCOME_BUSINESS_AGE_RANGES = [
  "Estoy comenzando",
  "Menos de 1 año",
  "1 a 3 años",
  "4 a 10 años",
  "Más de 10 años",
] as const;

export const WELCOME_BUSINESS_SIZES = [
  "Pequeño",
  "Mediano",
  "Grande",
] as const;

export type WelcomeProfileInput = {
  businessType?: unknown;
  businessAgeRange?: unknown;
  businessSize?: unknown;
};

export function shouldRequireOnboarding(company: {
  onboardingRequired?: boolean | null;
  onboardingStatus?: string | null;
}) {
  if (company.onboardingRequired !== true) return false;
  return (
    company.onboardingStatus === ONBOARDING_STATUS.WELCOME_PENDING ||
    company.onboardingStatus === ONBOARDING_STATUS.IN_PROGRESS
  );
}
