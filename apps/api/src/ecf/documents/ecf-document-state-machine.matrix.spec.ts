import { EcfElectronicDocumentStatus } from "@prisma/client";
import {
  canTransitionEcfDocument,
  ECF_DOCUMENT_TRANSITIONS,
} from "./ecf-document-state-machine";

/**
 * Matriz EXHAUSTIVA de la máquina de estados fiscales.
 *
 * La política se declara aquí de forma independiente y se compara contra la
 * implementación: 14 × 14 pares, con y sin evidencia. Los invariantes fiscales
 * se afirman como propiedades, no como casos sueltos.
 */

const ALL: EcfElectronicDocumentStatus[] = [
  "LOCAL_DRAFT",
  "LOCAL_VALIDATION_PENDING",
  "LOCAL_VALIDATED",
  "READY_TO_SEND",
  "SEND_PENDING",
  "SEND_IN_PROGRESS",
  "UNKNOWN_RESULT",
  "PROVIDER_ACCEPTED",
  "PROVIDER_REJECTED",
  "DGII_STATUS_PENDING",
  "DGII_ACCEPTED",
  "DGII_REJECTED",
  "HUMAN_REVIEW_REQUIRED",
  "CANCELLED",
];

/** Estados que solo pueden alcanzarse con evidencia verificable. */
const EVIDENCE_REQUIRED: EcfElectronicDocumentStatus[] = [
  "PROVIDER_ACCEPTED",
  "PROVIDER_REJECTED",
  "DGII_ACCEPTED",
  "DGII_REJECTED",
];

/** Estados terminales: no salen de ellos. */
const TERMINAL: EcfElectronicDocumentStatus[] = ["CANCELLED"];

/** Ruta fiscal mínima hasta una aceptación de la DGII. */
const DGII_ACCEPTANCE_PATH: EcfElectronicDocumentStatus[] = [
  "PROVIDER_ACCEPTED",
  "DGII_STATUS_PENDING",
  "DGII_ACCEPTED",
];

describe("máquina de estados e-CF — matriz de transiciones", () => {
  it("el esquema persiste exactamente los 14 estados que cubre la matriz", () => {
    expect(ALL).toHaveLength(14);
    expect(new Set(ALL).size).toBe(14);
    expect(Object.keys(ECF_DOCUMENT_TRANSITIONS).sort()).toEqual([...ALL].sort());
  });

  it("cada estado declara sus salidas y ninguna apunta a un estado inexistente", () => {
    for (const from of ALL) {
      const targets = ECF_DOCUMENT_TRANSITIONS[from];
      expect(Array.isArray(targets)).toBe(true);
      for (const to of targets) {
        expect(ALL).toContain(to);
      }
    }
  });

  it("evalúa los 196 pares sin ambigüedad ni excepción", () => {
    for (const from of ALL) {
      for (const to of ALL) {
        const withoutEvidence = canTransitionEcfDocument(from, to);
        const withEvidence = canTransitionEcfDocument(from, to, { hasEvidence: true });
        expect(typeof withoutEvidence.ok).toBe("boolean");
        expect(typeof withEvidence.ok).toBe("boolean");
        // La decisión depende de (from, to, evidencia), nunca de una ejecución previa.
        expect(canTransitionEcfDocument(from, to)).toEqual(withoutEvidence);
      }
    }
  });

  it("un estado siempre puede reafirmarse a sí mismo", () => {
    for (const state of ALL) {
      expect(canTransitionEcfDocument(state, state, { hasEvidence: true }).ok).toBe(true);
    }
  });

  it("solo se permite lo que la tabla declara", () => {
    for (const from of ALL) {
      const declared = new Set(ECF_DOCUMENT_TRANSITIONS[from]);
      for (const to of ALL) {
        const decision = canTransitionEcfDocument(from, to, { hasEvidence: true });
        if (from === to || declared.has(to)) {
          expect(decision.ok).toBe(true);
        } else {
          expect(decision.ok).toBe(false);
          if (!decision.ok) expect(decision.code).toBe("ECF_INVALID_STATUS_TRANSITION");
        }
      }
    }
  });

  it("los estados terminales no tienen salida, salvo reafirmarse", () => {
    for (const terminal of TERMINAL) {
      for (const to of ALL) {
        if (to === terminal) continue;
        const decision = canTransitionEcfDocument(terminal, to, { hasEvidence: true });
        expect(decision.ok).toBe(false);
      }
    }
  });
});

describe("máquina de estados e-CF — invariantes fiscales", () => {
  it("sin evidencia, ninguna aceptación ni rechazo es alcanzable", () => {
    for (const from of ALL) {
      for (const to of EVIDENCE_REQUIRED) {
        if (from === to) continue;
        const decision = canTransitionEcfDocument(from, to);
        expect(decision.ok).toBe(false);
        if (!decision.ok && ECF_DOCUMENT_TRANSITIONS[from].includes(to)) {
          // Si la transición existe, el único motivo del rechazo es la evidencia.
          expect(decision.code).toBe("ECF_STATUS_EVIDENCE_REQUIRED");
        }
      }
    }
  });

  it("con evidencia, las mismas transiciones sí se permiten", () => {
    for (const from of ALL) {
      for (const to of EVIDENCE_REQUIRED) {
        if (from === to || !ECF_DOCUMENT_TRANSITIONS[from].includes(to)) continue;
        expect(canTransitionEcfDocument(from, to, { hasEvidence: true }).ok).toBe(true);
      }
    }
  });

  it("PREPARADO no es ENVIADO: un borrador no llega a una aceptación del proveedor", () => {
    for (const from of ["LOCAL_DRAFT", "LOCAL_VALIDATION_PENDING", "LOCAL_VALIDATED", "READY_TO_SEND"] as const) {
      expect(canTransitionEcfDocument(from, "PROVIDER_ACCEPTED", { hasEvidence: true }).ok).toBe(false);
      expect(canTransitionEcfDocument(from, "DGII_ACCEPTED", { hasEvidence: true }).ok).toBe(false);
    }
  });

  it("ACEPTADO POR EL PROVEEDOR no es ACEPTADO POR LA DGII: hace falta el paso intermedio", () => {
    expect(
      canTransitionEcfDocument("PROVIDER_ACCEPTED", "DGII_ACCEPTED", { hasEvidence: true }).ok,
    ).toBe(false);
    for (let index = 0; index < DGII_ACCEPTANCE_PATH.length - 1; index += 1) {
      const step = DGII_ACCEPTANCE_PATH[index];
      const next = DGII_ACCEPTANCE_PATH[index + 1];
      expect(canTransitionEcfDocument(step, next, { hasEvidence: true }).ok).toBe(true);
    }
  });

  it("un rechazo NUNCA se convierte en aceptación", () => {
    const rejected: EcfElectronicDocumentStatus[] = ["PROVIDER_REJECTED", "DGII_REJECTED"];
    for (const from of rejected) {
      expect(canTransitionEcfDocument(from, "PROVIDER_ACCEPTED", { hasEvidence: true }).ok).toBe(false);
      expect(canTransitionEcfDocument(from, "DGII_ACCEPTED", { hasEvidence: true }).ok).toBe(false);
    }
  });

  it("la revisión humana no se resuelve sola: no promociona a aceptación", () => {
    expect(
      canTransitionEcfDocument("HUMAN_REVIEW_REQUIRED", "DGII_ACCEPTED", { hasEvidence: true }).ok,
    ).toBe(false);
    expect(
      canTransitionEcfDocument("HUMAN_REVIEW_REQUIRED", "PROVIDER_ACCEPTED", { hasEvidence: true }).ok,
    ).toBe(false);
  });

  it("un resultado desconocido no se declara aceptado sin cerrar el ciclo", () => {
    // Se permite salir del resultado desconocido por la vía normal…
    expect(canTransitionEcfDocument("UNKNOWN_RESULT", "PROVIDER_ACCEPTED", { hasEvidence: true }).ok).toBe(true);
    // …pero no saltarse el estado intermedio hacia la DGII.
    expect(canTransitionEcfDocument("UNKNOWN_RESULT", "DGII_ACCEPTED", { hasEvidence: true }).ok).toBe(false);
  });

  it("DGII_ACCEPTED solo es alcanzable desde el estado de consulta pendiente", () => {
    for (const from of ALL) {
      const reachable = canTransitionEcfDocument(from, "DGII_ACCEPTED", { hasEvidence: true }).ok;
      if (reachable && from !== "DGII_ACCEPTED") {
        expect(from).toBe("DGII_STATUS_PENDING");
      }
    }
  });

  it("el resultado observado se puede revisar o anular, pero no retroceder a borrador limpio sin revisión", () => {
    expect(canTransitionEcfDocument("HUMAN_REVIEW_REQUIRED", "CANCELLED", { hasEvidence: true }).ok).toBe(true);
    expect(canTransitionEcfDocument("PROVIDER_ACCEPTED", "SEND_IN_PROGRESS", { hasEvidence: true }).ok).toBe(false);
  });
});
