/**
 * FASE 3 — Diagnóstico automático contra PostgreSQL REAL.
 *
 *   $env:GUARDIAN_UAT_DATABASE_URL = 'postgresql://postgres@127.0.0.1:55661/daleventa_pos_uat'
 */
import { PrismaClient } from '@prisma/client';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianToolsService } from './guardian.tools.service';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';
import { GuardianAiProvider, GuardianAiRequest, GuardianAiResult, GuardianAiError } from './ai/guardian-ai.provider';
import { MockGuardianAiProvider } from './ai/mock-guardian-ai.provider';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `dx${Date.now().toString(36)}`;

const STACK_WITH_SYMBOL =
  'Error: unexpected\n    at GuardianIngestService.ingestBatch (guardian.ingest.service.ts:120:9)';

function event(overrides: Partial<GuardianIngestEventDto> = {}): GuardianIngestEventDto {
  return {
    eventId: `evt-${Math.random().toString(36).slice(2, 12)}-${Date.now().toString(36)}`,
    severity: 'SEV2',
    module: 'cash',
    operation: 'closeSession',
    exceptionType: 'TimeoutError',
    platform: 'windows',
    appVersion: '1.4.5',
    deviceId: `dev-${RUN_ID}`,
    occurredAt: new Date().toISOString(),
    message: 'timeout',
    stack: STACK_WITH_SYMBOL,
    ...overrides,
  } as GuardianIngestEventDto;
}

describeOnPg('Guardian diagnóstico sobre PostgreSQL real', () => {
  let prisma: PrismaClient;
  let ingest: GuardianIngestService;
  let tools: GuardianToolsService;
  let diagnosis: GuardianDiagnosisService;
  let company: { id: string };

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_INGEST_ENABLED = 'true';
    process.env.GUARDIAN_DIAGNOSIS_ENABLED = 'true';
    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    ingest = new GuardianIngestService(prisma as any, new GuardianQuotaService(prisma as any));
    tools = new GuardianToolsService(prisma as any);
    diagnosis = new GuardianDiagnosisService(prisma as any, tools, new MockGuardianAiProvider());

    company = await prisma.company.create({
      data: { name: `Guardian Diag ${RUN_ID}`, slug: `guardian-diag-${RUN_ID}` },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-diag-' } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_DIAGNOSIS_ENABLED;
  });

  it('nunca afirma una causa sin evidencia verificable', () => {
    const result = (diagnosis as any).enforceVerdictRules({
      verdict: 'CONFIRMED',
      confidence: 0.99,
      summary: 'causa segura',
      impact: null,
      causeCategory: 'x',
      explanation: 'x',
      nextSteps: [],
      evidenceRefs: [],
    });

    expect(result.verdict).toBe('INSUFFICIENT');
    expect(result.confidence).toBeLessThanOrEqual(0.2);
    expect(result.causeCategory).toBeNull();
  });

  it('con poca evidencia concluye INSUFFICIENT y persiste el diagnóstico', async () => {
    // Firma única y símbolo inexistente: garantiza cero incidentes similares y
    // cero coincidencias en código, para probar el estado INSUFFICIENT real.
    const outcome = await ingest.ingestBatch({
      companyId: company.id,
      events: [
        event({
          operation: `operacionAislada-${RUN_ID}`,
          exceptionType: `ExcepcionInexistente${RUN_ID}`,
          stack: 'Error: raro\n    at SimboloQueNoExisteXYZ.build (widget.dart:10:1)',
        }),
      ],
    });
    const incidentId = outcome.results[0].incidentId!;

    const result = await diagnosis.diagnose(incidentId);
    expect(result.ok).toBe(true);

    const stored = await prisma.guardianIncident.findUniqueOrThrow({
      where: { id: incidentId },
      include: { diagnoses: true },
    });

    expect(stored.processingState).toBe('DIAGNOSED');
    const latest = stored.diagnoses.at(-1)!;
    expect(latest.status).toBe('DONE');
    expect(latest.verdict).toBe('INSUFFICIENT');
    expect(Array.isArray(latest.evidenceRefs)).toBe(true);
    expect((latest.evidenceRefs as unknown[]).length).toBeGreaterThan(0);
    expect(latest.toolCalls).toBeTruthy();
  }, 60_000);

  it('con patrón repetido y coincidencia en código concluye CONFIRMED', async () => {
    const base = {
      module: 'cash' as const,
      operation: 'closeSessionConfirmed',
      exceptionType: 'RefundError',
      appVersion: '1.4.5',
      stack: STACK_WITH_SYMBOL,
    };

    const first = await ingest.ingestBatch({ companyId: company.id, events: [event(base)] });
    await ingest.ingestBatch({ companyId: company.id, events: [event(base)] });
    await ingest.ingestBatch({ companyId: company.id, events: [event(base)] });

    const targetId = first.results[0].incidentId!;
    const result = await diagnosis.diagnose(targetId);
    expect(result.ok).toBe(true);

    const latest = await prisma.guardianDiagnosis.findFirstOrThrow({
      where: { incidentId: targetId, status: 'DONE' },
      orderBy: { createdAt: 'desc' },
    });

    expect(latest.verdict).toBe('CONFIRMED');
    const refs = latest.evidenceRefs as Array<{ type: string }>;
    expect(refs.some((ref) => ref.type === 'similar_incident')).toBe(true);
    expect(refs.some((ref) => ref.type === 'code')).toBe(true);
  }, 90_000);

  it('si el proveedor IA falla, el incidente se reprograma sin perderse', async () => {
    const failingProvider: GuardianAiProvider = {
      name: 'failing',
      isConfigured: () => true,
      analyze: async (_request: GuardianAiRequest): Promise<GuardianAiResult> => {
        const error: any = new Error('IA no disponible');
        error.status = 503;
        throw error;
      },
    };
    const failingDiagnosis = new GuardianDiagnosisService(prisma as any, tools, failingProvider);

    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;

    const result = await failingDiagnosis.diagnose(incidentId);
    expect(result.ok).toBe(false);

    const stored = await prisma.guardianIncident.findUniqueOrThrow({ where: { id: incidentId } });
    expect(stored.processingState).toBe('PENDING');
    expect(stored.nextDiagnosisAt.getTime()).toBeGreaterThan(Date.now() - 1_000);

    const failedDiagnosis = await prisma.guardianDiagnosis.findFirst({
      where: { incidentId, status: 'FAILED' },
    });
    expect(failedDiagnosis).toBeTruthy();
    expect(failedDiagnosis!.error).toContain('IA no disponible');
  }, 60_000);

  it('Fase 5A: un fallo no reintentable no se reprograma ni se vuelve a facturar', async () => {
    // Simula lo observado en UAT: HTTP 2xx con salida no utilizable.
    const analyze = jest.fn(async (_request: GuardianAiRequest): Promise<GuardianAiResult> => {
      throw new GuardianAiError('AI_OUTPUT_TRUNCATED', 'el proveedor cortó la respuesta', {
        diagnostic: {
          finishReason: 'length',
          contentLength: 812,
          contentSha256: 'abcdef0123456789',
          startsWithJson: true,
          jsonBalanced: false,
          fenced: false,
          missingFields: [],
          invalidFields: [],
          maxTokens: 1600,
        },
      });
    });
    const truncatedProvider: GuardianAiProvider = {
      name: 'deepseek',
      isConfigured: () => true,
      analyze,
    };
    const truncatedDiagnosis = new GuardianDiagnosisService(prisma as any, tools, truncatedProvider);

    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;

    const result = await truncatedDiagnosis.diagnose(incidentId);
    expect(result).toMatchObject({
      ok: false,
      reason: 'PROVIDER_OUTPUT_INVALID',
      retryable: false,
      errorCode: 'AI_OUTPUT_TRUNCATED',
    });
    // Exactamente una llamada al proveedor: sin reintento automático.
    expect(analyze).toHaveBeenCalledTimes(1);

    const stored = await prisma.guardianIncident.findUniqueOrThrow({ where: { id: incidentId } });
    expect(stored.processingState).toBe('FAILED');
    // Fuera de la cola: no puede volver a llamarse a la IA en horas.
    expect(stored.nextDiagnosisAt.getTime()).toBeGreaterThan(Date.now() + 60 * 60 * 1000);

    const failedDiagnosis = await prisma.guardianDiagnosis.findFirst({
      where: { incidentId, status: 'FAILED' },
    });
    expect(failedDiagnosis).toBeTruthy();
    expect(failedDiagnosis!.error).toContain('cortó la respuesta');
    // Metadatos seguros persistidos, sin contenido crudo del proveedor.
    expect(failedDiagnosis!.error).toContain('[meta finish=length');
    expect(failedDiagnosis!.error).toContain('sha=abcdef0123456789');
    const traced = failedDiagnosis!.toolCalls as Array<{ tool: string }>;
    expect(traced.some((entry) => entry.tool === 'ai_response')).toBe(true);
  }, 60_000);

  it('rechaza consultas SQL fuera de la lista permitida', async () => {
    await expect(tools.runPredefinedQuery('DROP TABLE users', [])).rejects.toThrow(/no permitida/i);
    const rows = await tools.runPredefinedQuery('cash_activity_24h', [company.id]);
    expect(Array.isArray(rows)).toBe(true);
  }, 30_000);

  it('busca símbolos solo en el código autorizado', () => {
    const result = tools.searchCode(['GuardianIngestService']);
    expect(result.matches.length).toBeGreaterThan(0);
    expect(result.matches.every((match) => !match.file.includes('node_modules'))).toBe(true);
  }, 30_000);

  it('dos workers no diagnostican el mismo incidente a la vez', async () => {
    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;

    const [claimA, claimB] = await Promise.all([
      diagnosis.claimDueIncidents(10),
      diagnosis.claimDueIncidents(10),
    ]);
    const idsA = claimA.map((row) => row.id);
    const idsB = claimB.map((row) => row.id);

    expect(incidentId).toBeTruthy();
    expect(idsA.filter((id) => idsB.includes(id))).toEqual([]);
  }, 60_000);
});
