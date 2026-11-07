import { Inject, Injectable, Logger, Optional } from "@nestjs/common";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../../../prisma/prisma.service";
import {
  DOSA_INCIDENT_STATUS,
  isDosaIncidentResolution,
  isRetryableIncident,
  type DosaIncidentKind,
  type DosaIncidentResolution,
} from "./dosa-incident.policy";
import {
  planIncidentActions,
  outcomeOfAttempt,
  type DosaIncidentCandidate,
  type DosaIncidentOpenRow,
} from "./dosa-incident.reconcile";

/**
 * Ejecutor de reintentos seguros.
 *
 * Contrato mínimo y **cerrado**: solo sabe reejecutar la vinculación de la
 * postulación, que es idempotente por construcción. No expone «reintentar
 * cualquier cosa»: si mañana hace falta otra operación recuperable, se amplía
 * aquí de forma explícita y con su propia prueba.
 */
export interface DosaIncidentRetryRunner {
  retryBinding(input: {
    companyId: string;
    rnc: string;
    providerPostulationId: string;
  }): Promise<{ ok: boolean; errorCode?: string }>;
}

export const ECF_DOSA_INCIDENT_RETRY = Symbol("ECF_DOSA_INCIDENT_RETRY");

/** Antigüedad mínima para considerar una condición como incidencia. */
const DEFAULT_STALE_MINUTES = 15;

export type DosaIncidentScanSummary = {
  scannedCompanies: number;
  created: number;
  touched: number;
  retried: number;
  retrySucceeded: number;
  escalated: number;
  resolved: number;
  errors: number;
};

/** Fila tal como la devuelve la consulta de detección. */
type DetectionRow = {
  company_id: string;
  rnc: string | null;
  subject_ref: string | null;
  total: string | number | null;
};

/**
 * Seguimiento de incidencias del flujo DOSA.
 *
 * Qué NO hace, deliberadamente:
 *
 * * No reenvía eventos a DOSA ni salta la verificación HMAC.
 * * No guarda ni lee credenciales: trabaja sobre estados y referencias.
 * * No activa credenciales ni cambia estados de certificación.
 * * No mezcla empresas: cada consulta filtra por `company_id` y cada acción se
 *   aplica con `WHERE id = … AND company_id = …`.
 */
@Injectable()
export class DosaIncidentService {
  private readonly logger = new Logger(DosaIncidentService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Optional()
    @Inject(ECF_DOSA_INCIDENT_RETRY)
    private readonly retry?: DosaIncidentRetryRunner,
  ) {}

  /**
   * Barrido completo. Devuelve un resumen agregado (nunca datos sensibles) para
   * que el scheduler pueda registrarlo sin filtrar nada.
   *
   * El fallo de una empresa NO interrumpe a las demás: se captura por empresa y
   * se cuenta en `errors`.
   */
  async scan(
    options: { now?: Date; staleMinutes?: number } = {},
  ): Promise<DosaIncidentScanSummary> {
    const now = options.now ?? new Date();
    const staleMinutes = options.staleMinutes ?? DEFAULT_STALE_MINUTES;
    const summary: DosaIncidentScanSummary = {
      scannedCompanies: 0,
      created: 0,
      touched: 0,
      retried: 0,
      retrySucceeded: 0,
      escalated: 0,
      resolved: 0,
      errors: 0,
    };

    const candidates = await this.detectCandidates(now, staleMinutes);
    const byCompany = new Map<string, DosaIncidentCandidate[]>();
    for (const candidate of candidates) {
      const list = byCompany.get(candidate.companyId) ?? [];
      list.push(candidate);
      byCompany.set(candidate.companyId, list);
    }

    // Empresas con incidencias abiertas que ya no aparecen entre los candidatos
    // también deben visitarse; si no, nunca se cerrarían solas.
    const alreadyOpen = await this.openCompanies();
    for (const companyId of alreadyOpen) {
      if (!byCompany.has(companyId)) byCompany.set(companyId, []);
    }

    for (const [companyId, companyCandidates] of byCompany) {
      summary.scannedCompanies += 1;
      try {
        const openRows = await this.openRowsOf(companyId);
        const actions = planIncidentActions({
          candidates: companyCandidates,
          openRows,
          now,
        });

        for (const action of actions) {
          switch (action.type) {
            case "CREATE": {
              const created = await this.createIncident(
                companyId,
                action.candidate,
                action.incidentKey,
                action.severity,
                now,
              );
              summary.created += 1;
              // Si la incidencia es de un tipo recuperable, se intenta ya: la
              // alternativa sería esperar un ciclo completo de 10 minutos para
              // un reintento que sabemos que es seguro e idempotente.
              if (isRetryableIncident(action.candidate.kind)) {
                const resolvedNow = await this.runRetry(
                  companyId,
                  created.id,
                  action.candidate,
                  now,
                );
                summary.retried += 1;
                if (resolvedNow) summary.retrySucceeded += 1;
              }
              break;
            }
            case "TOUCH":
              await this.touchIncident(companyId, action.id, now);
              summary.touched += 1;
              break;
            case "RETRY": {
              const outcome = await this.runRetry(companyId, action.id, action.candidate, now);
              summary.retried += 1;
              if (outcome) summary.retrySucceeded += 1;
              break;
            }
            case "ESCALATE":
              await this.escalateIncident(companyId, action.id, now);
              summary.escalated += 1;
              break;
            case "RESOLVE":
              await this.resolveIncident(companyId, action.id, now);
              summary.resolved += 1;
              break;
          }
        }
      } catch (error) {
        summary.errors += 1;
        // Sin datos de la empresa en el mensaje: solo el identificador interno.
        this.logger.error(
          `Fallo el barrido de incidencias DOSA para la empresa ${companyId}: ${
            error instanceof Error ? error.message : String(error)
          }`,
          error instanceof Error ? error.stack : undefined,
        );
      }
    }

    return summary;
  }

  /**
   * Incidencias abiertas o escaladas, acotadas a las empresas indicadas.
   *
   * La lista de empresas la decide la capa de autorización (concesión de
   * asistencia), no el cliente HTTP.
   */
  async list(input: {
    companyIds: string[];
    status?: string | null;
    take?: number;
    skip?: number;
  }) {
    const companyIds = [...new Set(input.companyIds.filter((id) => id.length > 0))];
    if (companyIds.length === 0) {
      return { total: 0, items: [] as unknown[] };
    }
    const status = (input.status ?? "").trim().toUpperCase();
    const where = {
      companyId: { in: companyIds },
      ...(status.length > 0
        ? { status }
        : { status: { in: [DOSA_INCIDENT_STATUS.OPEN, DOSA_INCIDENT_STATUS.ESCALATED] } }),
    };
    const take = Math.min(Math.max(input.take ?? 50, 1), 200);
    const skip = Math.max(input.skip ?? 0, 0);

    const [rows, total] = await this.prisma.$transaction([
      this.prisma.ecfDosaIncident.findMany({
        where,
        orderBy: [{ severity: "asc" }, { lastSeenAt: "desc" }],
        take,
        skip,
        select: {
          id: true,
          companyId: true,
          rnc: true,
          kind: true,
          severity: true,
          status: true,
          subjectType: true,
          subjectRef: true,
          attempts: true,
          nextAttemptAt: true,
          lastErrorCode: true,
          resolution: true,
          firstSeenAt: true,
          lastSeenAt: true,
          resolvedAt: true,
          company: { select: { name: true } },
        },
      }),
      this.prisma.ecfDosaIncident.count({ where }),
    ]);

    return { total, items: rows };
  }

  /**
   * Cierre administrativo de una incidencia.
   *
   * Motivo obligatorio de una lista cerrada. Solo afecta a la incidencia: no
   * activa credenciales, no rota nada y no cambia el estado de certificación.
   */
  async close(input: {
    incidentId: string;
    companyId: string;
    resolution: string;
    actorUserId: string;
  }) {
    if (!isDosaIncidentResolution(input.resolution)) {
      return { ok: false as const, blockedReason: "RESOLUTION_NOT_ALLOWED" };
    }
    const updated = await this.prisma.ecfDosaIncident.updateMany({
      where: {
        id: input.incidentId,
        companyId: input.companyId,
        status: { in: [DOSA_INCIDENT_STATUS.OPEN, DOSA_INCIDENT_STATUS.ESCALATED] },
      },
      data: {
        status: DOSA_INCIDENT_STATUS.CLOSED,
        resolution: input.resolution satisfies DosaIncidentResolution,
        resolvedAt: new Date(),
        resolvedByUserId: input.actorUserId,
        nextAttemptAt: null,
      },
    });
    if (updated.count !== 1) {
      return { ok: false as const, blockedReason: "INCIDENT_NOT_OPEN" };
    }
    return { ok: true as const };
  }

  /**
   * Detección por empresa. Cada consulta es independiente y filtra por su
   * propio criterio; el `UNION` lo compone la capa de decisión, no el SQL, para
   * que cada condición sea legible y auditable por separado.
   */
  private async detectCandidates(
    now: Date,
    staleMinutes: number,
  ): Promise<DosaIncidentCandidate[]> {
    const since = new Date(now.getTime() - staleMinutes * 60_000);
    const candidates: DosaIncidentCandidate[] = [];

    // 1. Eventos autenticados cuyas credenciales no se pudieron guardar.
    const notStored = await this.prisma.$queryRaw<DetectionRow[]>`
      SELECT e."company_id" AS company_id,
             e."payload_summary"->>'rnc' AS rnc,
             e."postulacion_id" AS subject_ref,
             COUNT(*) AS total
        FROM "ecf_dosa_webhook_events" e
       WHERE e."processing_state" = 'PENDING_CREDENTIALS'
         AND e."received_at" < ${since}
       GROUP BY e."company_id", e."payload_summary"->>'rnc', e."postulacion_id"
    `;
    for (const row of notStored) {
      candidates.push({
        companyId: row.company_id,
        rnc: row.rnc,
        kind: "EVENT_CREDENTIALS_NOT_STORED",
        subjectType: "WEBHOOK_EVENT",
        subjectRef: row.subject_ref,
        detail: { events: toCount(row.total) },
      });
    }

    // 2. Conflictos de credenciales: la rotación es un acto humano.
    const conflicts = await this.prisma.$queryRaw<DetectionRow[]>`
      SELECT e."company_id" AS company_id,
             e."payload_summary"->>'rnc' AS rnc,
             e."postulacion_id" AS subject_ref,
             COUNT(*) AS total
        FROM "ecf_dosa_webhook_events" e
       WHERE e."processing_state" = 'CONFLICT_PENDING_REVIEW'
       GROUP BY e."company_id", e."payload_summary"->>'rnc', e."postulacion_id"
    `;
    for (const row of conflicts) {
      candidates.push({
        companyId: row.company_id,
        rnc: row.rnc,
        kind: "CREDENTIAL_CONFLICT_REVIEW",
        subjectType: "WEBHOOK_EVENT",
        subjectRef: row.subject_ref,
        detail: { events: toCount(row.total) },
      });
    }

    // 3. Credenciales esperando confirmación humana.
    const awaiting = await this.prisma.$queryRaw<DetectionRow[]>`
      SELECT c."company_id" AS company_id,
             c."rnc" AS rnc,
             c."environment" AS subject_ref,
             COUNT(*) AS total
        FROM "ecf_dosa_company_credentials" c
       WHERE c."status" = 'PENDING_CONFIRMATION'
         AND c."created_at" < ${since}
       GROUP BY c."company_id", c."rnc", c."environment"
    `;
    for (const row of awaiting) {
      candidates.push({
        companyId: row.company_id,
        rnc: row.rnc,
        kind: "CREDENTIAL_AWAITING_CONFIRMATION",
        subjectType: "CREDENTIAL",
        subjectRef: row.subject_ref,
        detail: { environments: toCount(row.total) },
      });
    }

    // 4. Evento con postulación que la sesión activa todavía no vinculó.
    //
    // Solo cuenta si el vínculo es POSIBLE: intento activo, sin identificador
    // asignado y sin que otra empresa lo tenga. Si otra empresa lo tiene, es un
    // conflicto de identidad y NO se reintenta: lo revisa una persona.
    const unbound = await this.prisma.$queryRaw<DetectionRow[]>`
      SELECT e."company_id" AS company_id,
             e."payload_summary"->>'rnc' AS rnc,
             e."postulacion_id" AS subject_ref,
             COUNT(*) AS total
        FROM "ecf_dosa_webhook_events" e
        JOIN "ecf_dosa_certification_sessions" s
          ON s."company_id" = e."company_id"
         AND s."rnc" = e."payload_summary"->>'rnc'
         AND s."active_key" = e."company_id"::text || ':' || (e."payload_summary"->>'rnc')
       WHERE e."postulacion_id" IS NOT NULL
         -- Solo eventos ya procesados: uno atascado en PENDING_CREDENTIALS ya
         -- tiene su propia incidencia y no debe ademas reclamar el vinculo.
         AND e."processing_state" = 'COMPLETE'
         AND s."provider_postulation_id" IS NULL
         AND NOT EXISTS (
           SELECT 1 FROM "ecf_dosa_certification_sessions" otro
            WHERE otro."provider_postulation_id" = e."postulacion_id"
              AND otro."company_id" <> e."company_id"
         )
       GROUP BY e."company_id", e."payload_summary"->>'rnc', e."postulacion_id"
    `;
    for (const row of unbound) {
      candidates.push({
        companyId: row.company_id,
        rnc: row.rnc,
        kind: "POSTULATION_NOT_BOUND",
        subjectType: "SESSION",
        subjectRef: row.subject_ref,
        detail: { events: toCount(row.total) },
      });
    }

    // 5. Eventos sin tipo confirmado: una sola incidencia por empresa.
    //
    // Se agrega a propósito. DOSA no envía campo de tipo de evento, así que
    // cada evento carece de tipo; abrir una incidencia por evento llenaría el
    // panel de ruido idéntico y escondería las incidencias que sí importan.
    const unclassified = await this.prisma.$queryRaw<DetectionRow[]>`
      SELECT e."company_id" AS company_id,
             NULL::varchar AS rnc,
             NULL::varchar AS subject_ref,
             COUNT(*) AS total
        FROM "ecf_dosa_webhook_events" e
       WHERE e."event_type" = 'PENDING_CLASSIFICATION'
       GROUP BY e."company_id"
    `;
    for (const row of unclassified) {
      candidates.push({
        companyId: row.company_id,
        rnc: row.rnc,
        kind: "EVENT_TYPE_UNKNOWN",
        subjectType: "WEBHOOK_EVENT",
        subjectRef: null,
        detail: { events: toCount(row.total) },
      });
    }

    return candidates;
  }

  private async openCompanies(): Promise<string[]> {
    const rows = await this.prisma.ecfDosaIncident.findMany({
      where: { status: { in: [DOSA_INCIDENT_STATUS.OPEN, DOSA_INCIDENT_STATUS.ESCALATED] } },
      select: { companyId: true },
      distinct: ["companyId"],
      take: 500,
    });
    return rows.map((row) => row.companyId);
  }

  private async openRowsOf(companyId: string): Promise<DosaIncidentOpenRow[]> {
    const rows = await this.prisma.ecfDosaIncident.findMany({
      where: {
        companyId,
        status: { in: [DOSA_INCIDENT_STATUS.OPEN, DOSA_INCIDENT_STATUS.ESCALATED] },
      },
      select: {
        id: true,
        incidentKey: true,
        kind: true,
        status: true,
        attempts: true,
        nextAttemptAt: true,
      },
    });
    return rows;
  }

  private async createIncident(
    companyId: string,
    candidate: DosaIncidentCandidate,
    incidentKey: string,
    severity: string,
    now: Date,
  ) {
    // `createMany` con `skipDuplicates` no existe para todos los conectores;
    // el UPSERT sobre la clave única es explícito y no falla si dos barridos
    // coinciden.
    return this.prisma.ecfDosaIncident.upsert({
      where: { companyId_incidentKey: { companyId, incidentKey } },
      create: {
        companyId,
        rnc: candidate.rnc,
        incidentKey,
        kind: candidate.kind,
        severity,
        status: DOSA_INCIDENT_STATUS.OPEN,
        subjectType: candidate.subjectType,
        subjectRef: candidate.subjectRef,
        detail: toJson(candidate.detail),
        // La primera revisión automática se agenda con backoff; la incidencia
        // ya queda visible en el panel desde el primer barrido.
        nextAttemptAt: null,
        firstSeenAt: now,
        lastSeenAt: now,
      },
      update: {
        lastSeenAt: now,
        detail: toJson(candidate.detail),
      },
      select: { id: true },
    });
  }

  private async touchIncident(companyId: string, id: string, now: Date) {
    await this.prisma.ecfDosaIncident.updateMany({
      where: { id, companyId },
      data: { lastSeenAt: now },
    });
  }

  private async escalateIncident(companyId: string, id: string, now: Date) {
    await this.prisma.ecfDosaIncident.updateMany({
      where: { id, companyId },
      data: {
        status: DOSA_INCIDENT_STATUS.ESCALATED,
        nextAttemptAt: null,
        lastSeenAt: now,
        lastErrorCode: "RETRY_EXHAUSTED",
      },
    });
  }

  private async resolveIncident(companyId: string, id: string, now: Date) {
    await this.prisma.ecfDosaIncident.updateMany({
      where: { id, companyId },
      data: {
        status: DOSA_INCIDENT_STATUS.RESOLVED,
        nextAttemptAt: null,
        resolvedAt: now,
      },
    });
  }

  /** Devuelve `true` si el reintento resolvió la incidencia. */
  private async runRetry(
    companyId: string,
    id: string,
    candidate: DosaIncidentCandidate,
    now: Date,
  ): Promise<boolean> {
    const row = await this.prisma.ecfDosaIncident.findFirst({
      where: { id, companyId },
      select: { attempts: true },
    });
    const attempts = row?.attempts ?? 0;

    let succeeded = false;
    let errorCode: string | null = null;

    if (candidate.kind !== "POSTULATION_NOT_BOUND") {
      // Guarda de seguridad: aunque la política cambie, aquí solo se reintenta
      // lo que este bloque sabe hacer.
      errorCode = "RETRY_NOT_SUPPORTED";
    } else if (!this.retry) {
      errorCode = "RETRY_RUNNER_NOT_CONFIGURED";
    } else if (!candidate.rnc || !candidate.subjectRef) {
      errorCode = "RETRY_SUBJECT_INCOMPLETE";
    } else {
      try {
        const result = await this.retry.retryBinding({
          companyId,
          rnc: candidate.rnc,
          providerPostulationId: candidate.subjectRef,
        });
        succeeded = result.ok;
        if (!result.ok) errorCode = result.errorCode ?? "RETRY_REJECTED";
      } catch (error) {
        errorCode = "RETRY_THREW";
        this.logger.warn(
          `Reintento de vínculo fallido (empresa ${companyId}): ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }

    const outcome = outcomeOfAttempt({ attempts, now, succeeded, errorCode });
    await this.prisma.ecfDosaIncident.updateMany({
      where: { id, companyId },
      data: {
        attempts: outcome.attempts,
        lastAttemptAt: now,
        lastSeenAt: now,
        nextAttemptAt: outcome.nextAttemptAt,
        status: outcome.status,
        lastErrorCode: outcome.lastErrorCode,
        ...(succeeded ? { resolvedAt: now } : {}),
      },
    });

    return succeeded;
  }
}

function toJson(detail: Record<string, unknown> | undefined): Prisma.InputJsonValue {
  // Solo se persisten contadores y referencias; nunca credenciales.
  return (detail ?? {}) as Prisma.InputJsonValue;
}

function toCount(value: string | number | null): number {
  if (typeof value === "number") return value;
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}
