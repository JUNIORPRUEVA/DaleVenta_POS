import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEmail,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Min,
  ValidateNested,
} from "class-validator";

export class UpsertSupplierDto {
  @IsString()
  commercialName!: string;

  @IsOptional() @IsString() legalName?: string;
  @IsOptional() @IsString() taxId?: string;
  @IsOptional() @IsString() contactName?: string;
  @IsOptional() @IsString() phone?: string;
  @IsOptional() @IsString() whatsapp?: string;
  @IsOptional() @IsEmail() email?: string;
  @IsOptional() @IsString() address?: string;
  @IsOptional() @IsString() city?: string;
  @IsOptional() @IsString() country?: string;
  @IsOptional() @IsString() website?: string;
  @IsOptional() @IsString() paymentTerms?: string;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) estimatedDeliveryDays?: number;
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsString() logo?: string;
  @IsOptional() @IsBoolean() isActive?: boolean;
}

export class PurchaseOrderItemDto {
  @IsOptional() @IsUUID() productId?: string;
  @IsOptional() @IsUUID() externalProductId?: string;
  @IsString() productName!: string;
  @IsOptional() @IsString() productCode?: string;
  @IsOptional() @IsString() description?: string;
  @IsOptional() @IsString() image?: string;
  @Type(() => Number) @IsNumber() @Min(0.0001) quantity!: number;
  @Type(() => Number) @IsNumber() @Min(0) unitCost!: number;
  @IsOptional() @IsUUID() supplierId?: string;
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsBoolean() createInventoryProductOnReceipt?: boolean;
}

export class CreatePurchaseOrderDto {
  @IsOptional() @IsUUID() supplierId?: string;
  @IsOptional() @IsDateString() expectedDeliveryDate?: string;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) discount?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) shippingCost?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) additionalCost?: number;
  @IsOptional() @Type(() => Number) @IsNumber() @Min(0) tax?: number;
  @IsOptional() @IsString() paymentTerms?: string;
  @IsOptional() @IsString() paymentMethod?: string;
  @IsOptional() @IsString() shippingMethod?: string;
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsString() supplierInstructions?: string;
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => PurchaseOrderItemDto)
  items!: PurchaseOrderItemDto[];
}

export class UpdatePurchaseOrderDto extends CreatePurchaseOrderDto {
  @IsOptional()
  @IsIn(["DRAFT", "PENDING_APPROVAL", "APPROVED", "SENT", "PARTIALLY_RECEIVED", "RECEIVED", "CANCELLED"])
  status?: string;
}

export class ReceivePurchaseOrderItemDto {
  @IsUUID() purchaseOrderItemId!: string;
  @Type(() => Number) @IsNumber() @Min(0.0001) quantityReceived!: number;
  @Type(() => Number) @IsNumber() @Min(0) unitCost!: number;
  @IsOptional() @IsString() condition?: string;
  @IsOptional() @IsString() notes?: string;
}

export class ReceivePurchaseOrderDto {
  @IsOptional() @IsString() supplierInvoiceNumber?: string;
  @IsOptional() @IsString() notes?: string;
  @IsOptional() @IsString() invoiceImage?: string;
  @IsOptional() @IsBoolean() updateInventory?: boolean;
  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => ReceivePurchaseOrderItemDto)
  items!: ReceivePurchaseOrderItemDto[];
}

