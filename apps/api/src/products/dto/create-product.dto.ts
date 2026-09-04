import {
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Min,
} from "class-validator";

export class CreateProductDto {
  @IsString()
  nombre!: string;

  @IsOptional()
  @IsString()
  codigo?: string;

  @IsOptional()
  @IsString()
  code?: string;

  @IsOptional()
  @IsString()
  sku?: string;

  @IsOptional()
  @IsString()
  barcode?: string;

  @IsOptional()
  @IsString()
  operationId?: string;

  @IsOptional()
  @IsString()
  unitOfMeasureId?: string;

  @IsNumber()
  @Min(0)
  precio!: number;

  @IsNumber()
  @Min(0)
  costo!: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  stock?: number;

  @IsOptional()
  @IsIn(["PRODUCT", "SERVICE"])
  itemType?: "PRODUCT" | "SERVICE";

  @IsOptional()
  @IsBoolean()
  trackInventory?: boolean;

  @IsOptional()
  @IsUUID()
  warehouseId?: string;

  @IsOptional()
  @IsIn(["INHERIT", "TAXABLE", "EXEMPT"])
  taxTreatment?: "INHERIT" | "TAXABLE" | "EXEMPT";

  @IsOptional()
  @IsNumber()
  @Min(0)
  taxRate?: number;

  @IsOptional()
  @IsIn(["NO_TAX", "TAX_ADDED", "TAX_INCLUDED"])
  taxPriceMode?: "NO_TAX" | "TAX_ADDED" | "TAX_INCLUDED";

  @IsOptional()
  @IsString()
  fotoUrl?: string;

  @IsOptional()
  @IsString()
  imageKey?: string;

  @IsOptional()
  @IsString()
  storageProvider?: string;

  @IsOptional()
  @IsString()
  imageMimeType?: string;

  @IsOptional()
  @IsString()
  imageOriginalFileName?: string;

  @IsString()
  categoria!: string;
}
