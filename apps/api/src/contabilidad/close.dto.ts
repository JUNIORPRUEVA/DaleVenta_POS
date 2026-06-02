import {
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsNotEmpty,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  ValidateNested,
  Min,
} from 'class-validator';
import { Type } from 'class-transformer';

export class CloseExpenseDetailDto {
  @IsString()
  concept!: string;

  @IsNumber()
  @Min(0)
  amount!: number;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseTransferVoucherDto)
  @IsOptional()
  vouchers?: CloseTransferVoucherDto[];
}

export enum CloseType {
  CAPSULAS = 'CAPSULAS',
  POS = 'POS',
  TIENDA = 'TIENDA',
  PHYTOEMAGRY = 'PHYTOEMAGRY',
}

export enum CloseStatus {
  PENDING = 'pending',
  APPROVED = 'approved',
  REJECTED = 'rejected',
}

export class CloseTransferVoucherDto {
  @IsString()
  storageKey!: string;

  @IsString()
  fileUrl!: string;

  @IsString()
  fileName!: string;

  @IsString()
  mimeType!: string;
}

export class CloseTransferEntryDto {
  @IsString()
  bankName!: string;

  @IsNumber()
  @Min(0)
  amount!: number;

  @IsString()
  @IsOptional()
  referenceNumber?: string;

  @IsString()
  @IsOptional()
  note?: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseTransferVoucherDto)
  vouchers!: CloseTransferVoucherDto[];
}

export class CreateCloseDto {
  @IsEnum(CloseType)
  type!: CloseType;

  @IsDateString()
  date!: string;

  @IsNumber()
  @Min(0)
  cash!: number;

  @IsNumber()
  @Min(0)
  transfer!: number;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseTransferEntryDto)
  @IsOptional()
  transfers?: CloseTransferEntryDto[];

  @IsString()
  @IsOptional()
  transferBank?: string;

  @IsNumber()
  @Min(0)
  card!: number;

  @IsNumber()
  @Min(0)
  @IsOptional()
  otherIncome?: number;

  @IsNumber()
  @Min(0)
  expenses!: number;

  @IsNumber()
  @IsOptional()
  cashDelivered?: number;

  @IsString()
  @IsOptional()
  notes?: string;

  @IsString()
  @IsOptional()
  evidenceUrl?: string;

  @IsString()
  @IsOptional()
  evidenceFileName?: string;

  @IsString()
  @IsOptional()
  evidenceStorageKey?: string;

  @IsString()
  @IsOptional()
  evidenceMimeType?: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseExpenseDetailDto)
  @IsOptional()
  expenseDetails?: CloseExpenseDetailDto[];

  @IsUUID()
  @IsOptional()
  correctionOfCloseId?: string;

  @IsString()
  @IsOptional()
  correctionReason?: string;
}

export class UpdateCloseDto {
  @IsNumber()
  @IsOptional()
  @Min(0)
  cash?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  transfer?: number;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseTransferEntryDto)
  @IsOptional()
  transfers?: CloseTransferEntryDto[];

  @IsString()
  @IsOptional()
  transferBank?: string;

  @IsNumber()
  @IsOptional()
  @Min(0)
  card?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  otherIncome?: number;

  @IsNumber()
  @IsOptional()
  @Min(0)
  expenses?: number;

  @IsNumber()
  @IsOptional()
  cashDelivered?: number;

  @IsString()
  @IsOptional()
  notes?: string;

  @IsString()
  @IsOptional()
  evidenceUrl?: string;

  @IsString()
  @IsOptional()
  evidenceFileName?: string;

  @IsString()
  @IsOptional()
  evidenceStorageKey?: string;

  @IsString()
  @IsOptional()
  evidenceMimeType?: string;

  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CloseExpenseDetailDto)
  @IsOptional()
  expenseDetails?: CloseExpenseDetailDto[];
}

export class ReviewCloseDto {
  @IsString()
  @IsOptional()
  reviewNote?: string;
}

export class ToggleCloseCashDepositDto {
  @IsBoolean()
  cashDeposited!: boolean;
}

export class DeleteCloseDto {
  @IsString()
  @IsNotEmpty()
  adminPassword!: string;
}

export class BulkDeleteClosesDto {
  @IsArray()
  @IsUUID('4', { each: true })
  closeIds!: string[];

  @IsString()
  @IsNotEmpty()
  adminPassword!: string;
}

export class CloseFinancialSummaryQueryDto {
  @IsDateString()
  @IsOptional()
  fromDate?: string;

  @IsDateString()
  @IsOptional()
  toDate?: string;

  @IsEnum(CloseType)
  @IsOptional()
  businessType?: CloseType;

  @IsString()
  @IsOptional()
  companyId?: string;
}
