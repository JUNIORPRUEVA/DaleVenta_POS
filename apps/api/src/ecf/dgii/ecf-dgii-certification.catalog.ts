export type EcfCertificationAutomationClass =
  | "AUTOMATIZABLE_CONFIRMED"
  | "MANUAL_REQUIRED"
  | "PROVIDER_DEPENDENT"
  | "DGII_DEPENDENT"
  | "UNKNOWN";

export type EcfCertificationCatalogStep = {
  key: string;
  title: string;
  automation: EcfCertificationAutomationClass;
  requiresEvidence: boolean;
  blocksProductionEmission: boolean;
  notes: string[];
};

export const ECF_DGII_CERTIFICATION_CATALOG: EcfCertificationCatalogStep[] = [
  {
    key: "REQUIREMENTS",
    title: "Requisitos internos y fiscales",
    automation: "MANUAL_REQUIRED",
    requiresEvidence: true,
    blocksProductionEmission: true,
    notes: ["Validar RNC, razón social, actividad y responsable autorizado."],
  },
  {
    key: "ALANUBE_REGISTRATION",
    title: "Registro o asociación en Alanube",
    automation: "PROVIDER_DEPENDENT",
    requiresEvidence: true,
    blocksProductionEmission: true,
    notes: ["No se asume que la cuenta reseller autoriza emisión por cliente."],
  },
  {
    key: "DGII_POSTULATION",
    title: "Postulación o habilitación DGII",
    automation: "DGII_DEPENDENT",
    requiresEvidence: true,
    blocksProductionEmission: true,
    notes: ["No se realizan acciones ante DGII desde FullPOS en esta fase."],
  },
  {
    key: "SIMULATIONS",
    title: "Pruebas de certificación",
    automation: "PROVIDER_DEPENDENT",
    requiresEvidence: true,
    blocksProductionEmission: true,
    notes: ["Las pruebas reales requieren contrato Sandbox autorizado."],
  },
  {
    key: "FINAL_AUTHORIZATION",
    title: "Autorización final",
    automation: "MANUAL_REQUIRED",
    requiresEvidence: true,
    blocksProductionEmission: true,
    notes: ["No puede declararse sin evidencia verificable."],
  },
];
