import { IsIn, IsOptional, IsString, IsUUID, Matches, MaxLength } from "class-validator";
import { ECF_DGII_DOCUMENT_KINDS, type EcfDgiiDocumentKind } from "../dgii/ecf-dgii-document.policy";
import {
  ECF_DGII_HABILITATION_STATES,
  ECF_DGII_VERIFICATION_SOURCES,
  ECF_EVIDENCE_SOURCES,
  type EcfDgiiHabilitationState,
  type EcfDgiiVerificationSource,
  type EcfEvidenceSource,
} from "../dgii/ecf-dgii-habilitation.policy";

/**
 * Mismo formato de referencia de almacenamiento que usa el resto del módulo e-CF
 * (`EcfService.normalizeEvidence`). Se repite aquí porque es un contrato de
 * entrada distinto, no una segunda fuente de verdad: la referencia nunca
 * contiene el documento, solo su ubicación.
 */
const ECF_EVIDENCE_STORAGE_REF = /^(storage|s3|r2|evidence|uat):\/\/[A-Za-z0-9._:\/@_-]{3,512}$/;

/**
 * Metadatos de una carga documental.
 *
 * El archivo viaja en multipart, no en este cuerpo. `kind` es una lista cerrada:
 * un tipo inventado no entra al expediente.
 */
export class UploadEcfDgiiDocumentDto {
  @IsIn([...ECF_DGII_DOCUMENT_KINDS])
  kind!: EcfDgiiDocumentKind;
}

export class UpdateEcfDgiiHabilitationDto {
  @IsOptional()
  @IsIn([...ECF_DGII_HABILITATION_STATES])
  state?: EcfDgiiHabilitationState;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  reviewState?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  observations?: string | null;

  @IsOptional()
  @IsUUID()
  responsibleUserId?: string | null;
}

export class RegisterEcfDgiiEvidenceDto {
  /** Origen declarado: separa declaración manual de documento oficial. */
  @IsIn([...ECF_EVIDENCE_SOURCES])
  source!: EcfEvidenceSource;

  @IsString()
  @MaxLength(64)
  kind!: string;

  @IsString()
  @Matches(ECF_EVIDENCE_STORAGE_REF, {
    message: "storageRef debe ser una referencia de almacenamiento válida",
  })
  storageRef!: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  fileName?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  mimeType?: string | null;

  @IsOptional()
  @IsString()
  @Matches(/^[0-9a-f]{64}$/i, { message: "sha256 debe ser hexadecimal de 64 caracteres" })
  sha256?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string | null;
}

export class RecordEcfDgiiAuthorizationDto {
  @IsIn([...ECF_DGII_VERIFICATION_SOURCES])
  source!: EcfDgiiVerificationSource;

  @IsOptional()
  @IsUUID()
  evidenceId?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  externalId?: string | null;
}

/**
 * Revisión INTERNA de una evidencia.
 *
 * Es una decisión de producto, no una verificación ante la DGII: marcar una
 * evidencia como revisada **no** autoriza nada. Para eso existe el registro
 * oficial, que además exige que la evidencia sea un documento oficial revisado.
 */
export class ReviewEcfDgiiEvidenceDto {
  @IsIn(["REVIEWED", "REJECTED"])
  decision!: "REVIEWED" | "REJECTED";

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  note?: string | null;
}

/** Estados de un requisito en el seguimiento interno. */
export const ECF_DGII_REQUIREMENT_STATUSES = [
  "PENDING",
  "IN_PROGRESS",
  "BLOCKED",
  "COMPLETED",
  "NOT_APPLICABLE",
] as const;

export class UpdateEcfDgiiRequirementDto {
  @IsIn([...ECF_DGII_REQUIREMENT_STATUSES])
  status!: (typeof ECF_DGII_REQUIREMENT_STATUSES)[number];

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string | null;

  @IsOptional()
  @IsUUID()
  responsibleUserId?: string | null;

  @IsOptional()
  @IsString()
  @Matches(/^\d{4}-\d{2}-\d{2}$/, {
    message: "dueDate debe tener el formato AAAA-MM-DD",
  })
  dueDate?: string | null;
}
