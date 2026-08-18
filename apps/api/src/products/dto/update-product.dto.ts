import { IsIn, IsNumber, IsOptional, IsString, Min } from "class-validator";

export class UpdateProductDto {
  @IsOptional()
  @IsString()
  nombre?: string;

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
  @IsNumber()
  @Min(0)
  precio?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  costo?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  stock?: number;

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

  @IsOptional()
  @IsString()
  categoria?: string;
}
