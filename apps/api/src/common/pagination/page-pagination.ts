export const DEFAULT_PAGE_LIMIT = 50;
export const MAX_PAGE_LIMIT = 200;

export type PagePagination = {
  page: number;
  limit: number;
  skip: number;
  take: number;
};

export type PageResult<T> = {
  items: T[];
  page: number;
  limit: number;
  hasMore: boolean;
  nextPage: number | null;
};

export function normalizePagePagination(params: {
  page?: number | string | null;
  limit?: number | string | null;
  pageSize?: number | string | null;
  defaultLimit?: number;
  maxLimit?: number;
}): PagePagination {
  const defaultLimit = params.defaultLimit ?? DEFAULT_PAGE_LIMIT;
  const maxLimit = params.maxLimit ?? MAX_PAGE_LIMIT;
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
  };
}

export function toPageResult<T>(
  rows: T[],
  pagination: PagePagination,
): PageResult<T> {
  const items = rows.slice(0, pagination.limit);
  const hasMore = rows.length > pagination.limit;
  return {
    items,
    page: pagination.page,
    limit: pagination.limit,
    hasMore,
    nextPage: hasMore ? pagination.page + 1 : null,
  };
}
