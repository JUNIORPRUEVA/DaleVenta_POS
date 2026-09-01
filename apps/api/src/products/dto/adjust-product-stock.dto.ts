import { Type } from "class-transformer";
import { IsNumber, IsOptional, IsString, IsUUID, Min } from "class-validator";

export class AdjustProductStockDto {
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  stock?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  delta?: number;

  @IsOptional()
  @Type(() => Number)
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
