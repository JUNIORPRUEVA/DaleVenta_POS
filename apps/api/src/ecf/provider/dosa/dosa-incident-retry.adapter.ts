import { Injectable } from "@nestjs/common";
import type { DosaIncidentRetryRunner } from "./dosa-incident.service";
import type { DosaSessionHintRecorder } from "./dosa-webhook.service";

/**
 * Adaptador de reintento seguro.
 *
 * Traduce la única operación recuperable que el vigilante tiene permitido
 * reejecutar —la vinculación de la postulación a la sesión activa— al contrato
 * mínimo del grabador de pistas.
 *
 * Por qué es seguro reintentarla:
 *
 * * La sentencia exige intento ACTIVO de esa empresa y ese RNC.
 * * Nunca sobrescribe un identificador ya asignado.
 * * Rechaza un identificador que pertenezca a otra empresa.
 *
 * Es decir: ejecutarla dos veces tiene el mismo efecto que ejecutarla una.
 * Cualquier otra operación del flujo (rotar credenciales, activar, emitir) NO
 * pasa por aquí y no se reintenta sola.
 */
@Injectable()
export class DosaIncidentRetryAdapter implements DosaIncidentRetryRunner {
  constructor(private readonly hints: DosaSessionHintRecorder) {}

  async retryBinding(input: {
    companyId: string;
    rnc: string;
    providerPostulationId: string;
  }): Promise<{ ok: boolean; errorCode?: string }> {
    try {
      const result = await this.hints.bindProviderPostulation({
        companyId: input.companyId,
        rnc: input.rnc,
        providerPostulationId: input.providerPostulationId,
      });
      // `bound: false` no es un error de infraestructura: significa que la
      // precondición dejó de cumplirse (sesión cerrada, vínculo ya resuelto,
      // identificador de otra empresa). Se reporta y la incidencia se reevalúa
      // en el siguiente barrido, donde lo normal es que ya no aparezca.
      return result.bound ? { ok: true } : { ok: false, errorCode: "BINDING_NOT_APPLICABLE" };
    } catch {
      // Nunca se propaga el error: el vigilante no debe romper el proceso por
      // una incidencia que precisamente está ahí para ser tolerada.
      return { ok: false, errorCode: "BINDING_FAILED" };
    }
  }
}
