import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsIn,
  IsInt,
  IsISO8601,
  IsObject,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';

export const GUARDIAN_SEVERITIES = ['SEV1', 'SEV2', 'SEV3', 'SEV4'] as const;
export type GuardianSeverityName = (typeof GUARDIAN_SEVERITIES)[number];

export const GUARDIAN_MODULES = [
  'auth',
  'cash',
  'sales',
  'inventory',
  'sync',
  'license',
  'updater',
  'printing',
  'fiscal',
  'reporting',
  'network',
  'flutter',
  'backend',
  'unknown',
] as const;

const SAFE_ID = /^[A-Za-z0-9._:-]{8,120}$/;

export class GuardianIngestEventDto {
  /** Identificador estable generado por el cliente (idempotencia). */
  @IsString()
  @Matches(SAFE_ID, { message: 'eventId debe ser un identificador estable (8-120, [A-Za-z0-9._:-])' })
  eventId!: string;

  @IsIn(GUARDIAN_SEVERITIES as unknown as string[])
  severity!: GuardianSeverityName;

  @IsIn(GUARDIAN_MODULES as unknown as string[])
  module!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(80)
  operation!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  exceptionType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(24)
  platform?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  appVersion?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  deviceId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  correlationId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20_000)
  stack?: string;

  @IsOptional()
  @IsString()
  @MaxLength(600)
  message?: string;

  @IsISO8601()
  occurredAt!: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(43_200)
  offlineMinutes?: number;

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(1)
  schemaVersion?: number;

  @IsOptional()
  @IsObject()
  context?: Record<string, unknown>;

  @IsOptional()
  @IsArray()
  @ArrayMaxSize(5)
  @IsObject({ each: true })
  evidences?: Array<Record<string, unknown>>;
}

export class GuardianIngestBatchDto {
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => GuardianIngestEventDto)
  events!: GuardianIngestEventDto[];
}

export type GuardianIngestResultItem = {
  eventId: string;
  status: 'accepted' | 'duplicate' | 'rejected';
  incidentId?: string;
  reason?: string;
  severity?: GuardianSeverityName;
};
