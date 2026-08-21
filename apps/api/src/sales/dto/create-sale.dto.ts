import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Min,
  ValidateNested,
} from "class-validator";

export class CreateSaleItemDto {
  @IsOptional()
  @IsUUID()
  productId?: string;

  @IsOptional()
  @IsString()
  productName?: string;

  @Type(() => Number)
  @IsNumber()
  @Min(0.0001)
  qty!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  priceSoldUnit!: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  costUnitSnapshot?: number;
}

export class CreateSaleDto {
  @IsOptional()
  @IsString()
  clientRequestId?: string;

  @IsOptional()
  @IsUUID()
  sourceQuotationId?: string;

  @IsOptional()
  @IsUUID()
  customerId?: string;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsString()
  fiscalVoucherType?: string;

  @IsOptional()
  @IsString()
  ncf?: string;

  @IsOptional()
  @IsString()
  fiscalCustomerTaxId?: string;

  @IsOptional()
  @IsString()
  fiscalCustomerName?: string;

  /**
   * When true, the backend persists/reuses a master Client from the fiscal
   * identification used in this sale (so it can be recovered by RNC later).
   * This is a decision stored per ticket; it never consumes an extra NCF.
   */
  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  saveFiscalCustomer?: boolean;

  @IsOptional()
  @IsIn(["cash", "transfer", "mixed", "credit"])
  paymentMethod?: "cash" | "transfer" | "mixed" | "credit";

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  paymentCashAmount?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  paymentTransferAmount?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  creditAmount?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  expectedTotalSold?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  globalDiscountAmount?: number;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateSaleItemDto)
  items!: CreateSaleItemDto[];
}

export class CreateSaleReturnItemDto {
  @IsUUID()
  saleItemId!: string;

  @Type(() => Number)
  @IsNumber()
  @Min(0.0001)
  qty!: number;
}

export class CreateSaleReturnDto {
  @IsOptional()
  @IsString()
  reason?: string;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => CreateSaleReturnItemDto)
  items?: CreateSaleReturnItemDto[];
}
