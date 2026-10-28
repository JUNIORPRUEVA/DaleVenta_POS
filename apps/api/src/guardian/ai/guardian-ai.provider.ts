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
  | 'AI_OUTPUT_TRUNCATED'
  | 'AI_SCHEMA_INVALID'
  | 'AI_TIMEOUT'
  | 'AI_RATE_LIMITED'
  | 'AI_PROVIDER_ERROR'
  | 'AI_NOT_CONFIGURED';

/**
 * Metadatos SEGUROS de la respuesta del proveedor.
 *
 * Solo contiene datos estructurales: nunca el contenido devuelto por la IA ni
 * la credencial. `contentSha256` es un hash truncado que permite correlacionar
 * dos fallos idénticos sin exponer el texto original.
 */
export type GuardianAiResponseDiagnostic = {
  finishReason: string | null;
  contentLength: number;
  contentSha256: string | null;
  startsWithJson: boolean;
  jsonBalanced: boolean;
  fenced: boolean;
  missingFields: string[];
  invalidFields: string[];
  maxTokens: number | null;
};

/**
 * Códigos que NO se reintentan automáticamente.
 *
 * Motivo: son fallos deterministas del resultado (respuesta vacía, JSON
 * truncado o fuera de esquema) o de configuración. Volver a llamar al proveedor
 * gastaría tokens con la misma entrada y el mismo resultado, así que el
 * incidente queda en estado terminal y se reporta en lugar de reintentarse.
 * Los fallos transitorios (429, 5xx, timeout) conservan su backoff.
 */
export const GUARDIAN_AI_NON_RETRYABLE_CODES: readonly GuardianAiErrorCode[] = [
  'AI_NOT_CONFIGURED',
  'AI_INVALID_RESPONSE',
  'AI_OUTPUT_TRUNCATED',
  'AI_SCHEMA_INVALID',
];

/**
 * Error tipado del proveedor. Permite que el worker distinga un fallo
 * transitorio (429/5xx/timeout) de una respuesta inválida y aplique backoff
 * con la espera que indique el proveedor.
 */
export class GuardianAiError extends Error {
  readonly code: GuardianAiErrorCode;
  readonly httpStatus?: number;
  readonly retryAfterMs?: number;
  /** `false` cuando reintentar la misma petición solo repetiría el fallo. */
  readonly retryable: boolean;
  /** Metadatos seguros de la respuesta (sin contenido crudo). */
  readonly diagnostic?: GuardianAiResponseDiagnostic;

  constructor(
    code: GuardianAiErrorCode,
    message: string,
    options: {
      httpStatus?: number;
      retryAfterMs?: number;
      retryable?: boolean;
      diagnostic?: GuardianAiResponseDiagnostic;
    } = {},
  ) {
    super(message);
    this.name = 'GuardianAiError';
    this.code = code;
    this.httpStatus = options.httpStatus;
    this.retryAfterMs = options.retryAfterMs;
    this.retryable =
      options.retryable ?? !GUARDIAN_AI_NON_RETRYABLE_CODES.includes(code);
    this.diagnostic = options.diagnostic;
  }

  /**
   * Resumen compacto y seguro, apto para `guardian_diagnoses.error`.
   * Nunca incluye el texto devuelto por el proveedor.
   */
  get diagnosticSummary(): string {
    const data = this.diagnostic;
    if (!data) return '';
    const parts = [
      `finish=${data.finishReason ?? 'n/a'}`,
      `chars=${data.contentLength}`,
      `sha=${data.contentSha256 ?? 'n/a'}`,
      `json=${data.startsWithJson ? 'si' : 'no'}`,
      `balanced=${data.jsonBalanced ? 'si' : 'no'}`,
      `fenced=${data.fenced ? 'si' : 'no'}`,
      `max_tokens=${data.maxTokens ?? 'n/a'}`,
      `faltan=${data.missingFields.length ? data.missingFields.join('|') : '-'}`,
      `invalidos=${data.invalidFields.length ? data.invalidFields.join('|') : '-'}`,
    ];
    return `[meta ${parts.join(' ')}]`;
  }
}

export const GUARDIAN_AI_PROVIDER = Symbol('GUARDIAN_AI_PROVIDER');
