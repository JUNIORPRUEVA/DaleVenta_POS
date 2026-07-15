import { IsBooleanString, IsISO8601, IsOptional, IsUUID } from 'class-validator';

export class SalesRangeQueryDto {
  @IsOptional()
  @IsISO8601()
  from?: string;

  @IsOptional()
  @IsISO8601()
  to?: string;

  @IsOptional()
  @IsUUID()
  userId?: string;

  @IsOptional()
  @IsUUID()
  customerId?: string;

  @IsOptional()
  @IsBooleanString()
  includeDeleted?: string;
}
