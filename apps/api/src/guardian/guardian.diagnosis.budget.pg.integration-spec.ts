/**
 * FASE A3 — presupuesto de IA por empresa y trazabilidad del prompt (PostgreSQL).
 */
import { PrismaClient } from '@prisma/client';
import { GuardianDiagnosisService } from './guardian.diagnosis.service';
import { GuardianIngestService } from './guardian.ingest.service';
import { GuardianQuotaService } from './guardian.quota.service';
import { GuardianToolsService } from './guardian.tools.service';
import { GuardianAiProvider, GuardianAiRequest, GuardianAiResult } from './ai/guardian-ai.provider';
import { GuardianIngestEventDto } from './dto/guardian-ingest.dto';

const UAT_DATABASE_URL = process.env.GUARDIAN_UAT_DATABASE_URL ?? '';
const describeOnPg = UAT_DATABASE_URL ? describe : describe.skip;
const RUN_ID = `bg${Date.now().toString(36)}`;

function stubProvider(result?: GuardianAiResult): GuardianAiProvider & { analyze: jest.Mock } {
  return {
    name: 'stub',
    isConfigured: () => true,
    analyze: jest.fn(async (request: GuardianAiRequest) => ({
      verdict: 'CONFIRMED',
      confidence: 0.9,
      summary: 'causa verificada en el incidente',
      impact: 'caja',
      causeCategory: 'pattern_recurrence',
      explanation: 'explicación',
      nextSteps: ['revisar'],
      evidenceRefs: [{ type: 'incident', ref: request.incident.id }],
      toolCalls: [],
      model: 'stub',
      tokensUsed: 10,
      durationMs: 1,
      ...result,
    })),
  } as unknown as GuardianAiProvider & { analyze: jest.Mock };
}

function event(overrides: Partial<GuardianIngestEventDto> = {}): GuardianIngestEventDto {
  return {
    eventId: `evt-${Math.random().toString(36).slice(2, 12)}-${Date.now().toString(36)}`,
    severity: 'SEV2',
    module: 'unknown',
    operation: 'unknownOperation',
    platform: 'windows',
    deviceId: `dev-${RUN_ID}`,
    occurredAt: new Date().toISOString(),
    message: 'evento sintético',
    ...overrides,
  } as GuardianIngestEventDto;
}

describeOnPg('Guardian presupuesto de IA por empresa', () => {
  let prisma: PrismaClient;
  let ingest: GuardianIngestService;
  let company: { id: string };

  beforeAll(async () => {
    process.env.GUARDIAN_ENABLED = 'true';
    process.env.GUARDIAN_DIAGNOSIS_ENABLED = 'true';

    prisma = new PrismaClient({ datasources: { db: { url: UAT_DATABASE_URL } } });
    await prisma.$connect();
    ingest = new GuardianIngestService(prisma as any, new GuardianQuotaService(prisma as any));

    company = await prisma.company.create({
      data: { name: `Guardian Budget ${RUN_ID}`, slug: `guardian-budget-${RUN_ID}` },
      select: { id: true },
    });
  }, 60_000);

  afterAll(async () => {
    await prisma?.company.deleteMany({ where: { slug: { startsWith: 'guardian-budget-' } } });
    await prisma?.$disconnect();
    delete process.env.GUARDIAN_DIAGNOSIS_ENABLED;
    delete process.env.GUARDIAN_AI_TOKENS_PER_COMPANY_DAY;
  });

  it('omite la llamada a la IA cuando la empresa agotó su presupuesto diario', async () => {
    process.env.GUARDIAN_AI_TOKENS_PER_COMPANY_DAY = '100';

    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;

    // Consumo previo de la misma empresa dentro de la ventana de 24 h.
    await prisma.guardianDiagnosis.create({
      data: { incidentId, status: 'DONE', verdict: 'PROBABLE', model: 'stub', tokensUsed: 150 },
    });

    const provider = stubProvider();
    const service = new GuardianDiagnosisService(prisma as any, new GuardianToolsService(prisma as any), provider);

    const result = await service.diagnose(incidentId);
    expect(result).toMatchObject({ ok: true, skipped: 'AI_BUDGET_EXCEEDED' });
    expect(provider.analyze).not.toHaveBeenCalled();

    const incident = await prisma.guardianIncident.findUniqueOrThrow({ where: { id: incidentId } });
    expect(incident.processingState).toBe('SKIPPED');

    const budgetRow = await prisma.guardianDiagnosis.findFirst({
      where: { incidentId, model: 'budget-guard' },
      orderBy: { createdAt: 'desc' },
    });
    expect(budgetRow?.verdict).toBe('INSUFFICIENT');
  }, 60_000);

  it('con presupuesto disponible diagnostica y guarda el hash del prompt', async () => {
    process.env.GUARDIAN_AI_TOKENS_PER_COMPANY_DAY = '0';

    const outcome = await ingest.ingestBatch({ companyId: company.id, events: [event()] });
    const incidentId = outcome.results[0].incidentId!;

    const provider = stubProvider();
    const service = new GuardianDiagnosisService(prisma as any, new GuardianToolsService(prisma as any), provider);

    const result = await service.diagnose(incidentId);
    expect(result.ok).toBe(true);
    expect(provider.analyze).toHaveBeenCalledTimes(1);

    const incident = await prisma.guardianIncident.findUniqueOrThrow({ where: { id: incidentId } });
    expect(incident.processingState).toBe('DIAGNOSED');

    const diagnosis = await prisma.guardianDiagnosis.findFirst({
      where: { incidentId, status: 'DONE' },
      orderBy: { createdAt: 'desc' },
    });
    expect(diagnosis?.promptHash).toBeTruthy();
    expect(diagnosis?.verdict).toBe('CONFIRMED');
  }, 60_000);
});
