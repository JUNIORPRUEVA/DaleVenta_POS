import { Transform, Type } from 'class-transformer';
import { IsOptional, IsString, Max, Min } from 'class-validator';

export class ServiceOrdersQueryDto {
  @IsOptional()
  @Type(() => Number)
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @Min(1)
  @Max(200)
  limit?: number;

  @IsOptional()
  @IsString()
  statuses?: string;

  @IsOptional()
  @IsString()
  status?: string;

  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;

  @IsOptional()
  @Transform(({ value }) => `${value ?? ''}`.trim())
  @IsString()
  search?: string;
}

export class ServiceOrdersSyncQueryDto {
  @IsOptional()
  @IsString()
  cursor?: string;

  @IsOptional()
  @Type(() => Number)
  @Min(1)
  @Max(200)
  limit?: number;
}
