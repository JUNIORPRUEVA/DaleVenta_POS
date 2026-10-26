import { GuardianDiagnosisVerdict } from '@prisma/client';

export type GuardianEvidenceRef = {
  type: 'incident' | 'similar_incident' | 'sql' | 'code' | 'log' | 'version' | 'company';
  ref: string;
  note?: string;
};

export type GuardianToolCallTrace = {
  tool: string;
  status: 'ok' | 'error' | 'skipped';
  detail?: string;
  ms?: number;
};

export type GuardianAiRequest = {
  incident: {
    id: string;
    module: string;
    operation: string;
    severity: string;
    exceptionType: string | null;
    platform: string | null;
    appVersion: string | null;
    occurredAt: string;
    message: string | null;
    stack: string | null;
    impactSummary: string | null;
  };
  similarIncidents: Array<{ id: string; companyId: string; occurredAt: string; appVersion: string | null }>;
  company: { id: string; plan: string; licenseStatus: string; createdAt: string } | null;
  businessFacts: Record<string, unknown>;
  codeMatches: Array<{ file: string; line: number; snippet: string }>;
  versionTimeline: Array<{ version: string; platform: string; publishedAt: string | null }>;
};

export type GuardianAiResult = {
  verdict: GuardianDiagnosisVerdict;
  confidence: number;
  summary: string;
  impact: string | null;
  causeCategory: string | null;
  explanation: string;
  nextSteps: string[];
  evidenceRefs: GuardianEvidenceRef[];
  toolCalls: GuardianToolCallTrace[];
  model: string;
  tokensUsed: number;
  durationMs: number;
};

/**
 * Contrato del proveedor de IA.
 *
 * El proveedor NUNCA recibe permisos ni ejecuta acciones: recibe contexto ya
 * consultado por herramientas de solo lectura y devuelve una hipótesis.
 */
export interface GuardianAiProvider {
  readonly name: string;
  isConfigured(): boolean;
  analyze(request: GuardianAiRequest): Promise<GuardianAiResult>;
}

export const GUARDIAN_AI_PROVIDER = Symbol('GUARDIAN_AI_PROVIDER');
