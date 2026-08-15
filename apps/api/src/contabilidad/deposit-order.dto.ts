import {
  IsBoolean,
  IsDateString,
  IsEnum,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Min,
  ValidateIf,
} from 'class-validator';

export enum DepositOrderStatusDto {
  PENDING = 'PENDING',
  EXECUTED = 'EXECUTED',
  CANCELLED = 'CANCELLED',
}

export class CreateDepositOrderDto {
  @IsDateString()
  windowFrom!: string;

  @IsDateString()
  windowTo!: string;

  @IsString()
  bankName!: string;

  @IsOptional()
  @IsString()
  bankAccount?: string;

  @IsOptional()
  @IsString()
  collaboratorName?: string;

  @IsOptional()
  @IsString()
  note?: string;

  @IsNumber()
  @Min(0)
  reserveAmount!: number;

  @IsNumber()
  @Min(0)
  totalAvailableCash!: number;

  @IsNumber()
  @Min(0)
  depositTotal!: number;

  @IsObject()
  closesCountByType!: Record<string, number>;

  @IsObject()
  depositByType!: Record<string, number>;

  @IsObject()
  accountByType!: Record<string, string>;

  @IsOptional()
  @IsString()
  correctionOfDepositOrderId?: string;

  @IsOptional()
  @IsString()
  correctionReason?: string;
}

export class UpdateDepositOrderDto {
  @IsOptional()
  @IsDateString()
  windowFrom?: string;

  @IsOptional()
  @IsDateString()
  windowTo?: string;

  @IsOptional()
  @IsString()
  bankName?: string;

  @IsOptional()
  @IsString()
  bankAccount?: string;

  @IsOptional()
  @IsString()
  collaboratorName?: string;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  reserveAmount?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  totalAvailableCash?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  depositTotal?: number;

  @IsOptional()
  @IsObject()
  closesCountByType?: Record<string, number>;

  @IsOptional()
  @IsObject()
  depositByType?: Record<string, number>;

  @IsOptional()
  @IsObject()
  accountByType?: Record<string, string>;

  @IsOptional()
  @IsString()
  correctionOfDepositOrderId?: string;

  @IsOptional()
  @IsString()
  correctionReason?: string;

  @IsOptional()
  @IsEnum(DepositOrderStatusDto)
  status?: DepositOrderStatusDto;

  @ValidateIf((_, value) => value != null)
  @IsString()
  voucherUrl?: string;

  @ValidateIf((_, value) => value != null)
  @IsString()
  voucherFileName?: string;

  @ValidateIf((_, value) => value != null)
  @IsString()
  voucherMimeType?: string;
}

export class ReviewDepositOrderDto {
  @IsOptional()
  @IsString()
  reviewNote?: string;
}

export class DepositOrdersQueryDto {
  @IsDateString()
  @IsOptional()
  from?: string;

  @IsDateString()
  @IsOptional()
  to?: string;

  @IsEnum(DepositOrderStatusDto)
  @IsOptional()
  status?: DepositOrderStatusDto;
}

export class CreateDepositBankDto {
  @IsString()
  name!: string;
}

export class UpdateDepositBankDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

export class CreateDepositBankAccountDto {
  @IsString()
  label!: string;

  @IsOptional()
  @IsString()
  accountNumber?: string;
}

export class UpdateDepositBankAccountDto {
  @IsOptional()
  @IsString()
  label?: string;

  @IsOptional()
  @IsString()
  accountNumber?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}
