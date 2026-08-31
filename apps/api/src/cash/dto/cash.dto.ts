import { Type } from 'class-transformer';
import { IsIn, IsNumber, IsOptional, IsString, IsUUID, Min } from 'class-validator';

export class OpenCashSessionDto {
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  openingAmount!: number;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsUUID()
  terminalId?: string;

  @IsOptional()
  @IsString()
  deviceFingerprint?: string;
}

export class CloseCashSessionDto {
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  closingAmount!: number;

  @IsOptional()
  @IsString()
  note?: string;
}

export class CreateCashMovementDto {
  @IsIn(['IN', 'OUT'])
  type!: 'IN' | 'OUT';

  @Type(() => Number)
  @IsNumber()
  @Min(0.01)
  amount!: number;

  @IsOptional()
  @IsString()
  reason?: string;

  @IsOptional()
  @IsIn(['expense', 'owner_draw', 'transfer'])
  movementType?: 'expense' | 'owner_draw' | 'transfer';

  @IsOptional()
  affectsProfit?: boolean;
}
