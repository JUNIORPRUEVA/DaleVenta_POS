import type { EcfCanonicalIdentityService } from "../../dgii/certificate/ecf-canonical-identity.service";
import {
  DosaCertificationSessionClient,
  readDosaSessionConfig,
  type DosaSessionEnv,
} from "./dosa-certification-session.client";
import type {
  DosaContactEmailReader,
  DosaIdentityReader,
  DosaSessionClientPort,
} from "./dosa-certification-session.service";

/**
 * Adaptadores del lanzador de sesiones DOSA.
 *
 * Todos leen del BACKEND y del ámbito de la empresa autenticada. Ningún dato
 * (RNC, correo, URL) se acepta del navegador.
 */

/** Identidad canónica (RNC del expediente fiscal) reutilizada tal cual. */
export class CanonicalDosaIdentityReader implements DosaIdentityReader {
  constructor(private readonly identity: EcfCanonicalIdentityService) {}

  async resolve(companyId: string): Promise<{ taxId: string | null }> {
    const resolved = await this.identity.resolve(companyId);
    return { taxId: resolved.taxId };
  }
}

/** Forma mínima de Prisma que necesita la lectura del correo. */
export interface DosaAppConfigClient {
  appConfig: {
    findFirst(args: {
      where: { companyId: string };
      select: { ecfContactEmail: true };
    }): Promise<{ ecfContactEmail: string | null } | null>;
  };
}

/** Correo de facturación electrónica guardado UNA vez en `app_config`. */
export class PrismaDosaContactEmailReader implements DosaContactEmailReader {
  constructor(private readonly prisma: DosaAppConfigClient) {}

  async read(companyId: string): Promise<string> {
    const row = await this.prisma.appConfig.findFirst({
      where: { companyId },
      select: { ecfContactEmail: true },
    });
    return `${row?.ecfContactEmail ?? ""}`.trim();
  }
}

/** Cliente del contrato de sesiones, configurado desde el entorno. */
export function createDosaSessionClient(
  env: DosaSessionEnv = process.env,
): DosaSessionClientPort {
  return new DosaCertificationSessionClient(readDosaSessionConfig(env));
}
