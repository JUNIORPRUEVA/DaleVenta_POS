import { IsIn, IsOptional, IsString, MaxLength, MinLength } from "class-validator";

/**
 * Decisión administrativa sobre un intento de certificación bloqueado.
 *
 * No existe una opción de «reintentar»: el sistema no permite reenviar por haber
 * sufrido un timeout. Solo se confirma si se aplicó (con evidencia) o si no se
 * aplicó (y entonces sí queda reintentable).
 */
export class ResolveEcfAttemptDto {
  @IsIn(["CONFIRM_APPLIED_WITH_EVIDENCE", "CONFIRM_NOT_APPLIED_RETRYABLE"])
  decision!: "CONFIRM_APPLIED_WITH_EVIDENCE" | "CONFIRM_NOT_APPLIED_RETRYABLE";

  /** Referencia a la evidencia que demuestra el resultado (no el documento). */
  @IsOptional()
  @IsString()
  @MaxLength(256)
  evidenceRef?: string;

  /** Identificador externo confirmado, si se conoce. */
  @IsOptional()
  @IsString()
  @MaxLength(128)
  externalId?: string;

  /** Nota de la decisión. No debe contener secretos. */
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  note?: string;
}
