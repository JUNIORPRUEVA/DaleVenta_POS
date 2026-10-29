import { Inject, Injectable, Logger } from '@nestjs/common';
import {
  GuardianDiagnosisStatus,
  GuardianDiagnosisVerdict,
  GuardianProcessingState,
  GuardianSeverity,
  Prisma,
} from '@prisma/client';
import { createHash } from 'node:crypto';
import { PrismaService } from '../prisma/prisma.service';
import { resolveGuardianConfig } from './guardian.config';
import {
  GUARDIAN_AI_PROVIDER,
  GuardianAiError,
  GuardianAiProvider,
  GuardianAiRequest,
  GuardianToolCallTrace,
} from './ai/guardian-ai.provider';
import { sanitizeUntrustedText, sanitizeUntrustedValue } from './ai/guardian.ai.sanitizer';
import { GuardianToolsService } from './guardian.tools.service';
import { resolveGuardianAiRuntime } from './ai/guardian.ai.runtime';
import {
  GUARDIAN_COMPANY_DISABLED,
  isGuardianEnabledForCompany,
} from './guardian.company.policy';

const MAX_BACKOFF_MS = 30 * 60_000;
const BUDGET_WINDOW_MS = 24 * 60 * 60 * 1000;
/** Aplazamiento de un incidente con fallo irreversible: fuera de la cola. */
const TERMINAL_DEFER_MS = BUDGET_WINDOW_MS;
/**
 * Clave del advisory lock que serializa la reserva de presupuesto global.
 * Número fijo y propio de Guardian: no colisiona con otras áreas del sistema.
 */
const GUARDIAN_GLOBAL_BUDGET_LOCK = 727_272_001;

@Injectable()
export class GuardianDiagnosisService {
  private readonly logger = new Logger(GuardianDiagnosisService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly tools: GuardianToolsService,
    @Inject(GUARDIAN_AI_PROVIDER) readonly provider: GuardianAiProvider,
  ) {}

  /**
   * Reclama incidentes pendientes con compare-and-swap (seguro con varios workers).
   */
  async claimDueIncidents(limit = 5) {
    const now = new Date();
    const baseWhere: Prisma.GuardianIncidentWhereInput = {
      processingState: GuardianProcessingState.PENDING,
      nextDiagnosisAt: { lte: now },
    };

    const candidates = await this.prisma.guardianIncident.findMany({
      where: baseWhere,
      select: { id: true },
      orderBy: [{ severity: 'asc' }, { nextDiagnosisAt: 'asc' }],
      take: limit,
    });

    const claimed: string[] = [];
    for (const candidate of candidates) {
      const result = await this.prisma.guardianIncident.updateMany({
        where: { id: candidate.id, ...baseWhere },
        data: {
          processingState: GuardianProcessingState.DIAGNOSING,
          diagnosisAttempts: { increment: 1 },
        },
      });
      if (result.count === 1) claimed.push(candidate.id);
    }

    if (!claimed.length) return [];
    return this.prisma.guardianIncident.findMany({ where: { id: { in: claimed } } });
  }

  async runBatch(limit = 5) {
    const config = resolveGuardianConfig();
    if (!config.diagnosisEnabled) {
      return { ok: true, enabled: false, processed: 0, diagnosed: 0, failed: 0 };
    }

    const incidents = await this.claimDueIncidents(limit);
    let diagnosed = 0;
    let failed = 0;

    for (const incident of incidents) {
      const outcome = await this.diagnose(incident.id).catch((error) => {
        this.logger.error(
          `Diagnóstico falló incident=${incident.id}: ${error instanceof Error ? error.message : String(error)}`,
        );
        return { ok: false as const };
      });
      if (outcome.ok) diagnosed += 1;
      else failed += 1;
    }

    return { ok: true, enabled: true, processed: incidents.length, diagnosed, failed };
  }

  /**
   * Diagnostica un incidente. Nunca lanza: en caso de fallo reprograma y deja el
   * incidente en PENDING (la alerta crítica ya se envió en la ingesta).
   */
  async diagnose(incidentId: string) {
    const config = resolveGuardianConfig();
    const incident = await this.prisma.guardianIncident.findUnique({ where: { id: incidentId } });
    if (!incident) return { ok: false as const, reason: 'NOT_FOUND' };

    // Fase 7 — la empresa debe tener Guardian activado. No se borra historial:
    // el incidente pasa a SKIPPED y se aplaza fuera de la cola.
    if (!(await isGuardianEnabledForCompany(this.prisma, incident.companyId))) {
      await this.prisma.guardianIncident.update({
        where: { id: incidentId },
        data: {
          processingState: GuardianProcessingState.SKIPPED,
          nextDiagnosisAt: new Date(Date.now() + TERMINAL_DEFER_MS),
        },
      });
      this.logger.warn(
        `Diagnóstico omitido: empresa con Guardian desactivado incident=${incidentId}`,
      );
      return { ok: true, skipped: GUARDIAN_COMPANY_DISABLED };
    }

    // Presupuesto por empresa: evita que un bucle de errores de un solo cliente
    // consuma el saldo de IA de toda la plataforma.
    if (await this.isCompanyBudgetExhausted(incident.companyId, config.aiTokensPerCompanyDay)) {
      await this.prisma.$transaction([
        this.prisma.guardianIncident.update({
          where: { id: incidentId },
          data: {
            processingState: GuardianProcessingState.SKIPPED,
            nextDiagnosisAt: new Date(Date.now() + BUDGET_WINDOW_MS),
          },
        }),
        this.prisma.guardianDiagnosis.create({
          data: {
            incidentId,
            status: GuardianDiagnosisStatus.DONE,
            verdict: GuardianDiagnosisVerdict.INSUFFICIENT,
            confidence: new Prisma.Decimal('0.00'),
            summary: 'El presupuesto diario de IA de la empresa está agotado; no se emitió diagnóstico.',
            explanation:
              'Guardian no llamó al proveedor de IA para no exceder el presupuesto configurado. ' +
              'El incidente queda registrado y la alerta administrativa ya fue planificada.',
            nextSteps: [
              'Revisar el presupuesto de IA de la empresa',
              'Reprocesar el incidente cuando se restablezca el presupuesto',
            ],
            evidenceRefs: [] as unknown as Prisma.InputJsonValue,
            toolCalls: [] as unknown as Prisma.InputJsonValue,
            model: 'budget-guard',
          },
        }),
      ]);
      this.logger.warn(`Diagnóstico omitido por presupuesto incident=${incidentId}`);
      return { ok: true as const, skipped: 'AI_BUDGET_EXCEEDED' as const };
    }

    // Fase 7 — reserva atómica de presupuesto GLOBAL + creación de la fila
    // RUNNING dentro de la misma transacción con advisory lock: dos workers
    // concurrentes no pueden sobrepasar el tope, porque la fila RUNNING cuenta
    // como reserva mientras la llamada está en vuelo.
    const slot = await this.claimGlobalBudgetSlot({
      incidentId,
      attempts: incident.diagnosisAttempts,
      model: this.provider.name,
      dailyLimit: config.aiTokensGlobalDay,
      monthlyLimit: config.aiTokensGlobalMonth,
    });
    if (!slot.ok) {
      await this.prisma.$transaction([
        this.prisma.guardianIncident.update({
          where: { id: incidentId },
          data: {
            processingState: GuardianProcessingState.SKIPPED,
            nextDiagnosisAt: new Date(Date.now() + BUDGET_WINDOW_MS),
          },
        }),
        this.prisma.guardianDiagnosis.create({
          data: {
            incidentId,
            status: GuardianDiagnosisStatus.DONE,
            verdict: GuardianDiagnosisVerdict.INSUFFICIENT,
            confidence: new Prisma.Decimal('0.00'),
            summary:
              'El presupuesto global de IA de la plataforma está agotado; no se emitió diagnóstico.',
            explanation:
              'Guardian no llamó al proveedor de IA para no exceder el presupuesto global configurado. ' +
              'El incidente queda registrado y puede reprocesarse cuando el presupuesto se restablezca.',
            nextSteps: [
              'Revisar el consumo global de IA de la plataforma',
              'Reprocesar el incidente cuando se restablezca el presupuesto',
            ],
            evidenceRefs: [] as unknown as Prisma.InputJsonValue,
            toolCalls: [
              { tool: 'ai_budget', status: 'skipped', detail: slot.detail },
            ] as unknown as Prisma.InputJsonValue,
            model: 'global-budget-guard',
          },
        }),
      ]);
      this.logger.warn(
        `Diagnóstico omitido por presupuesto GLOBAL incident=${incidentId} ${slot.detail}`,
      );
      return { ok: true as const, skipped: 'AI_GLOBAL_BUDGET_EXCEEDED' as const };
    }

    const diagnosis = { id: slot.diagnosisId };

    const toolCalls: GuardianToolCallTrace[] = [];
    try {
      const request = await this.buildRequest(incident, toolCalls);
      const promptHash = createHash('sha256')
        .update(JSON.stringify(request))
        .digest('hex')
        .slice(0, 64);
      const result = await this.provider.analyze(request);

      const enforced = this.enforceVerdictRules(result);

      await this.prisma.$transaction([
        this.prisma.guardianDiagnosis.update({
          where: { id: diagnosis.id },
          data: {
            status: GuardianDiagnosisStatus.DONE,
            verdict: enforced.verdict,
            confidence: new Prisma.Decimal(enforced.confidence.toFixed(2)),
            summary: enforced.summary,
            impact: enforced.impact,
            causeCategory: enforced.causeCategory,
            explanation: enforced.explanation,
            nextSteps: enforced.nextSteps as unknown as Prisma.InputJsonValue,
            evidenceRefs: enforced.evidenceRefs as unknown as Prisma.InputJsonValue,
            toolCalls: [...toolCalls, ...result.toolCalls] as unknown as Prisma.InputJsonValue,
            model: result.model,
            promptHash,
            tokensUsed: result.tokensUsed,
            durationMs: result.durationMs,
            error: null,
          },
        }),
        this.prisma.guardianIncident.update({
          where: { id: incidentId },
          data: {
            processingState: GuardianProcessingState.DIAGNOSED,
            impactSummary: (enforced.impact ?? incident.impactSummary ?? '').slice(0, 400) || null,
          },
        }),
      ]);

      return { ok: true as const, diagnosisId: diagnosis.id, verdict: enforced.verdict };
    } catch (error) {
      const attempts = incident.diagnosisAttempts;
      const maxAttempts = config.diagnosisMaxAttempts;
      const aiError = error instanceof GuardianAiError ? error : null;
      // Un fallo determinista (respuesta vacía, JSON truncado, esquema
      // incompleto o proveedor sin credenciales) NO se reintenta: repetiría la
      // misma llamada facturable con la misma entrada y el mismo resultado.
      const deterministic = aiError !== null && aiError.retryable === false;
      const providerRetryAfterMs = Number(
        (error as { retryAfterMs?: number } | null)?.retryAfterMs ?? 0,
      );
      const backoffMs = deterministic
        ? TERMINAL_DEFER_MS
        : Math.min(
            MAX_BACKOFF_MS,
            Math.max(
              Number.isFinite(providerRetryAfterMs) ? providerRetryAfterMs : 0,
              60_000 * Math.pow(2, Math.max(0, attempts - 1)),
            ),
          );
      const baseMessage = error instanceof Error ? error.message : String(error);
      // Metadatos seguros de la respuesta (sin contenido crudo del proveedor).
      const meta = aiError?.diagnosticSummary ?? '';
      const message = [baseMessage, meta].filter(Boolean).join(' ').slice(0, 600);
      const trace: GuardianToolCallTrace | null =
        meta.length > 0
          ? { tool: 'ai_response', status: 'error', detail: meta.slice(0, 300) }
          : null;

      await this.prisma.$transaction([
        this.prisma.guardianDiagnosis.update({
          where: { id: diagnosis.id },
          data: {
            status: GuardianDiagnosisStatus.FAILED,
            error: message,
            toolCalls: [...toolCalls, ...(trace ? [trace] : [])] as unknown as Prisma.InputJsonValue,
          },
        }),
        this.prisma.guardianIncident.update({
          where: { id: incidentId },
          data: {
            processingState:
              deterministic || attempts >= maxAttempts
                ? GuardianProcessingState.FAILED
                : GuardianProcessingState.PENDING,
            nextDiagnosisAt: new Date(Date.now() + backoffMs),
          },
        }),
      ]);

      this.logger.warn(
        `Diagnóstico ${deterministic ? 'descartado (no reintentable)' : 'reprogramado'} incident=${incidentId} attempts=${attempts}` +
          `${aiError ? ` codigo=${aiError.code}` : ''} error=${baseMessage}${meta ? ` ${meta}` : ''}`,
      );
      return {
        ok: false as const,
        reason: deterministic ? ('PROVIDER_OUTPUT_INVALID' as const) : ('PROVIDER_ERROR' as const),
        retryable: !deterministic,
        errorCode: aiError?.code ?? null,
      };
    }
  }

  /**
   * Verifica que nunca se afirme una causa sin evidencia verificable.
   */
  enforceVerdictRules(result: {
    verdict: GuardianDiagnosisVerdict;
    confidence: number;
    summary: string;
    impact: string | null;
    causeCategory: string | null;
    explanation: string;
    nextSteps: string[];
    evidenceRefs: Array<{ type: string; ref: string; note?: string }>;
  }) {
    const evidenceRefs = result.evidenceRefs.filter((ref) => ref && typeof ref.ref === 'string' && ref.ref.length > 0);
    const confidence = Math.min(1, Math.max(0, Number(result.confidence) || 0));

    // Sin evidencia verificable no se puede afirmar ninguna causa.
    if (evidenceRefs.length === 0) {
      return {
        ...result,
        verdict: GuardianDiagnosisVerdict.INSUFFICIENT,
        confidence: Math.min(confidence, 0.2),
        causeCategory: null,
        summary: result.summary || 'Información insuficiente para determinar la causa.',
        explanation:
          result.explanation ||
          'El diagnóstico no reunió evidencia verificable suficiente para concluir.',
        evidenceRefs,
        downgraded: true,
      };
    }

    if (result.verdict === GuardianDiagnosisVerdict.INSUFFICIENT) {
      return { ...result, confidence: Math.min(confidence, 0.5), evidenceRefs };
    }

    return { ...result, confidence, evidenceRefs };
  }

  /**
   * Reserva atómica del presupuesto GLOBAL de IA y creación de la fila RUNNING.
   *
   * Por qué así:
   * - `pg_advisory_xact_lock` serializa el cálculo entre workers (el lock se
   *   libera al cerrar la transacción).
   * - La fila `RUNNING` se crea **dentro** de la misma transacción, así que
   *   cuenta como reserva de `max_tokens` mientras la llamada está en vuelo.
   *   Dos workers concurrentes no pueden pasar ambos si el tope está al límite.
   * - `0` significa «sin límite» (misma semántica que el presupuesto por
   *   empresa) para no romper entornos que no configuran la variable.
   * - Si se agota, no se llama al proveedor: cero coste.
   */
  private async claimGlobalBudgetSlot(params: {
    incidentId: string;
    attempts: number;
    model: string;
    dailyLimit: number;
    monthlyLimit: number;
  }): Promise<{ ok: true; diagnosisId: string } | { ok: false; detail: string }> {
    const reserve = Math.max(1, resolveGuardianAiRuntime().maxTokens);

    return this.prisma.$transaction(async (tx) => {
      await tx.$executeRaw`SELECT pg_advisory_xact_lock(${GUARDIAN_GLOBAL_BUDGET_LOCK})`;

      const now = new Date();
      const dayStart = new Date(
        Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
      );
      const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));

      const usage = async (since: Date) => {
        const [used, running] = await Promise.all([
          tx.guardianDiagnosis.aggregate({
            _sum: { tokensUsed: true },
            where: { createdAt: { gte: since } },
          }),
          tx.guardianDiagnosis.count({
            where: { status: GuardianDiagnosisStatus.RUNNING, createdAt: { gte: since } },
          }),
        ]);
        return {
          consumed: Number(used._sum.tokensUsed ?? 0),
          reserved: running * reserve,
        };
      };

      if (params.dailyLimit > 0) {
        const day = await usage(dayStart);
        if (day.consumed + day.reserved + reserve > params.dailyLimit) {
          return {
            ok: false as const,
            detail: `dia consumido=${day.consumed} reservado=${day.reserved} tope=${params.dailyLimit}`,
          };
        }
      }
      if (params.monthlyLimit > 0) {
        const month = await usage(monthStart);
        if (month.consumed + month.reserved + reserve > params.monthlyLimit) {
          return {
            ok: false as const,
            detail: `mes consumido=${month.consumed} reservado=${month.reserved} tope=${params.monthlyLimit}`,
          };
        }
      }

      const created = await tx.guardianDiagnosis.create({
        data: {
          incidentId: params.incidentId,
          status: GuardianDiagnosisStatus.RUNNING,
          attempts: params.attempts,
          model: params.model,
        },
      });
      return { ok: true as const, diagnosisId: created.id };
    });
  }

  /**
   * Presupuesto diario de tokens por empresa.
   *
   * Se calcula con la suma real de `tokens_used` de los diagnósticos de la
   * empresa (vía la relación con el incidente), no con contadores en memoria:
   * sobrevive reinicios y es correcto con varios workers.
   */
  private async isCompanyBudgetExhausted(companyId: string, dailyLimit: number): Promise<boolean> {
    if (!Number.isFinite(dailyLimit) || dailyLimit <= 0) return false;
    const since = new Date(Date.now() - BUDGET_WINDOW_MS);
    const aggregate = await this.prisma.guardianDiagnosis.aggregate({
      _sum: { tokensUsed: true },
      where: {
        createdAt: { gte: since },
        incident: { companyId },
      },
    });
    const used = Number(aggregate._sum.tokensUsed ?? 0);
    return used >= dailyLimit;
  }

  private async buildRequest(
    incident: {
      id: string;
      companyId: string;
      module: string;
      operation: string;
      severity: GuardianSeverity;
      exceptionType: string | null;
      platform: string | null;
      appVersion: string | null;
      occurredAt: Date;
      impactSummary: string | null;
      fingerprint: string;
      payload: unknown;
      stack: string | null;
    },
    toolCalls: GuardianToolCallTrace[],
  ): Promise<GuardianAiRequest> {
    const startedAt = Date.now();

    const similarIncidents = await this.prisma.guardianIncident.findMany({
      where: {
        fingerprint: incident.fingerprint,
        id: { not: incident.id },
        occurredAt: { gte: new Date(incident.occurredAt.getTime() - 30 * 24 * 60 * 60 * 1000) },
      },
      select: { id: true, companyId: true, occurredAt: true, appVersion: true },
      orderBy: { occurredAt: 'desc' },
      take: 10,
    });
    toolCalls.push({ tool: 'findSimilarIncidents', status: 'ok', detail: `${similarIncidents.length} filas`, ms: Date.now() - startedAt });

    const company = await this.prisma.company.findUnique({
      where: { id: incident.companyId },
      select: { id: true, plan: true, licenseStatus: true, createdAt: true },
    });

    const businessFacts: Record<string, unknown> = {};
    const queryKey = this.queryForModule(incident.module);
    if (queryKey) {
      const queryStartedAt = Date.now();
      try {
        const rows = await this.tools.runPredefinedQuery(queryKey, [incident.companyId]);
        businessFacts[queryKey] = rows;
        toolCalls.push({ tool: queryKey, status: 'ok', ms: Date.now() - queryStartedAt });
      } catch (error) {
        toolCalls.push({
          tool: queryKey,
          status: 'error',
          detail: error instanceof Error ? error.message.slice(0, 120) : 'error',
          ms: Date.now() - queryStartedAt,
        });
      }
    }

    const identifiers = this.extractIdentifiers(incident.stack, incident.exceptionType);
    const code = this.tools.searchCode(identifiers);
    toolCalls.push(code.trace);

    const versionTimeline = await this.prisma.appRelease.findMany({
      where: { publishedAt: { gte: new Date(incident.occurredAt.getTime() - 45 * 24 * 60 * 60 * 1000) } },
      select: { version: true, platform: true, publishedAt: true },
      orderBy: { publishedAt: 'desc' },
      take: 10,
    });

    return {
      incident: {
        id: incident.id,
        module: incident.module,
        operation: incident.operation,
        severity: String(incident.severity),
        exceptionType: incident.exceptionType,
        platform: incident.platform,
        appVersion: incident.appVersion,
        occurredAt: incident.occurredAt.toISOString(),
        message: this.messageFromPayload(incident.payload)
          ? sanitizeUntrustedText(this.messageFromPayload(incident.payload), 600)
          : null,
        stack: incident.stack ? sanitizeUntrustedText(incident.stack, 8_000) : null,
        impactSummary: incident.impactSummary
          ? sanitizeUntrustedText(incident.impactSummary, 400)
          : null,
      },
      similarIncidents: similarIncidents.map((row) => ({
        id: row.id,
        companyId: row.companyId,
        occurredAt: row.occurredAt.toISOString(),
        appVersion: row.appVersion,
      })),
      company: company
        ? {
            id: company.id,
            plan: String(company.plan),
            licenseStatus: String(company.licenseStatus),
            createdAt: company.createdAt.toISOString(),
          }
        : null,
      businessFacts: sanitizeUntrustedValue(businessFacts) as Record<string, unknown>,
      codeMatches: code.matches.map((match) => ({
        file: match.file,
        line: match.line,
        snippet: sanitizeUntrustedText(match.snippet, 160),
      })),
      versionTimeline: versionTimeline.map((row) => ({
        version: row.version,
        platform: String(row.platform),
        publishedAt: row.publishedAt ? row.publishedAt.toISOString() : null,
      })),
    };
  }

  private queryForModule(module: string): string | null {
    switch (module) {
      case 'cash':
        return 'cash_activity_24h';
      case 'sales':
        return 'sales_activity_24h';
      case 'sync':
        return 'sync_recent_errors';
      case 'license':
        return 'license_state';
      default:
        return null;
    }
  }

  private messageFromPayload(payload: unknown): string | null {
    if (!payload || typeof payload !== 'object') return null;
    const message = (payload as Record<string, unknown>).message;
    return typeof message === 'string' ? message : null;
  }

  private extractIdentifiers(stack: string | null, exceptionType: string | null): string[] {
    const candidates = new Set<string>();
    if (exceptionType) candidates.add(exceptionType);
    for (const line of String(stack ?? '').split(/\r?\n/)) {
      const match = /at\s+([A-Za-z_$][\w$]*(\.[A-Za-z_$][\w$]*)?)/.exec(line.trim());
      if (match?.[1]) candidates.add(match[1]);
    }

    // `Clase.metodo` casi nunca aparece en una sola línea del código: se buscan
    // también los segmentos por separado.
    const expanded: string[] = [];
    for (const candidate of candidates) {
      expanded.push(candidate);
      for (const part of candidate.split('.')) {
        if (part.length >= 8 && part !== candidate) expanded.push(part);
      }
    }

    return [...new Set(expanded)].slice(0, 5);
  }
}
