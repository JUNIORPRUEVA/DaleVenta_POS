import { Transform } from 'class-transformer';
import { IsBoolean, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export type ClientsCorreoFilter = 'todos' | 'conCorreo' | 'sinCorreo';
export type ClientsOwnerFilter = 'todos' | 'mine';
export type ClientsOrderOption = 'az' | 'za';

const toEnumOrUndefined = <T extends string>(
  value: unknown,
  allowed: readonly T[],
): T | undefined => {
  if (value === undefined || value === null || value === '') return undefined;
  const normalized = String(value).trim();
  return (allowed as readonly string[]).includes(normalized)
    ? (normalized as T)
    : undefined;
};

const toSafePositiveIntOrUndefined = (value: unknown) => {
  if (value === undefined || value === null) return undefined;
  const num = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(num)) return undefined;
  return Math.max(1, Math.trunc(num));
};

const toBooleanOrUndefined = (value: unknown) => {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value === 'boolean') return value;
  const normalized = String(value).trim().toLowerCase();
  if (normalized === 'true' || normalized === '1' || normalized === 'yes') return true;
  if (normalized === 'false' || normalized === '0' || normalized === 'no') return false;
  return undefined;
};

export class ClientsQueryDto {
  @IsOptional()
  @IsString()
  search?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  /**
   * Filtros de la lista de clientes: los mismos que ofrece la UI, aplicados
   * en el SERVIDOR antes de paginar. Si se filtraran solo en el cliente, con
   * la lista paginada se ocultarían registros que existen.
   */
  @IsOptional()
  @Transform(({ value }) =>
    toEnumOrUndefined(value, ['todos', 'conCorreo', 'sinCorreo'] as const),
  )
  @IsString()
  correoFilter?: ClientsCorreoFilter;

  @IsOptional()
  @Transform(({ value }) => toEnumOrUndefined(value, ['todos', 'mine'] as const))
  @IsString()
  ownerFilter?: ClientsOwnerFilter;

  @IsOptional()
  @Transform(({ value }) => toEnumOrUndefined(value, ['az', 'za'] as const))
  @IsString()
  order?: ClientsOrderOption;

  @IsOptional()
  @Transform(({ value }) => toSafePositiveIntOrUndefined(value))
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Transform(({ value }) => toSafePositiveIntOrUndefined(value))
  @IsInt()
  @Min(1)
  @Max(200)
  pageSize?: number;

  @IsOptional()
  @Transform(({ value }) => toSafePositiveIntOrUndefined(value))
  @IsInt()
  @Min(1)
  @Max(200)
  limit?: number;

  @IsOptional()
  @Transform(({ value }) => toBooleanOrUndefined(value))
  @IsBoolean()
  includeDeleted?: boolean;

  @IsOptional()
  @Transform(({ value }) => toBooleanOrUndefined(value))
  @IsBoolean()
  onlyDeleted?: boolean;
}
