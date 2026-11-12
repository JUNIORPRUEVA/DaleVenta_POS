import { Injectable, Logger } from "@nestjs/common";
import { Cron, CronExpression } from "@nestjs/schedule";
import { DosaIncidentService } from "./dosa-incident.service";

/**
 * Bandeja de activación del vigilante.
 *
 * Apagado por defecto y **fail-closed**: sin la bandera explícita no se ejecuta
 * ni una consulta. Se activa solo cuando se autorice el seguimiento automático
 * en el entorno correspondiente, igual que el resto del flujo DOSA.
 */
export function isDosaIncidentMonitorEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return (env.DOSA_INCIDENT_MONITOR_ENABLED ?? "").trim().toLowerCase() === "true";
}

/**
 * Barrido periódico de incidencias DOSA.
 *
 * Cada 10 minutos, no cada minuto: la antigüedad mínima para considerar una
 * condición como incidencia es de 15 minutos (`DEFAULT_STALE_MINUTES`), así que
 * barrer más a menudo no adelantaría ninguna detección y sí multiplicaría las
 * consultas sobre las tablas del flujo fiscal.
 *
 * El trabajo pesado (y el riesgo) vive en `DosaIncidentService`; esto solo lo
 * agenda y registra un resumen **agregado**, sin datos de ninguna empresa.
 */
@Injectable()
export class DosaIncidentScheduler {
  private readonly logger = new Logger(DosaIncidentScheduler.name);

  constructor(private readonly incidents: DosaIncidentService) {}

  @Cron(CronExpression.EVERY_10_MINUTES)
  async sweep(): Promise<void> {
    if (!isDosaIncidentMonitorEnabled()) return;

    try {
      const summary = await this.incidents.scan();
      const touched =
        summary.created +
        summary.retried +
        summary.escalated +
        summary.resolved;
      if (touched > 0 || summary.errors > 0) {
        this.logger.log(
          `Incidencias DOSA: empresas=${summary.scannedCompanies} nuevas=${summary.created} ` +
            `reintentos=${summary.retried} resueltas_por_reintento=${summary.retrySucceeded} ` +
            `escaladas=${summary.escalated} cerradas=${summary.resolved} errores=${summary.errors}`,
        );
      }
    } catch (error) {
      // Un fallo del vigilante no puede tumbar la API: se registra y se espera
      // al siguiente ciclo. El propio servicio ya aísla el error por empresa.
      this.logger.error(
        `El barrido de incidencias DOSA falló: ${
          error instanceof Error ? error.message : String(error)
        }`,
        error instanceof Error ? error.stack : undefined,
      );
    }
  }
}
