import { Transform } from 'class-transformer';
import {
  IsBoolean,
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  MaxLength,
  Min,
} from 'class-validator';

export enum PayableProviderKindDto {
  PERSON = 'PERSON',
  COMPANY = 'COMPANY',
}

export enum PayableFrequencyDto {
  ONE_TIME = 'ONE_TIME',
  MONTHLY = 'MONTHLY',
  BIWEEKLY = 'BIWEEKLY',
}

export class CreatePayableServiceDto {
  @IsString()
  @MaxLength(180)
  title!: string;

  @IsEnum(PayableProviderKindDto)
  providerKind!: PayableProviderKindDto;

  @IsString()
  @MaxLength(180)
  providerName!: string;

  @IsString()
  @IsOptional()
  @MaxLength(1200)
  description?: string;

  @IsEnum(PayableFrequencyDto)
  frequency!: PayableFrequencyDto;

  @IsNumber()
  @Min(0)
  @IsOptional()
  defaultAmount?: number;

  @IsDateString()
  nextDueDate!: string;

  @IsBoolean()
  @IsOptional()
  active?: boolean;
}

export class UpdatePayableServiceDto {
  @IsString()
  @IsOptional()
  @MaxLength(180)
  title?: string;

  @IsEnum(PayableProviderKindDto)
  @IsOptional()
  providerKind?: PayableProviderKindDto;

  @IsString()
  @IsOptional()
  @MaxLength(180)
  providerName?: string;

  @IsString()
  @IsOptional()
  @MaxLength(1200)
  description?: string;

  @IsEnum(PayableFrequencyDto)
  @IsOptional()
  frequency?: PayableFrequencyDto;

  @IsNumber()
  @Min(0)
  @IsOptional()
  defaultAmount?: number;

  @IsDateString()
  @IsOptional()
  nextDueDate?: string;

  @IsBoolean()
  @IsOptional()
  active?: boolean;
}

export class RegisterPayablePaymentDto {
  @IsNumber()
  @Min(0)
  amount!: number;

  @IsDateString()
  @IsOptional()
  paidAt?: string;

  @IsString()
  @IsOptional()
  @MaxLength(1200)
  note?: string;
}

export class PayableServicesQueryDto {
  @Transform(({ value }) => {
    if (value == null) return undefined;
    const raw = String(value).trim().toLowerCase();
    if (raw === 'true' || raw === '1') return true;
    if (raw === 'false' || raw === '0') return false;
    return undefined;
  })
  @IsBoolean()
  @IsOptional()
  active?: boolean;

  @IsString()
  @IsOptional()
  page?: string;

  @IsString()
  @IsOptional()
  limit?: string;
}

export class PayablePaymentsQueryDto {
  @IsDateString()
  @IsOptional()
  from?: string;

  @IsDateString()
  @IsOptional()
  to?: string;

  @IsString()
  @IsOptional()
  serviceId?: string;

  @IsString()
  @IsOptional()
  page?: string;

  @IsString()
  @IsOptional()
  limit?: string;
}

export class UpdatePayablePaymentDto {
  @IsNumber()
  @Min(0)
  @IsOptional()
  amount?: number;

  @IsDateString()
  @IsOptional()
  paidAt?: string;

  @IsString()
  @IsOptional()
  @MaxLength(1200)
  note?: string;
}
