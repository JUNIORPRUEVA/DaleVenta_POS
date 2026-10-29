import { Type } from "class-transformer";
import {
  IsBoolean,
  IsIn,
  IsInt,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  Min,
} from "class-validator";

/**
 * Declaración del encargado: «sí recibí el dinero» de un intento de cobro que el
 * backend no pudo confirmar.
 *
 * Esto NO crea una venta. Solo abre una obligación de conciliación.
 */
export class CreateSaleAttemptDeclarationDto {
  @Type(() => Number)
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0.01)
  totalDeclared!: number;

  /** Momento real del cobro declarado (ISO-8601, UTC). */
  @Matches(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$/, {
    message: "declaredAtUtc debe ser ISO-8601 en UTC",
  })
  declaredAtUtc!: string;

  @IsOptional()
  @IsIn(["cash", "transfer", "card", "mixed", "credit"])
  paymentMethod?: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  declaredByUserId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(32)
  declaredByRole?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  note?: string;

  @IsOptional()
  @IsString()
  @Matches(/^[0-9a-fA-F]{16,64}$/, {
    message: "operationFingerprint debe ser hexadecimal",
  })
  operationFingerprint?: string;

  @IsOptional()
  @IsObject()
  attemptPayload?: Record<string, unknown>;
}

export class ListReconciliationObligationsQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(24)
  status?: string;

  /** Reservado: paginación futura sin romper el contrato actual. */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  limit?: number;

  @IsOptional()
  @IsBoolean()
  includeResolved?: boolean;
}
