import { EcfCertificationStatus } from "@prisma/client";
import {
  ECF_CERTIFICATION_GRANT_TARGETS,
  ECF_CERTIFICATION_REFUSALS,
  ECF_CERTIFICATION_REVOKED_STATE,
  decideCertificationGrant,
  decideCertificationRevoke,
  isCertificationGrantTarget,
} from "./ecf-certification-authorization.policy";

/**
 * Pruebas de la POLÍTICA de autorización de emisión.
 *
 * Es la pieza que decide quién puede emitir, así que la tabla de transiciones se
 * prueba completa: cada estado de origen contra cada objetivo.
 */
describe("política de autorización de certificación e-CF", () => {
  const ALL = Object.values(EcfCertificationStatus);

  describe("objetivos asignables", () => {
    it("solo sandbox y producción son asignables por esta vía", () => {
      expect([...ECF_CERTIFICATION_GRANT_TARGETS]).toEqual([
        "AUTHORIZED_SANDBOX",
        "PRODUCTION_READY",
      ]);
      expect(isCertificationGrantTarget("SUSPENDED")).toBe(false);
      expect(isCertificationGrantTarget("NOT_STARTED")).toBe(false);
      expect(isCertificationGrantTarget("BLOCKED")).toBe(false);
      expect(isCertificationGrantTarget("")).toBe(false);
    });

    it("un objetivo fuera del catálogo se rechaza sin escribir", () => {
      const decision = decideCertificationGrant({
        current: EcfCertificationStatus.IN_PROGRESS,
        target: "DGII_ACCEPTED",
      });
      expect(decision).toEqual({
        ok: false,
        blockedReason: ECF_CERTIFICATION_REFUSALS.TARGET_NOT_ALLOWED,
      });
    });
  });

  describe("sandbox", () => {
    it.each([
      EcfCertificationStatus.NOT_STARTED,
      EcfCertificationStatus.IN_PROGRESS,
      EcfCertificationStatus.READY_FOR_REVIEW,
      EcfCertificationStatus.SUSPENDED,
    ])("autoriza sandbox desde %s", (current) => {
      const decision = decideCertificationGrant({
        current,
        target: "AUTHORIZED_SANDBOX",
      });
      expect(decision).toEqual({
        ok: true,
        changed: true,
        from: current,
        to: EcfCertificationStatus.AUTHORIZED_SANDBOX,
      });
    });

    it("repetir la misma autorización es idempotente", () => {
      const decision = decideCertificationGrant({
        current: EcfCertificationStatus.AUTHORIZED_SANDBOX,
        target: "AUTHORIZED_SANDBOX",
      });
      expect(decision).toEqual({
        ok: true,
        changed: false,
        from: EcfCertificationStatus.AUTHORIZED_SANDBOX,
        to: EcfCertificationStatus.AUTHORIZED_SANDBOX,
      });
    });

    it("no rebaja una autorización de producción", () => {
      const decision = decideCertificationGrant({
        current: EcfCertificationStatus.PRODUCTION_READY,
        target: "AUTHORIZED_SANDBOX",
      });
      expect(decision).toEqual({
        ok: false,
        blockedReason: ECF_CERTIFICATION_REFUSALS.DOWNGRADE_NOT_ALLOWED,
      });
    });
  });

  describe("producción", () => {
    it("exige haber pasado por sandbox", () => {
      const decision = decideCertificationGrant({
        current: EcfCertificationStatus.NOT_STARTED,
        target: "PRODUCTION_READY",
      });
      expect(decision).toEqual({
        ok: false,
        blockedReason: ECF_CERTIFICATION_REFUSALS.SANDBOX_REQUIRED,
      });
    });

    it.each([
      EcfCertificationStatus.IN_PROGRESS,
      EcfCertificationStatus.READY_FOR_REVIEW,
    ])("no se concede desde %s sin sandbox previo", (current) => {
      expect(
        decideCertificationGrant({ current, target: "PRODUCTION_READY" }),
      ).toEqual({
        ok: false,
        blockedReason: ECF_CERTIFICATION_REFUSALS.SANDBOX_REQUIRED,
      });
    });

    it("se concede desde sandbox", () => {
      const decision = decideCertificationGrant({
        current: EcfCertificationStatus.AUTHORIZED_SANDBOX,
        target: "PRODUCTION_READY",
      });
      expect(decision).toEqual({
        ok: true,
        changed: true,
        from: EcfCertificationStatus.AUTHORIZED_SANDBOX,
        to: EcfCertificationStatus.PRODUCTION_READY,
      });
    });

    it("una empresa suspendida no salta a producción", () => {
      const decision = decideCertificationGrant({
        current: EcfCertificationStatus.SUSPENDED,
        target: "PRODUCTION_READY",
      });
      expect(decision.ok).toBe(false);
    });
  });

  describe("bloqueo", () => {
    it.each([...ECF_CERTIFICATION_GRANT_TARGETS])(
      "no autoriza %s por encima de un bloqueo real",
      (target) => {
        expect(
          decideCertificationGrant({
            current: EcfCertificationStatus.BLOCKED,
            target,
          }),
        ).toEqual({
          ok: false,
          blockedReason: ECF_CERTIFICATION_REFUSALS.STATE_BLOCKED,
        });
      },
    );
  });

  describe("tabla completa de concesión", () => {
    // Cada estado de origen contra los dos objetivos: un solo sitio donde se ve
    // si una transición nueva se abre o se cierra sin querer.
    const table = ALL.flatMap((current) =>
      ECF_CERTIFICATION_GRANT_TARGETS.map((target) => ({
        current,
        target,
        ok: decideCertificationGrant({ current, target }).ok,
      })),
    );

    it("solo sandbox y producción quedan autorizados, y nunca desde BLOCKED", () => {
      const allowed = table
        .filter((row) => row.ok)
        .map((row) => `${row.current}->${row.target}`);
      expect(allowed.sort()).toEqual(
        [
          "AUTHORIZED_SANDBOX->AUTHORIZED_SANDBOX",
          "IN_PROGRESS->AUTHORIZED_SANDBOX",
          "NOT_STARTED->AUTHORIZED_SANDBOX",
          "READY_FOR_REVIEW->AUTHORIZED_SANDBOX",
          "SUSPENDED->AUTHORIZED_SANDBOX",
          "AUTHORIZED_SANDBOX->PRODUCTION_READY",
          "PRODUCTION_READY->PRODUCTION_READY",
        ].sort(),
      );
    });
  });

  describe("revocación", () => {
    it.each([
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
      EcfCertificationStatus.PRODUCTION_READY,
    ])("revoca %s dejando SUSPENDED", (current) => {
      expect(decideCertificationRevoke({ current })).toEqual({
        ok: true,
        changed: true,
        from: current,
        to: ECF_CERTIFICATION_REVOKED_STATE,
      });
    });

    it("revocar dos veces es idempotente", () => {
      expect(
        decideCertificationRevoke({ current: EcfCertificationStatus.SUSPENDED }),
      ).toEqual({
        ok: true,
        changed: false,
        from: EcfCertificationStatus.SUSPENDED,
        to: ECF_CERTIFICATION_REVOKED_STATE,
      });
    });

    it.each([
      EcfCertificationStatus.NOT_STARTED,
      EcfCertificationStatus.IN_PROGRESS,
      EcfCertificationStatus.READY_FOR_REVIEW,
      EcfCertificationStatus.BLOCKED,
    ])("no hay nada que revocar en %s", (current) => {
      expect(decideCertificationRevoke({ current })).toEqual({
        ok: false,
        blockedReason: ECF_CERTIFICATION_REFUSALS.NOT_AUTHORIZED,
      });
    });

    it("revocar nunca deja NOT_STARTED (se retiró algo, no es que no empezara)", () => {
      for (const current of ALL) {
        const decision = decideCertificationRevoke({ current });
        if (decision.ok) {
          expect(decision.to).toBe(EcfCertificationStatus.SUSPENDED);
          expect(decision.to).not.toBe(EcfCertificationStatus.NOT_STARTED);
        }
      }
    });
  });
});
