import { Type } from "class-transformer";
import {
  IsArray,
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  Min,
  ValidateNested,
} from "class-validator";

export class CreatePriceListDto {
  @IsString()
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  priority?: number;
}

export class UpdatePriceListDto {
  @IsOptional()
  @IsString()
  name?: string;

  @IsOptional()
  @IsString()
  description?: string | null;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  priority?: number;
}

export class PriceListTierDto {
  @Type(() => Number)
  @IsNumber()
  @Min(0.000001)
  minQuantity!: number;

  @IsOptional()
  @IsIn(["FIXED_PRICE", "PERCENT_DISCOUNT"])
  mode?: "FIXED_PRICE" | "PERCENT_DISCOUNT";

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  fixedPrice?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(100)
  discountPercent?: number;
}

export class UpsertPriceListRuleDto {
  @IsUUID()
  productId!: string;

  @IsIn(["FIXED_PRICE", "PERCENT_DISCOUNT"])
  mode!: "FIXED_PRICE" | "PERCENT_DISCOUNT";

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  fixedPrice?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  @Max(100)
  discountPercent?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0.000001)
  minQuantity?: number;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @IsArray()
  @ValidateNested({ each: true })
  @Type(() => PriceListTierDto)
  tiers?: PriceListTierDto[];
}

export class AssignClientPriceListDto {
  @IsOptional()
  @IsUUID()
  priceListId?: string | null;
}

export class ResolvePriceListLineDto {
  @IsUUID()
  productId!: string;

  @Type(() => Number)
  @IsNumber()
  @Min(0.000001)
  qty!: number;

  @IsOptional()
  @IsUUID()
  clientId?: string;

  @IsOptional()
  @IsUUID()
  priceListId?: string;
}
