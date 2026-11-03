import { IsString, MaxLength, MinLength } from "class-validator";

/**
 * Contraseña del certificado, junto al archivo multipart.
 *
 * Reglas de este DTO:
 *  - La contraseña **no** se devuelve nunca, ni se escribe en auditoría.
 *  - `MinLength(1)` y `MaxLength` acotado: un PFX no admite contraseñas enormes.
 *  - No se declara `@Expose` ni transformación: si alguien serializa el DTO, el
 *    campo viaja; por eso ninguna capa lo registra.
 */
export class ValidateEcfCertificateDto {
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  password!: string;
}
