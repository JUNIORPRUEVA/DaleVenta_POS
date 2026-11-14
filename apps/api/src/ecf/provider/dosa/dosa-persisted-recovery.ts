import { ConflictException } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../../auth/tenant-context";

export const DOSA_PERSISTED_REQUEST = "DOSA_PERSISTED_REQUEST_IDENTITY";
export type DosaPersistedIdentity = {
  bodyHash: string; pathHash: string; requestHash: string; destinationHash: string;
  credentialFingerprint: string | null; documentFingerprint: string; requestFingerprint: string;
  environment: "SANDBOX" | "PRODUCTION";
};

export async function assertDosaClaimOwner(tx: Prisma.TransactionClient, companyId: string, documentId: string, attemptId: string) {
  const trace = await tx.ecfElectronicDocumentStatusLog.findFirst({ where: { companyId, documentId, reasonCode: DOSA_PERSISTED_REQUEST },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }], select: { metadata: true } });
  if ((trace?.metadata as { attemptId?: string } | null)?.attemptId !== attemptId) {
    throw new ConflictException("ECF_RECOVERY_STALE_WORKER");
  }
}

/** Runs under the document row lock, before transport. Stores hashes only.
 * Older documents without this evidence remain blocked for manual review.
 */
export async function claimPersistedDosaRequest(tx: Prisma.TransactionClient, user: TenantUser,
  documentId: string, attemptId: string, recovering: boolean, expected: DosaPersistedIdentity, leaseMs: number) {
  const companyId = requireTenant(user);
  if (!expected.credentialFingerprint) throw new ConflictException("ECF_RECOVERY_CREDENTIAL_IDENTITY_REQUIRED");
  await tx.$queryRaw`SELECT company_id FROM ecf_company_configurations WHERE company_id = ${companyId}::uuid FOR SHARE`;
  const config = await tx.ecfCompanyConfiguration.findUnique({ where: { companyId } });
  const certified = expected.environment === "PRODUCTION" ? config?.certificationStatus === "PRODUCTION_READY"
    : ["AUTHORIZED_SANDBOX", "PRODUCTION_READY"].includes(config?.certificationStatus ?? "");
  if (!config?.enabled || config.provider !== "DOSA" || config.environment !== expected.environment || !certified ||
      (expected.environment === "PRODUCTION" && !config.productionEnabled)) throw new ConflictException("ECF_RECOVERY_COMPANY_CHANGED");
  if (recovering) {
    const trace = await tx.ecfElectronicDocumentStatusLog.findFirst({ where: { companyId, documentId,
      reasonCode: DOSA_PERSISTED_REQUEST }, orderBy: [{ createdAt: "desc" }, { id: "desc" }], select: { metadata: true } });
    const saved = trace?.metadata as (DosaPersistedIdentity & { notBefore?: string }) | null;
    if (!saved || Object.keys(expected).some(key => saved[key as keyof DosaPersistedIdentity] !== expected[key as keyof DosaPersistedIdentity])) {
      throw new ConflictException("ECF_RECOVERY_REQUEST_CHANGED_OR_UNPROVEN");
    }
    const notBefore = Date.parse(saved.notBefore ?? "");
    if (!Number.isFinite(notBefore) || Date.now() < notBefore) throw new ConflictException("ECF_RECOVERY_WAIT_FOR_ACTIVE_REQUEST");
  }
  await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId,
    statusBefore: "SEND_IN_PROGRESS", statusAfter: "SEND_IN_PROGRESS", changedByUserId: user.id,
    reasonCode: DOSA_PERSISTED_REQUEST, safeMessage: recovering ? "Consulta con la solicitud original, sin consumir otra numeración." : "Identidad de envío conservada antes de la red.",
    metadata: { ...expected, attemptId, recovering, notBefore: new Date(Date.now() + leaseMs).toISOString() },
  } });
}
