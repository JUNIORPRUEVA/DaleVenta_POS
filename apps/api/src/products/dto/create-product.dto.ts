import { IsNumber, IsOptional, IsString, Min } from "class-validator";

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
