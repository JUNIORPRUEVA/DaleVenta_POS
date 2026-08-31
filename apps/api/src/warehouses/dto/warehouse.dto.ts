import {
  ArrayMinSize,
  IsArray,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
  ValidateNested,
} from "class-validator";
import { Type } from "class-transformer";

export class CreateWarehouseDto {
  @IsString()
  @MaxLength(120)
  name!: string;

  @IsString()
  @MaxLength(32)
  code!: string;
}

export class UpdateWarehouseDto {
  @IsOptional()
  @IsString()
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(32)
  code?: string;
}

export class UpdateTerminalWarehouseDto {
  @IsUUID()
  warehouseId!: string;
}

export class CreateWarehouseTransferItemDto {
  @IsUUID()
  productId!: string;

  @IsString()
  quantity!: string;
}

export class CreateWarehouseTransferDto {
  @IsUUID()
  sourceWarehouseId!: string;

  @IsUUID()
  destinationWarehouseId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  clientRequestId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  notes?: string;

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateWarehouseTransferItemDto)
  items!: CreateWarehouseTransferItemDto[];
}
