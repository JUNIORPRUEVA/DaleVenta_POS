import { Injectable, Logger } from "@nestjs/common";
import type { DosaIncidentKind } from "./dosa-incident.policy";

/**
 * Aviso de incidencia DOSA.
 *
 * Por qué existe como PUERTO y no como envío directo
 * -------------------------------------------------
 * El canal de aviso (WhatsApp de negocio, correo, SMS) es una dependencia
 * externa sujeta a autorización de la plataforma del proveedor: sin plantilla
 * aprobada no se puede enviar nada, y enviar «a cualquier número» sería un
 * riesgo, no una mejora.
 *
 * Lo que sí puede hacerse hoy, sin ninguna autorización pendiente:
 *
 * 1. **Bandeja de plataforma** (`GET /ecf/platform/dosa/incidents`): el registro
 *    durable ya existe y se filtra por concesión de soporte.
 * 2. **Registro operativo** (este puerto con la implementación por defecto): deja
 *    una línea estructurada en el log del servicio, que es lo que alimenta la
 *    alerta del contenedor.
 *
 * Cuando se autorice un canal real, se sustituye el proveedor de
 * `ECF_DOSA_INCIDENT_NOTIFIER` por uno que lo use. **No hay que tocar el
 * servicio de incidencias**: ese es el objetivo del puerto.
 *
 * Reglas del contrato:
 *
 * - Recibe solo datos NO sensibles: empresa, tipo, severidad e identificadores
 *   internos. Nunca credenciales, secretos, RNC completos ni cuerpos de evento.
 * - Nunca lanza: un fallo de aviso no puede tumbar el barrido que lo produjo.
 */
export interface DosaIncidentNotifier {
  notify(input: {
    companyId: string;
    incidentId: string;
    kind: DosaIncidentKind | string;
    severity: string;
    /** Cuántos casos agrupa la incidencia (para no repetir avisos). */
    occurrences: number;
  }): Promise<void>;
}

export const ECF_DOSA_INCIDENT_NOTIFIER = Symbol("ECF_DOSA_INCIDENT_NOTIFIER");

/**
 * Severidades que merecen interrumpir a una persona.
 *
 * Las de severidad baja se acumulan en la bandeja: avisar de cada una es la
 * forma más rápida de que nadie lea los avisos.
 */
const NOTIFIABLE_SEVERITIES = new Set(["HIGH", "CRITICAL", "ALTA", "CRÍTICA"]);

export function isNotifiableSeverity(severity: string): boolean {
  return NOTIFIABLE_SEVERITIES.has((severity ?? "").trim().toUpperCase());
}

/**
 * Implementación por defecto: registro estructurado, sin llamadas externas.
 *
 * Es deliberadamente silenciosa en cuanto a datos: ni RNC, ni nombres, ni
 * fragmentos de evento.
 */
@Injectable()
export class LoggingDosaIncidentNotifier implements DosaIncidentNotifier {
  private readonly logger = new Logger("DosaIncidentAlert");

  async notify(input: {
    companyId: string;
    incidentId: string;
    kind: DosaIncidentKind | string;
    severity: string;
    occurrences: number;
  }): Promise<void> {
    if (!isNotifiableSeverity(input.severity)) return;
    this.logger.warn(
      JSON.stringify({
        event: "ECF_DOSA_INCIDENT",
        companyId: input.companyId,
        incidentId: input.incidentId,
        kind: input.kind,
        severity: input.severity,
        occurrences: input.occurrences,
        // Dónde mirar; no se incluye ningún dato del cliente.
        inbox: "/ecf/platform/dosa/incidents",
      }),
    );
  }
}
