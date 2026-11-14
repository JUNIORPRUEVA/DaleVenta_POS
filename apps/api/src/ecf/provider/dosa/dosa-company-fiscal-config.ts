import type { DosaRawClient } from "./dosa-credential.service";
import type { DosaCompanyFiscalConfigReader } from "./dosa-emission.service";

/**
 * Lectura de la configuración fiscal de la empresa desde el servidor.
 *
 * Nunca se acepta esta información desde el cliente: la empresa sale del token
 * de sesión y la configuración, de la base.
 */
export class PrismaDosaCompanyFiscalConfigReader
  implements DosaCompanyFiscalConfigReader
{
  constructor(private readonly prisma: DosaRawClient) {}

  async read(companyId: string): Promise<{
    ecfEnabled: boolean;
    provider: string;
    environment: string;
    productionEnabled: boolean;
    certificationStatus: string;
  } | null> {
    const rows = await this.prisma.$queryRaw<
      Array<{ enabled: boolean; provider: string; environment: string; productionEnabled: boolean; certificationStatus: string }>
    >`
      SELECT "enabled", "provider"::text AS "provider", "environment"::text AS "environment",
             "production_enabled" AS "productionEnabled", "certification_status"::text AS "certificationStatus"
        FROM "ecf_company_configurations"
       WHERE "company_id" = ${companyId}::uuid
       LIMIT 1
    `;
    if (rows.length === 0) return null;
    return { ecfEnabled: rows[0].enabled === true, provider: rows[0].provider,
      environment: rows[0].environment, productionEnabled: rows[0].productionEnabled === true,
      certificationStatus: rows[0].certificationStatus };
  }
}
