import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { EcfAuditAction, Prisma } from "@prisma/client";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import {
  ECF_DGII_CONSENT_PURPOSE,
  ECF_DGII_CONSENT_VERSION,
  draftSaveRefusal,
  hashCanonical,
  missingDraftFields,
  submitRefusal,
} from "./ecf-dgii-application.policy";
import {
  hasOfficialAuthorization,
  stateUpdateRefusal,
} from "./ecf-dgii-habilitation.policy";
import type {
  SaveEcfDgiiDraftDto,
  SubmitEcfDgiiApplicationDto,
} from "../dto/ecf-dgii-application.dto";

/** Referencia documental que viaja dentro del snapshot. */
export interface EcfSnapshotDocument {
  evidenceId: string;
  kind: string;
  source: string;
  fileName: string | null;
  mimeType: string | null;
  sha256: string | null;
}

/**
 * Expediente de postulación: borrador persistente, snapshot versionado y
 * consentimiento.
 *
 * Tres invariantes:
 *
 *  1. **Aislamiento**: toda lectura y escritura se acota al `companyId` del
 *     contexto autenticado. No existe ruta que acepte una empresa ajena.
 *  2. **Inmutabilidad**: un snapshot enviado no se actualiza ni se borra (lo
 *     impide además un trigger de base de datos). Una corrección crea otra
 *     versión.
 *  3. **Nada fiscal**: guardar un borrador o enviar el expediente NO modifica la
 *     configuración fiscal, ni documentos históricos, ni autoriza emisión. El
 *     consentimiento no es un poder de representación ante la DGII.
 */
@Injectable()
export class EcfDgiiApplicationService {
  constructor(private readonly prisma: PrismaService) {}

  /** Borrador persistente + lo que falta para poder enviar. */
  async getDraft(user: TenantUser) {
    const companyId = requireTenant(user);
    const record = await this.prisma.ecfDgiiHabilitation.findUnique({
      where: { companyId },
      select: {
        draftPayload: true,
        draftUpdatedAt: true,
        draftUpdatedByUserId: true,
        draftRevision: true,
        currentSnapshotVersion: true,
        consentVersion: true,
        consentAcceptedAt: true,
        state: true,
      },
    });
    const draft = record?.draftPayload ?? null;
    return {
      companyId,
      state: record?.state ?? "NOT_STARTED",
      draft,
      draftUpdatedAt: record?.draftUpdatedAt ?? null,
      draftUpdatedByUserId: record?.draftUpdatedByUserId ?? null,
      draftRevision: record?.draftRevision ?? 0,
      missingFields: missingDraftFields(draft),
      currentSnapshotVersion: record?.currentSnapshotVersion ?? 0,
      consentVersion: record?.consentVersion ?? null,
      consentAcceptedAt: record?.consentAcceptedAt ?? null,
      // El cliente no inventa el texto ni la versión: los recibe del servidor.
      requiredConsentVersion: ECF_DGII_CONSENT_VERSION,
      consentPurpose: ECF_DGII_CONSENT_PURPOSE,
    };
  }

  /** Guarda el borrador tal cual, aunque esté incompleto. */
  async saveDraft(user: TenantUser, dto: SaveEcfDgiiDraftDto) {
    const companyId = requireTenant(user);
    const refusal = draftSaveRefusal({ payload: dto.payload });
    if (refusal) throw new BadRequestException(refusal);

    await this.assertCompanyExists(companyId);
    const record = await this.ensureRecord(companyId, user.id);

    // A partir de la primera edición, la revisión es obligatoria: es el único
    // dato que distingue «estoy editando lo vigente» de «llego tarde».
    if (record.draftRevision > 0 && dto.expectedRevision === undefined) {
      throw new BadRequestException("ECF_DGII_DRAFT_REVISION_REQUIRED");
    }
    const expected = dto.expectedRevision ?? record.draftRevision;
    const savedAt = new Date();

    return this.prisma.$transaction(async (tx) => {
      // Compare-and-set atómico: solo una petición puede pasar de N a N+1.
      const updated = await tx.ecfDgiiHabilitation.updateMany({
        where: { companyId, draftRevision: expected },
        data: {
          draftPayload: dto.payload as Prisma.InputJsonValue,
          draftUpdatedAt: savedAt,
          draftUpdatedByUserId: user.id,
          draftRevision: { increment: 1 },
          updatedByUserId: user.id,
        },
      });
      if (updated.count !== 1) {
        const current = await tx.ecfDgiiHabilitation.findUnique({
          where: { companyId },
          select: {
            draftRevision: true,
            draftPayload: true,
            draftUpdatedAt: true,
          },
        });
        // Conflicto explícito con la versión vigente para que el cliente se
        // recupere sin perder lo que escribió el otro dispositivo.
        throw new ConflictException({
          message: "ECF_DGII_DRAFT_CONFLICT",
          currentRevision: current?.draftRevision ?? 0,
          draft: current?.draftPayload ?? null,
          draftUpdatedAt: current?.draftUpdatedAt ?? null,
        });
      }
      await tx.ecfAuditLog.create({
        data: {
          companyId,
          actorUserId: user.id,
          action: EcfAuditAction.DGII_APPLICATION_DRAFT_SAVED,
          targetType: "EcfDgiiHabilitation",
          after: {
            savedAt: savedAt.toISOString(),
            revision: expected + 1,
            missingFields: missingDraftFields(dto.payload),
          } as Prisma.InputJsonValue,
        },
      });
      return {
        companyId,
        draftRevision: expected + 1,
        draft: dto.payload,
        draftUpdatedAt: savedAt,
        missingFields: missingDraftFields(dto.payload),
      };
    });
  }

  /**
   * Envía el expediente a revisión creando una versión inmutable.
   *
   * Idempotente: si el contenido y los documentos son idénticos al último envío
   * y el expediente sigue en revisión, devuelve la versión existente en vez de
   * crear otra.
   */
  async submit(user: TenantUser, dto: SubmitEcfDgiiApplicationDto) {
    const companyId = requireTenant(user);
    await this.assertCompanyExists(companyId);

    return this.prisma.$transaction(async (tx) => {
      const record = await tx.ecfDgiiHabilitation.findUnique({
        where: { companyId },
      });
      if (!record) throw new BadRequestException("ECF_DGII_DRAFT_REQUIRED");

      const payload = (dto.payload ?? record.draftPayload) as unknown;
      const refusal = submitRefusal({
        payload,
        consentVersion: dto.consentVersion ?? null,
      });
      if (refusal) throw new BadRequestException(refusal);

      const evidence = await tx.ecfEvidence.findMany({
        where: { companyId },
        select: {
          id: true,
          kind: true,
          source: true,
          fileName: true,
          mimeType: true,
          sha256: true,
        },
        orderBy: { id: "asc" },
      });
      const documents: EcfSnapshotDocument[] = evidence.map((row) => ({
        evidenceId: row.id,
        kind: row.kind,
        source: row.source,
        fileName: row.fileName,
        mimeType: row.mimeType,
        sha256: row.sha256,
      }));

      const payloadHash = hashCanonical(payload);
      const documentsHash = hashCanonical(documents);
      const consentVersion = (dto.consentVersion ?? "").trim();

      const latest = await tx.ecfDgiiApplicationSnapshot.findFirst({
        where: { companyId },
        orderBy: { version: "desc" },
        select: {
          id: true,
          version: true,
          payloadHash: true,
          documentsHash: true,
          submittedAt: true,
        },
      });

      const alreadySubmitted =
        latest !== null &&
        latest.payloadHash === payloadHash &&
        latest.documentsHash === documentsHash &&
        record.state === "APPLICATION_PENDING";
      if (alreadySubmitted) {
        return {
          idempotent: true,
          snapshotId: latest.id,
          version: latest.version,
          submittedAt: latest.submittedAt,
          state: record.state,
          payloadHash,
          documentsHash,
        };
      }

      // El envío mueve el estado con la MISMA política que el resto del módulo.
      const transitionRefusal = stateUpdateRefusal(
        record.state,
        "APPLICATION_PENDING",
        hasOfficialAuthorization(record),
      );
      if (transitionRefusal) throw new ConflictException(transitionRefusal);

      const acceptedAt = new Date();
      const version = (record.currentSnapshotVersion ?? 0) + 1;

      const snapshot = await tx.ecfDgiiApplicationSnapshot.create({
        data: {
          companyId,
          version,
          payload: payload as Prisma.InputJsonValue,
          payloadHash,
          documents: documents as unknown as Prisma.InputJsonValue,
          documentsHash,
          consentVersion,
          consentAcceptedAt: acceptedAt,
          submittedByUserId: user.id,
        },
      });

      await tx.ecfDgiiHabilitation.update({
        where: { companyId },
        data: {
          state: "APPLICATION_PENDING",
          currentSnapshotVersion: version,
          consentVersion,
          consentAcceptedAt: acceptedAt,
          consentAcceptedByUserId: user.id,
          // El borrador deja de existir como trabajo en curso: vive en el snapshot.
          draftPayload: Prisma.DbNull,
          draftUpdatedAt: null,
          ...(record.startedAt === null ? { startedAt: acceptedAt } : {}),
          updatedByUserId: user.id,
        },
      });

      await tx.ecfAuditLog.create({
        data: {
          companyId,
          actorUserId: user.id,
          action: EcfAuditAction.DGII_CONSENT_ACCEPTED,
          targetType: "EcfDgiiHabilitation",
          targetId: snapshot.id,
          after: {
            consentVersion,
            acceptedAt: acceptedAt.toISOString(),
            purpose: ECF_DGII_CONSENT_PURPOSE,
          } as Prisma.InputJsonValue,
        },
      });
      await tx.ecfAuditLog.create({
        data: {
          companyId,
          actorUserId: user.id,
          action: EcfAuditAction.DGII_APPLICATION_SUBMITTED,
          targetType: "EcfDgiiApplicationSnapshot",
          targetId: snapshot.id,
          before: { state: record.state } as Prisma.InputJsonValue,
          after: {
            state: "APPLICATION_PENDING",
            version,
            payloadHash,
            documentsHash,
            documentCount: documents.length,
          } as Prisma.InputJsonValue,
        },
      });

      return {
        idempotent: false,
        snapshotId: snapshot.id,
        version,
        submittedAt: snapshot.submittedAt,
        state: "APPLICATION_PENDING",
        payloadHash,
        documentsHash,
      };
    });
  }

  /** Versiones enviadas, de la más reciente a la más antigua. */
  async listSnapshots(user: TenantUser) {
    const companyId = requireTenant(user);
    const rows = await this.prisma.ecfDgiiApplicationSnapshot.findMany({
      where: { companyId },
      orderBy: { version: "desc" },
      take: 50,
      select: {
        id: true,
        version: true,
        payload: true,
        payloadHash: true,
        documents: true,
        documentsHash: true,
        consentVersion: true,
        consentAcceptedAt: true,
        submittedByUserId: true,
        submittedAt: true,
      },
    });
    return rows.map((row) => ({
      id: row.id,
      version: row.version,
      payload: row.payload,
      payloadHash: row.payloadHash,
      documents: row.documents,
      documentsHash: row.documentsHash,
      consentVersion: row.consentVersion,
      consentAcceptedAt: row.consentAcceptedAt,
      submittedByUserId: row.submittedByUserId,
      submittedAt: row.submittedAt,
    }));
  }

  private async assertCompanyExists(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { id: true },
    });
    if (!company) throw new NotFoundException("Empresa no encontrada");
  }

  private async ensureRecord(companyId: string, actorUserId: string) {
    return this.prisma.ecfDgiiHabilitation.upsert({
      where: { companyId },
      update: {},
      create: { companyId, createdByUserId: actorUserId },
    });
  }
}
