import { Type } from "class-transformer";
import { IsBooleanString, IsInt, IsOptional, IsString, Max, Min } from "class-validator";

export class ProductsQueryDto {
  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsString()
  category?: string;

  /**
   * Lista de categorias separadas por coma. Permite al POS filtrar por varias
   * categorias EN EL SERVIDOR (antes se filtraba en local sobre la pagina).
   */
  @IsOptional()
  @IsString()
  categories?: string;

  @IsOptional()
  @IsString()
  warehouseId?: string;

  @IsOptional()
  @IsBooleanString()
  includeArchived?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;
}
