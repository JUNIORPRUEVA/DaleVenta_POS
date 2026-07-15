import { Type } from 'class-transformer';
import { ArrayMinSize, IsArray, IsIn, IsNumber, IsOptional, IsString, IsUUID, Min, ValidateNested } from 'class-validator';

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
  @IsUUID()
  customerId!: string;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsIn(['cash', 'transfer', 'mixed'])
  paymentMethod?: 'cash' | 'transfer' | 'mixed';

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

  @IsArray()
  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateSaleItemDto)
  items!: CreateSaleItemDto[];
}
