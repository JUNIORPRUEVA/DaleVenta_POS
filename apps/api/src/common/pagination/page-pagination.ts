export const DEFAULT_PAGE_LIMIT = 50;
export const MAX_PAGE_LIMIT = 200;

/**
 * Red de seguridad para clientes LEGACY que no piden paginacion explicita.
 *
 * Los clientes Windows/PWA anteriores al contrato paginado llaman a estos
 * endpoints SIN `page`, `limit` ni `pageSize`, y consumen la respuesta como si
 * fuera el dataset completo. Si el backend les aplicara el limite por defecto
 * (50) verian datos truncados de forma silenciosa: ese es el incidente
 * "faltan productos".
 *
 * Por eso: si el cliente no pide paginacion de forma explicita se devuelve el
 * conjunto completo (hasta este tope de seguridad, que NO es un limite
 * funcional). Es temporal: LEGACY_CLIENT_COMPAT_MODE.
 */
export const LEGACY_UNPAGINATED_LIMIT = 5000;

export type PagePagination = {
  page: number;
  limit: number;
  skip: number;
  take: number;
  /**
   * true  -> el cliente pidio paginacion explicitamente (page/limit/pageSize).
   * false -> cliente legacy: se devuelve el conjunto completo (LEGACY mode).
   */
  explicit: boolean;
};

export type PageResult<T> = {
  items: T[];
  page: number;
  limit: number;
  total: number | null;
  hasMore: boolean;
  nextPage: number | null;
};

export type NormalizePagePaginationParams = {
  page?: number | string | null;
  limit?: number | string | null;
  pageSize?: number | string | null;
  defaultLimit?: number;
  maxLimit?: number;
  /** Tope del modo legacy para este endpoint (por defecto LEGACY_UNPAGINATED_LIMIT). */
  legacyLimit?: number;
};

function isProvided(value: unknown): boolean {
  return value !== undefined && value !== null && `${value}`.trim() !== "";
}

/**
 * true si el cliente pidio paginacion de forma explicita.
 * Un cliente legacy no envia ninguna de estas claves.
 */
export function hasExplicitPagination(
  params: NormalizePagePaginationParams,
): boolean {
  return (
    isProvided(params.page) ||
    isProvided(params.limit) ||
    isProvided(params.pageSize)
  );
}

export function normalizePagePagination(
  params: NormalizePagePaginationParams,
): PagePagination {
  const defaultLimit = params.defaultLimit ?? DEFAULT_PAGE_LIMIT;
  const maxLimit = params.maxLimit ?? MAX_PAGE_LIMIT;

  // Cliente legacy: nunca truncar silenciosamente.
  if (!hasExplicitPagination(params)) {
    const legacyLimit = Math.max(
      params.legacyLimit ?? LEGACY_UNPAGINATED_LIMIT,
      defaultLimit,
    );
    return {
      page: 1,
      limit: legacyLimit,
      skip: 0,
      take: legacyLimit + 1,
      explicit: false,
    };
  }

  const rawLimit = params.limit ?? params.pageSize;
  const parsedLimit = Number(rawLimit ?? defaultLimit);
  const parsedPage = Number(params.page ?? 1);
  const limit = Number.isFinite(parsedLimit)
    ? Math.min(Math.max(Math.trunc(parsedLimit), 1), maxLimit)
    : defaultLimit;
  const page = Number.isFinite(parsedPage)
    ? Math.max(Math.trunc(parsedPage), 1)
    : 1;

  return {
    page,
    limit,
    skip: (page - 1) * limit,
    take: limit + 1,
    explicit: true,
  };
}

/**
 * Construye la respuesta paginada.
 *
 * `total` debe ser el total DESPUES de filtros/search y ANTES de paginar.
 *  - Si el servicio lo calcula (count/aggregate), se pasa y se usa.
 *  - En modo legacy el conjunto ES completo, asi que total = rows.length.
 *  - Si no se conoce, queda `null` (honesto: nunca un numero inventado).
 */
export function toPageResult<T>(
  rows: T[],
  pagination: PagePagination,
  total?: number | null,
): PageResult<T> {
  const items = rows.slice(0, pagination.limit);

  let resolvedTotal: number | null = null;
  if (typeof total === "number" && Number.isFinite(total)) {
    resolvedTotal = total;
  } else if (!pagination.explicit) {
    resolvedTotal = rows.length;
  }
  const hasMore =
    typeof resolvedTotal === "number" && pagination.explicit
      ? pagination.page * pagination.limit < resolvedTotal
      : rows.length > pagination.limit;

  return {
    items,
    page: pagination.page,
    limit: pagination.limit,
    total: resolvedTotal,
    hasMore,
    nextPage: hasMore ? pagination.page + 1 : null,
  };
}
