/**
 * FASE 8 — Presupuesto GLOBAL de IA y reserva concurrente segura.
 *
 * Estrategia: tope diario global = exactamente el tamaño de una reserva
 * (`max_tokens`), así solo UN diagnóstico puede entrar aunque se lancen varios
 * en paralelo. El resto debe saltarse SIN llamar al proveedor.
 */
import { PrismaClient } from '@prisma/client';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianToolsService } from './guardian.tools.service';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';
import { GuardianAiProvider, GuardianAiRequest, GuardianAiResult } from './ai/guardian-ai.provider';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';

const DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = DATABASE_URL ? describe : describe.skip;
const RUN_ID = `gbudget${Date.now().toString(36)}`;

function event(): GuardianIngestEventDto {
  return {
    eventId: `evt-${Math.random().toString(36).slice(2, 12)}-${Date.now().toString(36)}`,
    severity: 'SEV2',
    module: 'cash',
    operation: 'closeSession',
    exceptionType: 'TimeoutError',
    platform: 'windows',
    appVersion: '1.0.6+149',
    deviceId: `dev-${RUN_ID}`,
    occurredAt: new Date().toISOString(),
    message: 'timeout',
    stack: 'Error: timeout\n    at CashService.close (cash.service.ts:10:1)',
  } as GuardianIngestEventDto;
}

describeOnPg('Guardian presupuesto GLOBAL de IA sobre PostgreSQL real', () => {
  let prisma: PrismaClient;
  let ingest: GuardianIngestService;
  let company: { id: string };

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_INGEST_ENABLED = 'true';
    process.env.GUARDIAN_DIAGNOSIS_ENABLED = 'true';
    prisma = new PrismaClient({ datasources: { db: { url: DATABASE_URL } } });
    await prisma.$connect();
    ingest = new GuardianIngestService(prisma as any, new GuardianQuotaService(prisma as any));
    company = await prisma.company.create({
      data: {
        name: `Guardian Global Budget ${RUN_ID}`,
        slug: `guardian-gbudget-${RUN_ID}`,
        guardianEnabled: true,
      },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { contains: RUN_ID } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_AI_TOKENS_GLOBAL_DAY;
    delete process.env.GUARDIAN_AI_MAX_TOKENS;
  });

  it('con el tope global agotado no se llama al proveedor', async () => {
    process.env.GUARDIAN_AI_MAX_TOKENS = '1600';
    process.env.GUARDIAN_AI_TOKENS_GLOBAL_DAY = '100'; // menor que una reserva

    const analyze = jest.fn(async (): Promise<GuardianAiResult> => {
      throw new Error('no debería llamarse');
    });
    const provider: GuardianAiProvider = { name: 'stub', isConfigured: () => true, analyze };
    const service = new GuardianDiagnosisService(prisma as any, new GuardianToolsService(prisma as any), provider);

    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;

    const result = await service.diagnose(incidentId);
    expect(result).toMatchObject({ ok: true, skipped: 'AI_GLOBAL_BUDGET_EXCEEDED' });
    expect(analyze).not.toHaveBeenCalled();

    const incident = await prisma.guardianIncident.findUniqueOrThrow({ where: { id: incidentId } });
    expect(incident.processingState).toBe('SKIPPED');
    const guard = await prisma.guardianDiagnosis.findFirst({
      where: { incidentId, model: 'global-budget-guard' },
    });
    expect(guard).toBeTruthy();
  }, 60_000);

  it('reserva concurrente: solo un diagnóstico entra con tope de una reserva', async () => {
    process.env.GUARDIAN_AI_MAX_TOKENS = '1600';
    process.env.GUARDIAN_AI_TOKENS_GLOBAL_DAY = '1600'; // cabe exactamente uno

    // Consumo previo que deja el margen justo para una reserva.
    const seed = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const seedId = seed.results[0].incidentId!;
    await prisma.guardianDiagnosis.create({
      data: { incidentId: seedId, status: 'DONE', verdict: 'PROBABLE', model: 'seed', tokensUsed: 0 },
    });

    const analyze = jest.fn(
      async (_request: GuardianAiRequest): Promise<GuardianAiResult> => ({
        verdict: 'PROBABLE' as any,
        confidence: 0.5,
        summary: 'resumen de prueba',
        impact: null,
        causeCategory: null,
        explanation: 'explicación de prueba',
        nextSteps: [],
        evidenceRefs: [{ type: 'incident', ref: seedId }],
        toolCalls: [],
        model: 'stub',
        tokensUsed: 1600,
        durationMs: 1,
      }),
    );
    const provider: GuardianAiProvider = { name: 'stub', isConfigured: () => true, analyze };
    const service = new GuardianDiagnosisService(prisma as any, new GuardianToolsService(prisma as any), provider);

    const batch = await ingest.ingestBatch({
      companyId: company.id,
      events: [event(), event(), event()],
    });
    const ids = batch.results.map((row) => row.incidentId!).filter(Boolean);

    const outcomes = await Promise.all(ids.map((id) => service.diagnose(id)));
    const processed = outcomes.filter((row) => row.ok && !('skipped' in row));
    const skipped = outcomes.filter((row) => 'skipped' in row);

    // Con 1600 de tope y 1600 por reserva: exactamente una llamada al proveedor.
    expect(analyze).toHaveBeenCalledTimes(1);
    expect(processed).toHaveLength(1);
    expect(skipped.length).toBe(ids.length - 1);
  }, 120_000);

  it('sin tope configurado (0) el presupuesto global no bloquea', async () => {
    process.env.GUARDIAN_AI_MAX_TOKENS = '1600';
    process.env.GUARDIAN_AI_TOKENS_GLOBAL_DAY = '0';

    const analyze = jest.fn(
      async (_request: GuardianAiRequest): Promise<GuardianAiResult> => ({
        verdict: 'INSUFFICIENT' as any,
        confidence: 0.1,
        summary: 'sin evidencia suficiente',
        impact: null,
        causeCategory: null,
        explanation: 'no hay evidencia',
        nextSteps: [],
        evidenceRefs: [{ type: 'incident', ref: 'x' }],
        toolCalls: [],
        model: 'stub',
        tokensUsed: 10,
        durationMs: 1,
      }),
    );
    const provider: GuardianAiProvider = { name: 'stub', isConfigured: () => true, analyze };
    const service = new GuardianDiagnosisService(prisma as any, new GuardianToolsService(prisma as any), provider);

    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;

    const result = await service.diagnose(incidentId);
    expect(result.ok).toBe(true);
    expect(analyze).toHaveBeenCalledTimes(1);
  }, 60_000);
});
