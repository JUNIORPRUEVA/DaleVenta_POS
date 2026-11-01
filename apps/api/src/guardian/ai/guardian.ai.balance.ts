/**
 * Saldo y estado de facturación del proveedor de IA (DeepSeek).
 *
 * Fuente de verdad: el endpoint oficial `GET https://api.deepseek.com/user/balance`
 * (documentación oficial `https://api-docs.deepseek.com/api/get-user-balance`,
 * consultada el 2026-10-30). Respuesta:
 *
 * ```json
 * { "is_available": true,
 *   "balance_infos": [ { "currency": "USD", "total_balance": "110.00",
 *                        "granted_balance": "10.00", "topped_up_balance": "100.00" } ] }
 * ```
 *
 * Reglas:
 * - **Nunca se inventa un saldo.** Si el proveedor no responde, responde un
 *   error o el adaptador activo no es DeepSeek, el estado es `UNAVAILABLE` o
 *   `NOT_CONFIGURED` y `totalBalance` queda en `null`.
 * - El importe se conserva **tal como lo devuelve el proveedor** (cadena). Solo
 *   se convierte a número para comparar con el umbral, sin redondear el valor
 *   publicado.
 * - La llamada al endpoint de saldo **no consume tokens** ni genera coste.
 */

export type GuardianAiBalanceState =
  | 'OK'
  | 'LOW'
  | 'EXHAUSTED'
  | 'BILLING_ERROR'
  | 'UNAVAILABLE'
  | 'NOT_CONFIGURED';

export type GuardianAiBalanceSnapshot = {
  state: GuardianAiBalanceState;
  /** Proveedor efectivo del que se consultó el saldo. */
  provider: 'deepseek' | 'none';
  /** Endpoint consultado (para auditoría; no contiene credenciales). */
  endpoint: string | null;
  checkedAt: string;
  httpStatus: number | null;
  /** Valor literal devuelto por el proveedor, sin reformatear. */
  currency: string | null;
  totalBalance: string | null;
  grantedBalance: string | null;
  toppedUpBalance: string | null;
  isAvailable: boolean | null;
  /** Umbral configurado (en la misma moneda informada) para considerar `LOW`. */
  lowThreshold: number | null;
  error: string | null;
};

/** Deriva el endpoint oficial de saldo a partir de la base URL del chat. */
export function resolveDeepSeekBalanceEndpoint(baseUrl: string | null | undefined): string | null {
  const raw = String(baseUrl ?? '').trim();
  if (!raw) return null;
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (!/^https?:$/.test(url.protocol)) return null;
  // Solo el host oficial de DeepSeek: una base URL de otro proveedor no expone
  // este endpoint y no debe consultarse (jamás se envía la clave a otro host).
  if (!/(^|\.)deepseek\.com$/i.test(url.hostname)) return null;
  return `${url.protocol}//${url.host}/user/balance`;
}

function toAmount(raw: unknown): number | null {
  const value = typeof raw === 'number' ? raw : Number.parseFloat(String(raw ?? ''));
  if (!Number.isFinite(value)) return null;
  return value;
}

/** Elige el saldo en USD si existe; si no, el primero informado. */
function pickBalanceInfo(balanceInfos: unknown): {
  currency: string | null;
  totalBalance: string | null;
  grantedBalance: string | null;
  toppedUpBalance: string | null;
} {
  const list = Array.isArray(balanceInfos) ? balanceInfos : [];
  const entries = list.filter((entry): entry is Record<string, unknown> => !!entry && typeof entry === 'object');
  if (entries.length === 0) {
    return { currency: null, totalBalance: null, grantedBalance: null, toppedUpBalance: null };
  }
  const usd = entries.find((entry) => String(entry.currency ?? '').toUpperCase() === 'USD');
  const chosen = usd ?? entries[0];
  const asText = (value: unknown): string | null => {
    if (value === null || value === undefined) return null;
    const text = String(value).trim();
    return text.length > 0 ? text : null;
  };
  return {
    currency: asText(chosen.currency),
    totalBalance: asText(chosen.total_balance),
    grantedBalance: asText(chosen.granted_balance),
    toppedUpBalance: asText(chosen.topped_up_balance),
  };
}

/**
 * Consulta el saldo real. Nunca lanza: cualquier fallo se traduce en un estado
 * explícito sin cifras inventadas.
 */
export async function probeDeepSeekBalance(params: {
  apiKey: string;
  baseUrl: string | null | undefined;
  lowThreshold: number;
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  now?: Date;
}): Promise<GuardianAiBalanceSnapshot> {
  const now = params.now ?? new Date();
  const checkedAt = now.toISOString();
  const endpoint = resolveDeepSeekBalanceEndpoint(params.baseUrl);
  const apiKey = String(params.apiKey ?? '').trim();

  const base: GuardianAiBalanceSnapshot = {
    state: 'NOT_CONFIGURED',
    provider: 'none',
    endpoint,
    checkedAt,
    httpStatus: null,
    currency: null,
    totalBalance: null,
    grantedBalance: null,
    toppedUpBalance: null,
    isAvailable: null,
    lowThreshold: Number.isFinite(params.lowThreshold) ? params.lowThreshold : null,
    error: null,
  };

  if (!apiKey) {
    return { ...base, error: 'GUARDIAN_AI_API_KEY no configurada' };
  }
  if (!endpoint) {
    return {
      ...base,
      error: 'El proveedor de IA activo no expone el endpoint oficial de saldo',
    };
  }

  const fetchImpl = params.fetchImpl ?? fetch;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), params.timeoutMs ?? 10_000);
  let status: number | null = null;
  try {
    const response = await fetchImpl(endpoint, {
      method: 'GET',
      headers: { accept: 'application/json', authorization: `Bearer ${apiKey}` },
      signal: controller.signal,
    });
    status = response.status;
    const text = await response.text();

    if (status === 401 || status === 402 || status === 403) {
      return {
        ...base,
        provider: 'deepseek',
        state: 'BILLING_ERROR',
        httpStatus: status,
        error: `El proveedor rechazó la consulta de saldo (HTTP ${status})`,
      };
    }
    if (status < 200 || status >= 300) {
      return {
        ...base,
        provider: 'deepseek',
        state: 'UNAVAILABLE',
        httpStatus: status,
        error: `Respuesta inesperada del proveedor (HTTP ${status})`,
      };
    }

    let body: unknown;
    try {
      body = JSON.parse(text);
    } catch {
      return {
        ...base,
        provider: 'deepseek',
        state: 'UNAVAILABLE',
        httpStatus: status,
        error: 'Respuesta de saldo no interpretable',
      };
    }

    const record = (body && typeof body === 'object' ? body : {}) as Record<string, unknown>;
    const info = pickBalanceInfo(record.balance_infos);
    const isAvailable = typeof record.is_available === 'boolean' ? record.is_available : null;
    const amount = toAmount(info.totalBalance);

    if (!info.totalBalance && isAvailable === null) {
      return {
        ...base,
        provider: 'deepseek',
        state: 'UNAVAILABLE',
        httpStatus: status,
        error: 'La respuesta de saldo no contiene importes ni estado de disponibilidad',
      };
    }

    let state: GuardianAiBalanceState = 'OK';
    if (isAvailable === false) state = 'EXHAUSTED';
    else if (amount !== null && amount <= 0) state = 'EXHAUSTED';
    else if (amount !== null && base.lowThreshold !== null && amount < base.lowThreshold) state = 'LOW';

    return {
      state,
      provider: 'deepseek',
      endpoint,
      checkedAt,
      httpStatus: status,
      currency: info.currency,
      totalBalance: info.totalBalance,
      grantedBalance: info.grantedBalance,
      toppedUpBalance: info.toppedUpBalance,
      isAvailable,
      lowThreshold: base.lowThreshold,
      error: null,
    };
  } catch (error) {
    const reason =
      error instanceof Error
        ? error.name === 'AbortError'
          ? `Tiempo de espera agotado al consultar el saldo (${params.timeoutMs ?? 10_000} ms)`
          : error.message
        : String(error);
    return {
      ...base,
      provider: 'deepseek',
      state: 'UNAVAILABLE',
      httpStatus: status,
      error: reason,
    };
  } finally {
    clearTimeout(timeout);
  }
}

/** `true` cuando el estado exige aviso al administrador. */
export function isBalanceAlertState(state: GuardianAiBalanceState): boolean {
  return state === 'LOW' || state === 'EXHAUSTED' || state === 'BILLING_ERROR' || state === 'UNAVAILABLE';
}

/** Etiqueta legible (español) del estado de saldo. */
export function describeBalanceState(state: GuardianAiBalanceState): string {
  switch (state) {
    case 'OK':
      return 'operativo';
    case 'LOW':
      return 'saldo bajo';
    case 'EXHAUSTED':
      return 'saldo agotado';
    case 'BILLING_ERROR':
      return 'facturación rechazada';
    case 'UNAVAILABLE':
      return 'proveedor no disponible';
    default:
      return 'sin configurar';
  }
}
