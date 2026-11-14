import { BadRequestException, ConflictException, Injectable } from "@nestjs/common";
import { EcfAuditAction, Prisma, type EcfEnvironment } from "@prisma/client";
import { PrismaService } from "../../prisma/prisma.service";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import {
  ECF_DGII_DECLARATION_TEXT,
  ECF_DGII_DECLARATION_VERSION,
  ECF_SEQUENCE_TYPES,
  validateAuthorizationDeclaration,
  type AuthorizedRange,
  type EcfAuthorizationInput,
} from "./ecf-dgii-authorized-sequences.policy";

import { lockNumberingEnvironment, numberingEnvironment } from "./ecf-numbering-environment";

/**
 * Guarda y expone la autorización de numeración que la DGII otorgó a la empresa.
 *
 * Una fila por empresa y tipo. Volver a declarar **actualiza** la fila (la
 * empresa pudo recibir un rango nuevo); el historial de cambios vive en la
 * auditoría del módulo, no en filas duplicadas.
 *
 * No inventa datos ni los deduce del proveedor: solo persiste lo que el cliente
 * transcribió de la Oficina Virtual, ya validado por la política pura.
 */
@Injectable()
export class EcfDgiiAuthorizedSequencesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(user: TenantUser) {
    const companyId = requireTenant(user);
    const environment = await numberingEnvironment(this.prisma, companyId);
    const rows = await this.prisma.ecfDgiiAuthorizedSequence.findMany({
      where: { companyId, environment },
      orderBy: { documentType: "asc" },
    });
    return {
      environment,
      items: rows.map(toView),
      supportedTypes: [...ECF_SEQUENCE_TYPES],
      declarationVersion: environment === "SANDBOX" ? "test-v1" : ECF_DGII_DECLARATION_VERSION,
      declarationText: environment === "SANDBOX"
        ? "Declaro que el proveedor confirmó estos rangos y vencimientos para TEST de mi empresa. No copiaré una autorización de producción sin esa confirmación. Estos comprobantes no tienen validez fiscal."
        : ECF_DGII_DECLARATION_TEXT,
    };
  }

  async declare(user: TenantUser, input: EcfAuthorizationInput & { expectedEnvironment?: EcfEnvironment }) {
    const companyId = requireTenant(user);
    const environment = await numberingEnvironment(this.prisma, companyId);
    if (input.expectedEnvironment && input.expectedEnvironment !== environment) throw new ConflictException("ECF_NUMBERING_ENVIRONMENT_CHANGED");
    const validated = validateAuthorizationDeclaration(input);
    if (!validated.ok) {
      throw new BadRequestException(`${validated.code}: ${validated.message}`);
    }

    const data = {
      authorizationNumber: validated.authorizationNumber,
      rangeFrom: validated.rangeFrom,
      rangeTo: validated.rangeTo,
      approvedQuantity: validated.approvedQuantity,
      expiresAt: validated.expiresAt,
      evidenceId: null,
      declaredByUserId: user.id,
      declaredAt: new Date(),
      declarationVersion: environment === "SANDBOX" ? "test-v1" : ECF_DGII_DECLARATION_VERSION,
    };

    // Declarar y auditar en la MISMA transacción: si la auditoría falla, la
    // declaración no se guarda. Volver a declarar deja el antes y el después en
    // el historial, porque la fila solo conserva el estado vigente.
    return this.prisma.$transaction(async (tx) => {
      await lockNumberingEnvironment(tx, companyId, environment);
      const previous = await tx.ecfDgiiAuthorizedSequence.findUnique({
        where: {
          companyId_documentType: {
            companyId,
            documentType: validated.documentType,
            environment,
          },
        },
      });

      const saved = await tx.ecfDgiiAuthorizedSequence.upsert({
        where: {
          companyId_documentType: {
            companyId,
            documentType: validated.documentType,
            environment,
          },
        },
        create: { companyId, environment, documentType: validated.documentType, ...data },
        update: data,
      });

      await tx.ecfAuditLog.create({
        data: {
          companyId,
          actorUserId: user.id,
          action: EcfAuditAction.DGII_AUTHORIZED_SEQUENCES_DECLARED,
          targetType: "EcfDgiiAuthorizedSequence",
          targetId: saved.id,
          before: previous === null ? Prisma.JsonNull : toAuditSnapshot(previous),
          after: toAuditSnapshot(saved),
          metadata: {
            declarationVersion: data.declarationVersion,
            declaredByUserId: user.id,
          },
        },
      });

      return toView(saved);
    });
  }

  /** Autorización vigente de una empresa para un tipo, o `null` si no declaró. */
  async findFor(
    companyId: string,
    documentType: string,
    environment?: EcfEnvironment,
  ): Promise<AuthorizedRange | null> {
    const row = await this.prisma.ecfDgiiAuthorizedSequence.findUnique({
      where: {
        companyId_documentType: {
          companyId,
          documentType: `${documentType}`.trim().toUpperCase(),
          environment: environment ?? await numberingEnvironment(this.prisma, companyId),
        },
      },
    });
    if (!row) return null;
    return {
      authorizationNumber: row.authorizationNumber,
      rangeFrom: row.rangeFrom,
      rangeTo: row.rangeTo,
      approvedQuantity: row.approvedQuantity,
      expiresAt: row.expiresAt,
    };
  }
}

type AuthorizedRow = {
  documentType: string;
  environment: EcfEnvironment;
  authorizationNumber: string;
  rangeFrom: number;
  rangeTo: number;
  approvedQuantity: number;
  expiresAt: Date | null;
  declaredAt: Date;
  declarationVersion: string;
};

function toView(row: AuthorizedRow) {
  return {
    documentType: row.documentType,
    environment: row.environment,
    authorizationNumber: row.authorizationNumber,
    rangeFrom: row.rangeFrom,
    rangeTo: row.rangeTo,
    approvedQuantity: row.approvedQuantity,
    expiresAt: row.expiresAt,
    declaredAt: row.declaredAt,
    declarationVersion: row.declarationVersion,
  };
}

/**
 * Snapshot para la auditoría: rango, autorización y fechas. **Sin secretos** y
 * sin datos de otras empresas.
 */
function toAuditSnapshot(row: AuthorizedRow & { declaredByUserId?: string | null }) {
  return {
    documentType: row.documentType,
    environment: row.environment,
    authorizationNumber: row.authorizationNumber,
    rangeFrom: row.rangeFrom,
    rangeTo: row.rangeTo,
    approvedQuantity: row.approvedQuantity,
    expiresAt: row.expiresAt?.toISOString() ?? null,
    declaredByUserId: row.declaredByUserId ?? null,
    declaredAt: row.declaredAt.toISOString(),
    declarationVersion: row.declarationVersion,
  };
}
