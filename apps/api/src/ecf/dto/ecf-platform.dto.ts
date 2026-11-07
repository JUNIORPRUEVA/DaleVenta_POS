import { IsIn, IsOptional, IsString, MaxLength } from "class-validator";
import {
  ECF_DGII_HABILITATION_STATES,
  type EcfDgiiHabilitationState,
} from "../dgii/ecf-dgii-habilitation.policy";
import { DOSA_INCIDENT_RESOLUTIONS } from "../provider/dosa/dosa-incident.policy";

/** Estados que la COLA de revisión puede filtrar. Lista cerrada. */
export const ECF_PLATFORM_QUEUE_STATES = ECF_DGII_HABILITATION_STATES;

/**
 * Decisión del personal de plataforma sobre una solicitud de habilitación.
 *
 * Deliberadamente NO existe un campo `approve`. La aprobación oficial no es una
 * decisión de interfaz: exige un registro con fuente `DGII_OFFICIAL_RECORD`,
 * evidencia documental, fecha e identificador externo. Si alguien envía
 * `state: "APPROVED"`, la política del servicio lo rechaza con
 * `ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD`.
 *
 * `observations` hace de motivo: en `REQUIRES_CORRECTION` y `REJECTED` es
 * obligatorio, y esa regla la aplica el servicio, no este DTO.
 */
export class DecideEcfDgiiApplicationDto {
  @IsOptional()
  @IsIn([...ECF_DGII_HABILITATION_STATES])
  state?: EcfDgiiHabilitationState;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  reviewState?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  observations?: string | null;
}

/**
 * Cierre de una incidencia DOSA.
 *
 * `resolution` es una lista cerrada (ver `dosa-incident.policy.ts`): cerrar una
 * incidencia es una afirmación auditable, así que se elige de un catálogo y no
 * se escribe texto libre en un campo que luego se lee como estado.
 *
 * No hay campo para «activar credenciales» ni para «rotar»: cerrar la
 * incidencia no toca las credenciales de la empresa.
 */
export class CloseDosaIncidentDto {
  @IsIn([...DOSA_INCIDENT_RESOLUTIONS])
  resolution!: (typeof DOSA_INCIDENT_RESOLUTIONS)[number];
}
