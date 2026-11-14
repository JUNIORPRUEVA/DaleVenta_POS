import { Logger } from "@nestjs/common";
import { requireTenant, type TenantUser } from "../../../auth/tenant-context";
import type { PrismaService } from "../../../prisma/prisma.service";
import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";
import type { DosaCredentialEnvironment } from "./dosa-credential-vault.service";
import type { DosaReplayInfo } from "./dosa-emission.client";
import type { DosaEmissionService } from "./dosa-emission.service";

const logger = new Logger("DosaSameRequestRecovery");
export const DOSA_REPLAY_REASON = "DOSA_IDENTICAL_REQUEST_REPLAY";

/** This authorizes a transport replay inside the original, still-running
 * dispatch. It cannot resume an old document or create another fiscal number.
 */
export async function auditDosaSameRequestRecovery(db: PrismaService, dosa: DosaEmissionService, user: TenantUser,
  documentId: string, parentAttemptId: string, info: DosaReplayInfo, expected: {
    environment: DosaCredentialEnvironment; rnc: string; documentType: EcfDocumentType;
    credentialFingerprint: string | null; documentFingerprint: string; requestFingerprint: string;
    bodyHash: string; pathHash: string; requestHash: string;
  }): Promise<boolean> {
  const companyId = requireTenant(user);
  if (![2, 3].includes(info.ordinal) || !expected.credentialFingerprint ||
      info.bodyHash !== expected.bodyHash || info.pathHash !== expected.pathHash || info.requestHash !== expected.requestHash) return false;
  try {
    const authorization = await dosa.assess({ companyId, rnc: expected.rnc, senderTaxId: expected.rnc,
      documentType: expected.documentType, sequenceAvailable: true, expectedEnvironment: expected.environment });
    if (!authorization.allowed || authorization.credentialFingerprint !== expected.credentialFingerprint) return false;
    return await db.$transaction(async tx => {
      await tx.$queryRaw`SELECT id FROM ecf_company_configurations WHERE company_id = ${companyId}::uuid FOR SHARE`;
      const fiscal = await tx.ecfCompanyConfiguration.findUnique({ where: { companyId },
        select: { enabled: true, provider: true, environment: true, certificationStatus: true, productionEnabled: true } });
      const environment = expected.environment === "test" ? "SANDBOX" : "PRODUCTION";
      const certified = expected.environment === "production" ? fiscal?.certificationStatus === "PRODUCTION_READY"
        : fiscal?.certificationStatus === "AUTHORIZED_SANDBOX" || fiscal?.certificationStatus === "PRODUCTION_READY";
      if (!fiscal?.enabled || fiscal.provider !== "DOSA" || fiscal.environment !== environment || !certified ||
          (expected.environment === "production" && !fiscal.productionEnabled)) return false;
      await tx.$queryRaw`SELECT id FROM ecf_electronic_documents WHERE company_id = ${companyId}::uuid AND id = ${documentId}::uuid FOR UPDATE`;
      const document = await tx.ecfElectronicDocument.findFirst({ where: { companyId, id: documentId },
        select: { status: true, environment: true, payloadFingerprint: true, idempotencyKey: true } });
      const parent = await tx.ecfElectronicDocumentAttempt.findFirst({ where: { companyId, documentId,
        id: parentAttemptId, operation: "SEND_TO_PROVIDER" } });
      if (!document || document.status !== "SEND_IN_PROGRESS" ||
          document.environment !== environment ||
          document.payloadFingerprint !== expected.documentFingerprint || !parent ||
          parent.idempotencyKey !== document.idempotencyKey || parent.requestFingerprint !== expected.requestFingerprint) return false;
      const count = await tx.ecfElectronicDocumentStatusLog.count({ where: { companyId, documentId,
        reasonCode: DOSA_REPLAY_REASON, metadata: { path: ["parentAttemptId"], equals: parentAttemptId } } });
      if (info.ordinal !== count + 2) return false;
      await tx.ecfElectronicDocumentStatusLog.create({ data: { companyId, documentId, changedByUserId: user.id,
        statusBefore: "SEND_IN_PROGRESS", statusAfter: "SEND_IN_PROGRESS", reasonCode: DOSA_REPLAY_REASON,
        safeMessage: "Recuperación autorizada con el mismo JSON, ruta y e-NCF; no se asigna otra secuencia.",
        metadata: { ...info, parentAttemptId, environment: document.environment,
          documentFingerprint: expected.documentFingerprint, requestFingerprint: expected.requestFingerprint,
          contract: "DOSA_SAME_REQUEST_20261113", stage: "AUTHORIZED_BEFORE_TRANSPORT" },
      } });
      return true;
    });
  } catch (error) {
    logger.error("No se pudo autorizar o auditar la recuperación DOSA; no se repetirá el envío.", error instanceof Error ? error.stack : undefined);
    return false;
  }
}
