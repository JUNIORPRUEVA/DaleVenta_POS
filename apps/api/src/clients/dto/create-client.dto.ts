import { IsOptional, IsString } from 'class-validator';
import { ClientLocationFieldsDto } from './client-location-fields.dto';

export class CreateClientDto extends ClientLocationFieldsDto {
  @IsString()
  nombre!: string;

  @IsString()
  telefono!: string;

  @IsOptional()
  @IsString()
  email?: string;

  @IsOptional()
  @IsString()
  direccion?: string;

  @IsOptional()
  @IsString()
  notas?: string;

  @IsOptional()
  @IsString()
  taxId?: string;

  @IsOptional()
  @IsString()
  businessName?: string;

  @IsOptional()
  @IsString()
  taxIdType?: string;
}
