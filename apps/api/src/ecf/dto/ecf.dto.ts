import {
  IsArray,
  IsBoolean,
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  ValidateNested,
} from "class-validator";
import { Type } from "class-transformer";
import {
  EcfEnvironment,
  EcfOnboardingStepMode,
  EcfOnboardingStepStatus,
  EcfProvider,
} from "@prisma/client";
import { ECF_ALLOWED_DOCUMENT_TYPES } from "../ecf.constants";

export class UpdateEcfConfigDto {
  @IsOptional()
  @IsBoolean()
  enabled?: boolean;

  @IsOptional()
  @IsIn([EcfProvider.ALANUBE])
  provider?: EcfProvider;

  @IsOptional()
  @IsIn([EcfEnvironment.SANDBOX])
  environment?: EcfEnvironment;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  alanubeCompanyId?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(256)
  credentialsSecretRef?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(256)
  certificateSecretRef?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(256)
  webhookSecretRef?: string | null;

  @IsOptional()
  @IsArray()
  @IsIn(ECF_ALLOWED_DOCUMENT_TYPES, { each: true })
  allowedTypes?: string[];

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  notes?: string | null;
}

export class EcfEvidenceReferenceDto {
  @IsString()
  @MaxLength(64)
  kind!: string;

  @IsString()
  @MaxLength(512)
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
  @Matches(/^[a-fA-F0-9]{64}$/)
  sha256?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string | null;
}

export class UpdateEcfOnboardingStepDto {
  @IsOptional()
  @IsIn(Object.values(EcfOnboardingStepStatus))
  status?: EcfOnboardingStepStatus;

  @IsOptional()
  @IsIn(Object.values(EcfOnboardingStepMode))
  mode?: EcfOnboardingStepMode;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  resultSummary?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  lastErrorCode?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  lastError?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  blockedReason?: string | null;

  @IsOptional()
  @IsString()
  evidenceId?: string | null;

  @IsOptional()
  @ValidateNested()
  @Type(() => EcfEvidenceReferenceDto)
  evidence?: EcfEvidenceReferenceDto;
}

