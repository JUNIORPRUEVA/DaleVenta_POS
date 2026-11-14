import { CompanyMemberStatus, Role, type EcfCompanyConfiguration, type Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";

/** Read-only admission policy shared by POS capabilities and sale creation.
 * Credential presence is checked here; secrets are opened only by dispatch.
 */
export async function ecfCheckoutAccess(db: Prisma.TransactionClient, user: TenantUser, config: EcfCompanyConfiguration | null) {
  const companyId = requireTenant(user);
  const blocked = (code: string) => ({ allowed: false, code });
  if (!config?.enabled || config.provider !== "DOSA") return blocked("ECF_COMPANY_DISABLED");
  if (user.role !== Role.ADMIN && !user.authorizedPermissions?.includes("prepareEcfDocuments")) {
    const permissions = Object.prototype.hasOwnProperty.call(user, "userPermissions")
      ? user.userPermissions
      : (await db.user.findFirst({ where: { id: user.id, OR: [{ companyId }, {
          companyMemberships: { some: { companyId, status: CompanyMemberStatus.ACTIVE } },
        }] }, select: { userPermissions: true } }))?.userPermissions;
    if (!permissions || typeof permissions !== "object" || Array.isArray(permissions) ||
        (permissions as Record<string, unknown>).prepareEcfDocuments !== true) {
      return blocked("ECF_PREPARATION_PERMISSION_REQUIRED");
    }
  }
  if (process.env.DOSA_EMISSION_ENABLED !== "true") return blocked("ECF_EMISSION_DISABLED");
  if (config.environment === "PRODUCTION") {
    if (!config.productionEnabled || config.certificationStatus !== "PRODUCTION_READY" ||
        process.env.DOSA_PRODUCTION_EMISSION_ENABLED !== "true" || process.env.DOSA_CONFIRMED_DGII_OUTCOMES_ENABLED !== "true") {
      return blocked("ECF_PRODUCTION_BLOCKED");
    }
  } else if (config.environment !== "SANDBOX" || config.productionEnabled ||
      !["AUTHORIZED_SANDBOX", "PRODUCTION_READY"].includes(config.certificationStatus)) {
    return blocked("ECF_CERTIFICATION_REQUIRED");
  }
  const identity = await db.appConfig.findFirst({ where: { companyId }, select: { rnc: true } });
  const rnc = identity?.rnc.replace(/\D/g, "") ?? "";
  if (!rnc) return blocked("ECF_ISSUER_REQUIRED");
  const environment = config.environment === "PRODUCTION" ? "production" : "test";
  const credential = await db.ecfDosaCompanyCredential.findFirst({
    where: { companyId, rnc, environment, status: "ACTIVE" }, select: { present: true },
  });
  const key = environment === "production" ? "apiKeyProduccion" : "apiKeyTest";
  if ((credential?.present as Record<string, unknown> | null)?.[key] !== true) {
    return blocked("ECF_COMPANY_CREDENTIAL_REQUIRED");
  }
  return { allowed: true, code: null };
}
