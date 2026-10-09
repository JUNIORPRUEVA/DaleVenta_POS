import {
  IsDateString,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from 'class-validator';

export class CreateServiceOrderDto {
  @IsOptional()
  @IsUUID()
  clientId?: string;

  @IsOptional()
  @IsUUID()
  client_id?: string;

  @IsOptional()
  @IsUUID()
  quotationId?: string;

  @IsOptional()
  @IsUUID()
  quotation_id?: string;

  @IsString()
  category!: string;

  @IsOptional()
  @IsString()
  serviceType?: string;

  @IsOptional()
  @IsString()
  service_type?: string;

  @IsOptional()
  @IsString()
  status?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  technicalNote?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  technical_note?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  extraRequirements?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  extra_requirements?: string;

  @IsOptional()
  @IsUUID()
  assignedToId?: string;

  @IsOptional()
  @IsUUID()
  assigned_to?: string;

  @IsOptional()
  @IsDateString()
  scheduledFor?: string;

  @IsOptional()
  @IsDateString()
  scheduled_for?: string;
}

export class UpdateServiceOrderDto extends CreateServiceOrderDto {}

export class UpdateServiceOrderStatusDto {
  @IsString()
  status!: string;

  @IsOptional()
  @IsDateString()
  scheduledAt?: string;

  @IsOptional()
  @IsDateString()
  scheduled_at?: string;
}

export class CloneServiceOrderDto {
  @IsOptional()
  @IsString()
  serviceType?: string;

  @IsOptional()
  @IsString()
  service_type?: string;

  @IsOptional()
  @IsUUID()
  clientId?: string;

  @IsOptional()
  @IsUUID()
  client_id?: string;

  @IsOptional()
  @IsUUID()
  quotationId?: string;

  @IsOptional()
  @IsUUID()
  quotation_id?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  technicalNote?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  technical_note?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  extraRequirements?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5000)
  extra_requirements?: string;

  @IsOptional()
  @IsUUID()
  assignedToId?: string;

  @IsOptional()
  @IsUUID()
  assigned_to?: string;
}

export class CreateServiceEvidenceDto {
  @IsString()
  type!: string;

  @IsString()
  @MaxLength(10000)
  content!: string;
}

export class CreateServiceReportDto {
  @IsOptional()
  @IsString()
  type?: string;

  @IsString()
  @MaxLength(10000)
  report!: string;
}
