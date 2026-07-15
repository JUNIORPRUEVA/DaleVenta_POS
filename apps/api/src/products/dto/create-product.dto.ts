import { IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class CreateProductDto {
  @IsString()
  nombre!: string;

  @IsNumber()
  @Min(0)
  precio!: number;

  @IsNumber()
  @Min(0)
  costo!: number;

  @IsNumber()
  @Min(0)
  stock!: number;

  @IsOptional()
  @IsString()
  fotoUrl?: string;

  @IsString()
  categoria!: string;
}
