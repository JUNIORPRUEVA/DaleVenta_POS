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

export class CreateNcfSequenceDto {
  @IsIn(["B01", "B02"])
  voucherType!: "B01" | "B02";

  @IsString()
  prefix!: string;

  @Type(() => Number)
  @IsNumber()
  @Min(1)
  startNumber!: number;

  @Type(() => Number)
  @IsNumber()
  @Min(1)
  endNumber!: number;

  @IsOptional()
  @IsString()
  validUntil?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

export class UpdateNcfSequenceDto {
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  @Min(1)
  endNumber?: number;

  @IsOptional()
  @IsString()
  validUntil?: string | null;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}
