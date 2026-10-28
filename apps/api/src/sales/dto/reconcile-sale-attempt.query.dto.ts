import { IsOptional, IsString, Matches } from "class-validator";

/**
 * Consulta de conciliación de un intento de cobro.
 *
 * `expectedTotalSold` es opcional y SOLO sirve para comparar: el servidor nunca
 * escribe nada a partir de él. Se recibe como texto para validar el formato
 * exacto antes de convertirlo a número.
 */
export class ReconcileSaleAttemptQueryDto {
  @IsOptional()
  @IsString()
  @Matches(/^-?\d{1,12}(\.\d{1,2})?$/, {
    message: "SALE_ATTEMPT_EXPECTED_TOTAL_INVALID",
  })
  expectedTotalSold?: string;
}
