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

export type GuardianAiErrorCode =
  | 'AI_INVALID_RESPONSE'
  | 'AI_TIMEOUT'
  | 'AI_RATE_LIMITED'
  | 'AI_PROVIDER_ERROR'
  | 'AI_NOT_CONFIGURED';

/**
 * Error tipado del proveedor. Permite que el worker distinga un fallo
 * transitorio (429/5xx/timeout) de una respuesta inválida y aplique backoff
 * con la espera que indique el proveedor.
 */
export class GuardianAiError extends Error {
  readonly code: GuardianAiErrorCode;
  readonly httpStatus?: number;
  readonly retryAfterMs?: number;

  constructor(
    code: GuardianAiErrorCode,
    message: string,
    options: { httpStatus?: number; retryAfterMs?: number } = {},
  ) {
    super(message);
    this.name = 'GuardianAiError';
    this.code = code;
    this.httpStatus = options.httpStatus;
    this.retryAfterMs = options.retryAfterMs;
  }
}

export const GUARDIAN_AI_PROVIDER = Symbol('GUARDIAN_AI_PROVIDER');
