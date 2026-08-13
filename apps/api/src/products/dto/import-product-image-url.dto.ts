import { IsOptional, IsString, IsUrl, MaxLength } from 'class-validator';

export class ImportProductImageUrlDto {
  @IsUrl({ require_protocol: true, protocols: ['http', 'https'] })
  @MaxLength(2048)
  url!: string;

  @IsOptional()
  @IsString()
  @MaxLength(160)
  productName?: string;
}
