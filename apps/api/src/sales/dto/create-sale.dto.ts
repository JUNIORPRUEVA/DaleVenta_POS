import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsArray,
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

  /**
   * Precio unitario ORIGINAL antes de un descuento comercial de línea
   * (solo para ventas directas). Permite al backend persistir el descuento
   * comercial real por línea, separado del prorrateo fiscal del descuento
   * general. Ausente ⇒ no hubo descuento de línea en ese producto.
   */
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  originalUnitPriceSnapshot?: number;
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
