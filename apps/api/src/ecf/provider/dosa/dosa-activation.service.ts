import type { DosaCredentialService } from "./dosa-credential.service";
import type { DosaCredentialEnvironment } from "./dosa-credential-vault.service";
import {
  activationBlockers,
  type DosaActivationEvidence,
  type DosaAuthorizationReader,
} from "./dosa-activation-authority.service";

/**
 * Activación fiscal de DOSA.
 *
 * Es la única puerta que puede llevar una credencial a `ACTIVE`, y **no acepta
 * autorizaciones como argumento**: lee la evidencia de la base de datos con
 * `DosaAuthorizationReader` y decide con eso.
 *
 * Consecuencia práctica: escribir `promote({ authorized: true })` no existe como
 * camino. Para activar hay que haber producido, de verdad y en este orden:
 *
 * 1. una sesión que vincule el RNC a la empresa,
 * 2. un evento del proveedor autenticado con `estado_certificacion = finalizado`,
 * 3. una habilitación DGII `APPROVED` con origen `DGII_OFFICIAL_RECORD`,
 * 4. una acción de auditoría `DGII_AUTHORIZATION_RECORDED` con actor real, no
 *    revocada después.
 */
export class DosaActivationService {
  constructor(
    private readonly authority: DosaAuthorizationReader,
    private readonly credentials: DosaCredentialService,
  ) {}

  /** Diagnóstico sin efectos: qué falta exactamente para poder activar. */
  async evaluate(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }): Promise<{
    evidence: DosaActivationEvidence;
    blockingReasons: string[];
  }> {
    const evidence = await this.authority.read({
      companyId: input.companyId,
      rnc: input.rnc,
    });
    return { evidence, blockingReasons: activationBlockers(evidence) };
  }

  async activate(input: {
    companyId: string;
    rnc: string;
    environment: DosaCredentialEnvironment;
  }): Promise<
    | { ok: true; status: "ACTIVE"; evidence: DosaActivationEvidence }
    | { ok: false; blockingReasons: string[]; evidence: DosaActivationEvidence }
  > {
    const { evidence, blockingReasons } = await this.evaluate(input);
    if (blockingReasons.length > 0) {
      return { ok: false, blockingReasons, evidence };
    }

    const promoted = await this.credentials.promote({
      companyId: input.companyId,
      rnc: input.rnc,
      environment: input.environment,
      to: "ACTIVE",
      evidence,
    });
    if (!promoted.ok) {
      return { ok: false, blockingReasons: [promoted.blockedReason], evidence };
    }
    return { ok: true, status: "ACTIVE", evidence };
  }
}
