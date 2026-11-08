import { BadRequestException, Injectable } from "@nestjs/common";
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
    const rows = await this.prisma.ecfDgiiAuthorizedSequence.findMany({
      where: { companyId },
      orderBy: { documentType: "asc" },
    });
    return {
      items: rows.map(toView),
      supportedTypes: [...ECF_SEQUENCE_TYPES],
      declarationVersion: ECF_DGII_DECLARATION_VERSION,
      declarationText: ECF_DGII_DECLARATION_TEXT,
    };
  }

  async declare(user: TenantUser, input: EcfAuthorizationInput) {
    const companyId = requireTenant(user);
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
      declarationVersion: ECF_DGII_DECLARATION_VERSION,
    };

    const saved = await this.prisma.ecfDgiiAuthorizedSequence.upsert({
      where: {
        companyId_documentType: {
          companyId,
          documentType: validated.documentType,
        },
      },
      create: { companyId, documentType: validated.documentType, ...data },
      update: data,
    });

    return toView(saved);
  }

  /** Autorización vigente de una empresa para un tipo, o `null` si no declaró. */
  async findFor(
    companyId: string,
    documentType: string,
  ): Promise<AuthorizedRange | null> {
    const row = await this.prisma.ecfDgiiAuthorizedSequence.findUnique({
      where: {
        companyId_documentType: {
          companyId,
          documentType: `${documentType}`.trim().toUpperCase(),
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
    authorizationNumber: row.authorizationNumber,
    rangeFrom: row.rangeFrom,
    rangeTo: row.rangeTo,
    approvedQuantity: row.approvedQuantity,
    expiresAt: row.expiresAt,
    declaredAt: row.declaredAt,
    declarationVersion: row.declarationVersion,
  };
}
