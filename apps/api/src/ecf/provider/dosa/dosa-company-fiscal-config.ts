import type { DosaRawClient } from "./dosa-credential.service";
import type { DosaCompanyFiscalConfigReader } from "./dosa-emission.service";

/**
 * Lectura de la configuración fiscal de la empresa desde el servidor.
 *
 * Se usa SQL parametrizado y `provider::text` a propósito: el enum `EcfProvider`
 * de la base solo admite `ALANUBE` hoy, y añadir `DOSA` requiere
 * `ALTER TYPE ... ADD VALUE`, que es una migración de tipo con restricciones de
 * transacción. Leerlo como texto permite que la compuerta funcione y que el
 * recorrido sea verificable sin fingir un cambio de esquema que no existe.
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
  } | null> {
    const rows = await this.prisma.$queryRaw<
      Array<{ enabled: boolean; provider: string }>
    >`
      SELECT "enabled", "provider"::text AS "provider"
        FROM "ecf_company_configurations"
       WHERE "company_id" = ${companyId}::uuid
       LIMIT 1
    `;
    if (rows.length === 0) return null;
    return { ecfEnabled: rows[0].enabled === true, provider: rows[0].provider };
  }
}
