import { Type } from "class-transformer";
import {
  IsBoolean,
  IsIn,
  IsNumber,
  IsOptional,
  IsString,
  Min,
} from "class-validator";

export class UpsertTaxDto {
  @IsString()
  name!: string;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  rate!: number;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;

  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}

export class UpdateFiscalSettingsDto {
  @IsOptional()
  @IsBoolean()
  taxEnabled?: boolean;

  @IsOptional()
  @IsString()
  defaultTaxId?: string | null;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  defaultTaxRate?: number;

  @IsOptional()
  @IsBoolean()
  pricesIncludeTax?: boolean;

  @IsOptional()
  @IsBoolean()
  ncfEnabled?: boolean;
}

export class CalculateSaleDto {
  @IsOptional()
  @IsBoolean()
  taxEnabled?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  globalDiscountAmount?: number;

  @IsOptional()
  @IsIn(["NO_TAX", "TAX_ADDED", "TAX_INCLUDED"])
  defaultPriceMode?: "NO_TAX" | "TAX_ADDED" | "TAX_INCLUDED";
}
