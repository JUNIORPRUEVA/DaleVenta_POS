import { EcfCertificationStatus } from "@prisma/client";
import {
  isReadyForReviewEvidence,
  resolveCertificationStatus,
} from "./ecf-certification-status.policy";

describe("resolveCertificationStatus — solo promociona", () => {
  it("sin estado previo se guarda el derivado", () => {
    expect(
      resolveCertificationStatus({
        current: null,
        derived: EcfCertificationStatus.READY_FOR_REVIEW,
      }),
    ).toBe(EcfCertificationStatus.READY_FOR_REVIEW);
  });

  it("una evidencia nueva promociona NOT_STARTED a READY_FOR_REVIEW", () => {
    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.NOT_STARTED,
        derived: EcfCertificationStatus.READY_FOR_REVIEW,
      }),
    ).toBe(EcfCertificationStatus.READY_FOR_REVIEW);
  });

  it("tocar una etapa NO degrada una autorización existente", () => {
    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.AUTHORIZED_SANDBOX,
        derived: EcfCertificationStatus.IN_PROGRESS,
      }),
    ).toBe(EcfCertificationStatus.AUTHORIZED_SANDBOX);

    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.PRODUCTION_READY,
        derived: EcfCertificationStatus.NOT_STARTED,
      }),
    ).toBe(EcfCertificationStatus.PRODUCTION_READY);
  });

  it("un bloqueo real siempre aflora", () => {
    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.PRODUCTION_READY,
        derived: EcfCertificationStatus.BLOCKED,
      }),
    ).toBe(EcfCertificationStatus.BLOCKED);
  });

  it("BLOCKED es pegajoso: una etapa resuelta no los borra", () => {
    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.SUSPENDED,
        derived: EcfCertificationStatus.IN_PROGRESS,
      }),
    ).toBe(EcfCertificationStatus.SUSPENDED);

    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.SUSPENDED,
        derived: EcfCertificationStatus.READY_FOR_REVIEW,
      }),
    ).toBe(EcfCertificationStatus.SUSPENDED);
  });

  // Regresión del defecto detectado en la auditoría del 07/11/2026: si BLOCKED
  // fuera pegajoso, una empresa bloqueada una vez no podría salir nunca, porque
  // ninguna otra ruta escribe `certification_status`.
  it("resolver la etapa bloqueada LEVANTA el bloqueo", () => {
    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.BLOCKED,
        derived: EcfCertificationStatus.IN_PROGRESS,
      }),
    ).toBe(EcfCertificationStatus.IN_PROGRESS);

    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.BLOCKED,
        derived: EcfCertificationStatus.READY_FOR_REVIEW,
      }),
    ).toBe(EcfCertificationStatus.READY_FOR_REVIEW);
  });

  it("un bloqueo vigente se mantiene mientras la evidencia lo diga", () => {
    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.BLOCKED,
        derived: EcfCertificationStatus.BLOCKED,
      }),
    ).toBe(EcfCertificationStatus.BLOCKED);

    // Sin avanzar: no se degrada a NOT_STARTED por sí solo.
    expect(
      resolveCertificationStatus({
        current: EcfCertificationStatus.BLOCKED,
        derived: EcfCertificationStatus.NOT_STARTED,
      }),
    ).toBe(EcfCertificationStatus.BLOCKED);
  });

  it("nunca produce un estado de certificación por inferencia", () => {
    // La función no puede devolver algo que no venga de la evidencia o de lo
    // ya guardado; en particular nunca inventa AUTHORIZED/PRODUCTION_READY.
    const derivedStates = [
      EcfCertificationStatus.NOT_STARTED,
      EcfCertificationStatus.IN_PROGRESS,
      EcfCertificationStatus.READY_FOR_REVIEW,
      EcfCertificationStatus.BLOCKED,
    ];
    for (const derived of derivedStates) {
      const result = resolveCertificationStatus({
        current: EcfCertificationStatus.NOT_STARTED,
        derived,
      });
      expect([EcfCertificationStatus.AUTHORIZED_SANDBOX, EcfCertificationStatus.PRODUCTION_READY]).not.toContain(
        result,
      );
    }
  });
});

describe("isReadyForReviewEvidence", () => {
  it("solo un evento completo cuenta como evidencia", () => {
    expect(isReadyForReviewEvidence({ completeWebhookEvents: 0 })).toBe(false);
    expect(isReadyForReviewEvidence({ completeWebhookEvents: 1 })).toBe(true);
  });
});
