import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../../prisma/prisma.service";
import type { DosaCompanyResolver } from "./dosa-webhook.service";

/**
 * Correlación RNC → empresa **desde datos de servidor**.
 *
 * Fuente: `ecf_dosa_certification_sessions`, que solo crea nuestro backend, y
 * `ecf_company_configurations.enabled` para el opt-in.
 *
 * Deliberadamente **no** se usa:
 * * el `rnc` que venga del navegador o del cuerpo del evento por sí solo,
 * * ningún valor por defecto ("si no encuentro, uso la empresa del partner").
 *
 * Si hay 0 coincidencias → desconocido. Si hay más de una → ambiguo, y también
 * se rechaza: es un error de datos que no debe resolverse "eligiendo la
 * primera".
 */
@Injectable()
export class PrismaDosaCompanyResolver implements DosaCompanyResolver {
  constructor(private readonly prisma: PrismaService) {}

  async resolveByRnc(
    rnc: string,
  ): Promise<{
    companyId: string;
    ecfEnabled: boolean;
    portalEligible: boolean;
  } | null> {
    const normalized = rnc.replace(/[^0-9A-Za-z]/g, "").toUpperCase();
    if (!normalized) return null;

    const rows = await this.prisma.$queryRaw<
      { company_id: string; enabled: boolean; portal_eligible: boolean }[]
    >`
      SELECT DISTINCT s."company_id" AS company_id,
             COALESCE(c."enabled", FALSE) AS enabled,
             -- Autorización del asistente POR EMPRESA, no por entorno.
             -- Una fila ACTIVE sin revocar y sin caducar es elegible.
             EXISTS (
               SELECT 1 FROM "ecf_portal_enrollments" e
                WHERE e."company_id" = s."company_id"
                  AND e."status" = 'ACTIVE'
                  AND e."revoked_at" IS NULL
                  AND (e."expires_at" IS NULL OR e."expires_at" > NOW())
             ) AS portal_eligible
        FROM "ecf_dosa_certification_sessions" s
        LEFT JOIN "ecf_company_configurations" c
          ON c."company_id" = s."company_id"
       WHERE s."rnc" = ${normalized}
       LIMIT 2
    `;

    if (rows.length !== 1) return null;
    return {
      companyId: rows[0].company_id,
      ecfEnabled: rows[0].enabled,
      portalEligible: rows[0].portal_eligible === true,
    };
  }
}
