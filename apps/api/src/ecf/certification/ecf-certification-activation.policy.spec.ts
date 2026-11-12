import { EcfCertificationStatus } from "@prisma/client";
import {
  canDerivePromotion,
  deriveCertificationFromCredentials,
} from "./ecf-certification-activation.policy";

/**
 * Pruebas de la DERIVACIÓN del estado de certificación a partir de credenciales.
 *
 * Es la regla que permite al cliente autorizarse a sí mismo emitiendo su propia
 * evidencia, así que se prueba exhaustivamente: qué estado sostiene cada
 * combinación y, sobre todo, que la AUSENCIA de credencial no autoriza nada.
 */
describe("derivación del estado de certificación desde credenciales", () => {
  const cred = (environment: string, status: string) => ({ environment, status });

  describe("qué estado sostiene la evidencia", () => {
    it("production ACTIVE autoriza producción", () => {
      expect(deriveCertificationFromCredentials([cred("production", "ACTIVE")])).toBe(
        EcfCertificationStatus.PRODUCTION_READY,
      );
    });

    it("test ACTIVE autoriza solo sandbox", () => {
      expect(deriveCertificationFromCredentials([cred("test", "ACTIVE")])).toBe(
        EcfCertificationStatus.AUTHORIZED_SANDBOX,
      );
    });

    it("producción gana cuando ambas están activas", () => {
      expect(
        deriveCertificationFromCredentials([
          cred("test", "ACTIVE"),
          cred("production", "ACTIVE"),
        ]),
      ).toBe(EcfCertificationStatus.PRODUCTION_READY);
    });

    it("test activa con producción pendiente no adelanta producción", () => {
      expect(
        deriveCertificationFromCredentials([
          cred("test", "ACTIVE"),
          cred("production", "PENDING_CONFIRMATION"),
        ]),
      ).toBe(EcfCertificationStatus.AUTHORIZED_SANDBOX);
    });
  });

  describe("la ausencia de evidencia no autoriza", () => {
    it("sin ninguna credencial registrada no deriva estado", () => {
      expect(deriveCertificationFromCredentials([])).toBeNull();
    });

    it("una credencial en TEST pendiente no autoriza", () => {
      expect(
        deriveCertificationFromCredentials([cred("test", "PENDING_CONFIRMATION")]),
      ).toBeNull();
    });

    it("una credencial de producción solo confirmada no autoriza", () => {
      expect(
        deriveCertificationFromCredentials([cred("production", "CONFIRMED")]),
      ).toBeNull();
    });

    it("una credencial REVOKED no autoriza, ni siquiera en producción", () => {
      expect(deriveCertificationFromCredentials([cred("production", "REVOKED")])).toBeNull();
    });

    it("test REVOKED con producción ausente no autoriza", () => {
      expect(deriveCertificationFromCredentials([cred("test", "REVOKED")])).toBeNull();
    });
  });

  describe("tolerancia de formato", () => {
    it("acepta el estado en minúsculas y el entorno con espacios", () => {
      expect(deriveCertificationFromCredentials([cred(" Test ", "active")])).toBe(
        EcfCertificationStatus.AUTHORIZED_SANDBOX,
      );
    });

    it("ignora un entorno desconocido", () => {
      expect(deriveCertificationFromCredentials([cred("staging", "ACTIVE")])).toBeNull();
    });

    it("no revienta con valores vacíos", () => {
      expect(
        deriveCertificationFromCredentials([{ environment: "", status: "" }]),
      ).toBeNull();
    });
  });

  describe("bloqueo", () => {
    it("no se promociona por encima de un bloqueo real", () => {
      expect(
        canDerivePromotion({ current: EcfCertificationStatus.BLOCKED }),
      ).toBe(false);
    });

    it.each([
      EcfCertificationStatus.NOT_STARTED,
      EcfCertificationStatus.IN_PROGRESS,
      EcfCertificationStatus.READY_FOR_REVIEW,
      EcfCertificationStatus.AUTHORIZED_SANDBOX,
      EcfCertificationStatus.PRODUCTION_READY,
      EcfCertificationStatus.SUSPENDED,
    ])("el resto de estados admite evaluación (%s)", (current) => {
      expect(canDerivePromotion({ current })).toBe(true);
    });
  });
});
