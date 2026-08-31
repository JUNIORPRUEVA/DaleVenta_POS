import { IsNumber, IsOptional, IsString, IsUUID, Min } from "class-validator";

export class AdjustProductStockDto {
  @IsOptional()
  @IsNumber()
  @Min(0)
  stock?: number;

  @IsOptional()
  @IsNumber()
  delta?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  expectedCurrentStock?: number;

  @IsOptional()
  @IsUUID()
  warehouseId?: string;

  @IsOptional()
  @IsString()
  reason?: string;
}
