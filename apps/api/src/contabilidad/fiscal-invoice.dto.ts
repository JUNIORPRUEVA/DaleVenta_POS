import {
  IsDateString,
  IsEnum,
  IsOptional,
  IsString,
  MaxLength,
} from 'class-validator';

export enum FiscalInvoiceKindDto {
  SALE_CARD = 'SALE_CARD',
  SALE = 'SALE',
  PURCHASE = 'PURCHASE',
}

export class CreateFiscalInvoiceDto {
  @IsEnum(FiscalInvoiceKindDto)
  kind!: FiscalInvoiceKindDto;

  @IsDateString()
  invoiceDate!: string;

  @IsString()
  imageUrl!: string;

  @IsString()
  @IsOptional()
  @MaxLength(1200)
  note?: string;
}

export class UpdateFiscalInvoiceDto {
  @IsEnum(FiscalInvoiceKindDto)
  @IsOptional()
  kind?: FiscalInvoiceKindDto;

  @IsDateString()
  @IsOptional()
  invoiceDate?: string;

  @IsString()
  @IsOptional()
  imageUrl?: string;

  @IsString()
  @IsOptional()
  @MaxLength(1200)
  note?: string;
}

export class FiscalInvoicesQueryDto {
  @IsDateString()
  @IsOptional()
  from?: string;

  @IsDateString()
  @IsOptional()
  to?: string;

  @IsEnum(FiscalInvoiceKindDto)
  @IsOptional()
  kind?: FiscalInvoiceKindDto;

  @IsString()
  @IsOptional()
  page?: string;

  @IsString()
  @IsOptional()
  limit?: string;
}
