import {
  DEFAULT_PAGE_LIMIT,
  LEGACY_UNPAGINATED_LIMIT,
  MAX_PAGE_LIMIT,
  hasExplicitPagination,
  normalizePagePagination,
  toPageResult,
} from "./page-pagination";

/**
 * Contrato unico de paginacion.
 *
 * Contexto: el backend paso a paginar por defecto (50) y los clientes antiguos
 * que no envian `page`/`limit` empezaron a recibir datasets truncados en
 * silencio ("faltan productos"). Estos tests fijan las dos reglas que evitan
 * esa regresion:
 *   1. sin paginacion explicita -> se devuelve el conjunto completo (legacy);
 *   2. con paginacion explicita -> pagina acotada + hasMore/nextPage/total.
 */
describe("page-pagination contract", () => {
  describe("hasExplicitPagination", () => {
    it("detecta un cliente legacy (sin page/limit/pageSize)", () => {
      expect(hasExplicitPagination({})).toBe(false);
      expect(hasExplicitPagination({ page: undefined, limit: undefined })).toBe(
        false,
      );
      expect(hasExplicitPagination({ limit: null, page: null })).toBe(false);
      expect(hasExplicitPagination({ page: "", limit: "   " })).toBe(false);
    });

    it("detecta paginacion explicita", () => {
      expect(hasExplicitPagination({ page: 2 })).toBe(true);
      expect(hasExplicitPagination({ limit: 50 })).toBe(true);
      expect(hasExplicitPagination({ pageSize: 20 })).toBe(true);
      expect(hasExplicitPagination({ limit: "50" })).toBe(true);
    });
  });

  describe("normalizePagePagination", () => {
    it("modo legacy: no trunca a 50, devuelve el conjunto completo", () => {
      const pagination = normalizePagePagination({});

      expect(pagination.explicit).toBe(false);
      expect(pagination.skip).toBe(0);
      expect(pagination.limit).toBe(LEGACY_UNPAGINATED_LIMIT);
      expect(pagination.limit).toBeGreaterThan(DEFAULT_PAGE_LIMIT);
      expect(pagination.take).toBe(LEGACY_UNPAGINATED_LIMIT + 1);
    });

    it("permite acotar el modo legacy por endpoint", () => {
      const pagination = normalizePagePagination({ legacyLimit: 300 });

      expect(pagination.explicit).toBe(false);
      expect(pagination.limit).toBe(300);
    });

    it("modo explicito: aplica page/limit y calcula skip/take", () => {
      const pagination = normalizePagePagination({ page: 3, limit: 50 });

      expect(pagination).toEqual({
        page: 3,
        limit: 50,
        skip: 100,
        take: 51,
        explicit: true,
      });
    });

    it("acota limit al maximo permitido", () => {
      expect(normalizePagePagination({ limit: 5000 }).limit).toBe(
        MAX_PAGE_LIMIT,
      );
      expect(normalizePagePagination({ limit: 10, maxLimit: 25 }).limit).toBe(
        10,
      );
    });

    it("normaliza page invalida a 1", () => {
      expect(normalizePagePagination({ page: 0 }).page).toBe(1);
      expect(normalizePagePagination({ page: -5 }).page).toBe(1);
    });
  });

  describe("toPageResult", () => {
    const rows = Array.from({ length: 103 }, (_, index) => ({ id: index + 1 }));

    it("modo legacy devuelve TODO y total exacto (regresion 50)", () => {
      const pagination = normalizePagePagination({});
      const result = toPageResult(rows, pagination);

      expect(result.items).toHaveLength(103);
      expect(result.hasMore).toBe(false);
      expect(result.nextPage).toBeNull();
      expect(result.total).toBe(103);
    });

    it("modo explicito pagina y expone hasMore/nextPage", () => {
      const first = toPageResult(
        rows.slice(0, 51),
        normalizePagePagination({ page: 1, limit: 50 }),
      );

      expect(first.items).toHaveLength(50);
      expect(first.hasMore).toBe(true);
      expect(first.nextPage).toBe(2);

      const last = toPageResult(
        rows.slice(100),
        normalizePagePagination({ page: 3, limit: 50 }),
      );

      expect(last.items).toHaveLength(3);
      expect(last.hasMore).toBe(false);
      expect(last.nextPage).toBeNull();
    });

    it("usa el total autoritativo cuando el servicio lo calcula", () => {
      const result = toPageResult(
        rows.slice(0, 51),
        normalizePagePagination({ page: 1, limit: 50 }),
        103,
      );

      expect(result.total).toBe(103);
      expect(result.hasMore).toBe(true);
      expect(result.nextPage).toBe(2);
    });

    it("deriva hasMore desde total cuando el servicio ya hizo count", () => {
      const result = toPageResult(
        [],
        normalizePagePagination({ page: 1, limit: 50 }),
        500,
      );

      expect(result.total).toBe(500);
      expect(result.hasMore).toBe(true);
      expect(result.nextPage).toBe(2);
    });

    it("nunca inventa un total: queda null si no se conoce", () => {
      const result = toPageResult(
        rows.slice(0, 51),
        normalizePagePagination({ page: 1, limit: 50 }),
      );

      expect(result.total).toBeNull();
    });
  });
});
