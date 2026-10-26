import { Inject, Injectable, Logger } from '@nestjs/common';
import {
  GuardianDiagnosisStatus,
  GuardianDiagnosisVerdict,
  GuardianProcessingState,
  GuardianSeverity,
  Prisma,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { resolveGuardianConfig } from './guardian.config';
import {
  GUARDIAN_AI_PROVIDER,
  GuardianAiProvider,
  GuardianAiRequest,
  GuardianToolCallTrace,
} from './ai/guardian-ai.provider';
import { GuardianToolsService } from './guardian.tools.service';

const MAX_BACKOFF_MS = 30 * 60_000;

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

    const diagnosis = await this.prisma.guardianDiagnosis.create({
      data: {
        incidentId,
        status: GuardianDiagnosisStatus.RUNNING,
        attempts: incident.diagnosisAttempts,
        model: this.provider.name,
      },
    });

    const toolCalls: GuardianToolCallTrace[] = [];
    try {
      const request = await this.buildRequest(incident, toolCalls);
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
      const backoffMs = Math.min(MAX_BACKOFF_MS, 60_000 * Math.pow(2, Math.max(0, attempts - 1)));
      const message = error instanceof Error ? error.message : String(error);

      await this.prisma.$transaction([
        this.prisma.guardianDiagnosis.update({
          where: { id: diagnosis.id },
          data: {
            status: GuardianDiagnosisStatus.FAILED,
            error: message.slice(0, 600),
            toolCalls: toolCalls as unknown as Prisma.InputJsonValue,
          },
        }),
        this.prisma.guardianIncident.update({
          where: { id: incidentId },
          data: {
            processingState:
              attempts >= maxAttempts
                ? GuardianProcessingState.FAILED
                : GuardianProcessingState.PENDING,
            nextDiagnosisAt: new Date(Date.now() + backoffMs),
          },
        }),
      ]);

      this.logger.warn(`Diagnóstico reprogramado incident=${incidentId} attempts=${attempts} error=${message}`);
      return { ok: false as const, reason: 'PROVIDER_ERROR' };
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
        message: this.messageFromPayload(incident.payload),
        stack: incident.stack,
        impactSummary: incident.impactSummary,
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
      businessFacts,
      codeMatches: code.matches,
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
