/**
 * Validaciones del comprobante antes de conceder la activacion.
 *
 * Son **deterministas y comprobables**: tipo y tamano del archivo, orden
 * abierta, plan vigente, empresa activa, importe positivo y — cuando el motor
 * de analisis ya entrego la lectura del comprobante — que el importe leido
 * coincida con el de la orden.
 *
 * Si alguna comprobacion impide activar, la orden queda pendiente de revision
 * y **no** se concede activacion. El analisis por si solo nunca aprueba nada:
 * la aprobacion final es de soporte.
 */

export type EvidenceAnalysis = 'PENDING' | 'MATCH' | 'MISMATCH' | 'UNREADABLE';

export type EvidenceCheck = {
  code: string;
  ok: boolean;
  detail?: string;
};

export type EvidenceValidation = {
  passed: boolean;
  analysis: EvidenceAnalysis;
  checks: EvidenceCheck[];
  /** 0..1, para que soporte vea de un vistazo la confianza de la validacion. */
  score: number;
  validatedAt: string;
  /** Importe leido del comprobante, si el analisis ya llego. */
  extractedAmount: number | null;
};

export const EVIDENCE_MAX_BYTES = 8 * 1024 * 1024;
const ALLOWED_MIME = ['image/png', 'image/jpeg', 'image/webp', 'application/pdf'];
const AMOUNT_TOLERANCE = 0.01;

export type ValidationInput = {
  mime: string;
  sizeBytes: number;
  order: {
    amount: number;
    months: number;
    planActive: boolean;
  };
  companyActive: boolean;
  /** Datos que entrego el motor de analisis (APPYRA), si ya estan. */
  extracted?: { amount?: number | null } | null;
  /** Exige lectura del comprobante para activar (politica de negocio). */
  requireAnalysis?: boolean;
  maxBytes?: number;
  now?: Date;
};

export function evaluateEvidence(input: ValidationInput): EvidenceValidation {
  const checks: EvidenceCheck[] = [];
  const maxBytes = input.maxBytes ?? EVIDENCE_MAX_BYTES;

  checks.push({
    code: 'EVIDENCE_TYPE',
    ok: ALLOWED_MIME.includes(input.mime),
    detail: input.mime,
  });
  checks.push({
    code: 'EVIDENCE_NOT_EMPTY',
    ok: input.sizeBytes > 0,
  });
  checks.push({
    code: 'EVIDENCE_SIZE',
    ok: input.sizeBytes > 0 && input.sizeBytes <= maxBytes,
    detail: String(input.sizeBytes),
  });
  checks.push({
    code: 'ORDER_AMOUNT_POSITIVE',
    ok: Number.isFinite(input.order.amount) && input.order.amount > 0,
    detail: String(input.order.amount),
  });
  checks.push({
    code: 'ORDER_MONTHS',
    ok: Number.isInteger(input.order.months) && input.order.months >= 1,
  });
  checks.push({ code: 'PLAN_ACTIVE', ok: input.order.planActive });
  checks.push({ code: 'COMPANY_ACTIVE', ok: input.companyActive });

  const extractedAmount =
    input.extracted?.amount != null && Number.isFinite(input.extracted.amount)
      ? round2(input.extracted.amount)
      : null;

  let analysis: EvidenceAnalysis = 'PENDING';
  if (extractedAmount != null) {
    const expected = round2(input.order.amount);
    const diff = Math.abs(extractedAmount - expected);
    const tolerance = Math.max(1, expected * AMOUNT_TOLERANCE);
    const matches = diff <= tolerance;
    analysis = matches ? 'MATCH' : 'MISMATCH';
    checks.push({
      code: 'EXTRACTED_AMOUNT_MATCHES',
      ok: matches,
      detail: `${extractedAmount} vs ${expected}`,
    });
  } else if (input.requireAnalysis) {
    // Sin lectura no se puede verificar el comprobante: no se activa.
    checks.push({
      code: 'ANALYSIS_AVAILABLE',
      ok: false,
      detail: 'sin lectura del comprobante',
    });
  }

  const passed =
    checks.every((check) => check.ok) && analysis !== 'MISMATCH';
  const okCount = checks.filter((check) => check.ok).length;

  return {
    passed,
    analysis,
    checks,
    score: checks.length === 0 ? 0 : round2(okCount / checks.length),
    validatedAt: (input.now ?? new Date()).toISOString(),
    extractedAmount,
  };
}

/**
 * ¿Se puede volver a subir comprobante a esta orden? Una orden rechazada,
 * revertida o ya resuelta **nunca** se reabre: si el cliente quiere pagar
 * otra vez, se crea una orden nueva (y el comprobante repetido se rechaza por
 * huella).
 */
export function canAcceptEvidence(status: string, activationState: string) {
  const open = ['CREATED', 'AWAITING_TRANSFER'];
  if (!open.includes(status)) {
    return {
      ok: false,
      code:
        status === 'REJECTED'
          ? ('ORDER_REJECTED' as const)
          : ('ORDER_NOT_PAYABLE' as const),
    };
  }
  // Una activacion ya revertida no se reutiliza aunque la orden siguiera
  // abierta: evita pedir una segunda activacion con el mismo comprobante.
  if (activationState === 'REVERTED') {
    return { ok: false, code: 'ORDER_ALREADY_REVIEWED' as const };
  }
  return { ok: true, code: null };
}

function round2(value: number) {
  return Math.round(value * 100) / 100;
}
