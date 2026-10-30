import {
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  MaxLength,
  Min,
} from "class-validator";

/**
 * Borrador del expediente.
 *
 * Se acepta cualquier forma mientras sea un objeto: un borrador puede estar
 * incompleto a propósito. Lo que falta se calcula en el servidor y se devuelve
 * como lista de campos, nunca se rellena solo.
 */
export class SaveEcfDgiiDraftDto {
  @IsObject()
  payload!: Record<string, unknown>;

  /**
   * Revisión sobre la que se editó. Obligatoria cuando ya existe borrador.
   *
   * Es lo que permite rechazar un guardado que llega tarde: sin este dato, una
   * petición lenta con datos antiguos podría pisar un borrador más reciente.
   */
  @IsOptional()
  @IsInt()
  @Min(0)
  expectedRevision?: number;
}

/**
 * Envío a revisión.
 *
 * `consentVersion` se declara OPCIONAL a propósito: si falta, quien responde es
 * la política del servicio con un código estable (`ECF_DGII_CONSENT_REQUIRED`),
 * no el validador con un mensaje de campo. Así existe UNA sola forma de rechazo
 * para el mismo hecho y el cliente puede mapearla. `payload` también es
 * opcional: si no viene, se envía el borrador guardado.
 */
export class SubmitEcfDgiiApplicationDto {
  @IsOptional()
  @IsString()
  @MaxLength(32)
  consentVersion?: string;

  @IsOptional()
  @IsObject()
  payload?: Record<string, unknown>;
}
