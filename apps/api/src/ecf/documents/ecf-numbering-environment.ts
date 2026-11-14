import { ConflictException } from "@nestjs/common";
import type { EcfEnvironment, Prisma } from "@prisma/client";

/** Tenant configuration selects the numbering domain. Never infer it from a key. */
export async function numberingEnvironment(
  db: Pick<Prisma.TransactionClient, "ecfCompanyConfiguration">,
  companyId: string,
): Promise<EcfEnvironment> {
  const config = await db.ecfCompanyConfiguration.findUnique({
    where: { companyId }, select: { environment: true },
  });
  if (!config || !["SANDBOX", "PRODUCTION"].includes(config.environment)) {
    throw new ConflictException("ECF_NUMBERING_ENVIRONMENT_NOT_CONFIGURED");
  }
  return config.environment;
}

/** Hold the configuration row while a numbering write is committed. */
export async function lockNumberingEnvironment(tx: Prisma.TransactionClient, companyId: string, expected: EcfEnvironment) {
  const rows = await tx.$queryRaw<Array<{ environment: EcfEnvironment }>>`
    SELECT environment FROM ecf_company_configurations WHERE company_id = ${companyId}::uuid FOR SHARE
  `;
  if (rows[0]?.environment !== expected) throw new ConflictException("ECF_NUMBERING_ENVIRONMENT_CHANGED");
}
