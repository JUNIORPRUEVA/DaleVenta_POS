# Guardrails de escalabilidad y large datasets

Fecha: 2026-10-07

## Reglas obligatorias

1. Ningun endpoint GET de listado que pueda crecer debe devolver todo por defecto.
2. Todo listado grande debe aceptar `page` y `limit`, aplicar limite por defecto y cap maximo.
3. El orden debe ser estable y agregar `id` como desempate cuando se pagina.
4. Las pantallas deben abrir con primera pagina y cargar mas bajo demanda.
5. Los reportes deben devolver agregados calculados en backend/DB, no miles de filas para sumar en Flutter.
6. Los backups deben leer modulos grandes por paginas o chunks.
7. Los jobs multi-tenant deben paginar tenants y limitar concurrencia.
8. La paginacion nunca puede remover `companyId` ni debilitar filtros tenant-scoped.

## Contrato recomendado

```json
{
  "items": [],
  "page": 1,
  "limit": 50,
  "hasMore": false,
  "nextPage": null
}
```

Backend:

- Usar `normalizePagePagination` y `toPageResult` de `apps/api/src/common/pagination/page-pagination.ts`.
- Default global: 50.
- Max global: 200.
- Fetch interno: `take = limit + 1`.

Flutter:

- Los repositorios deben aceptar tanto `List` legacy como `{ "items": [] }`.
- Refresh recarga pagina 1.
- Error de pagina siguiente no debe borrar paginas ya visibles.

## Checklist para nuevos endpoints

- [ ] `companyId` aplicado antes de paginar.
- [ ] `limit` validado/capeado.
- [ ] `page` minimo 1.
- [ ] `orderBy` estable.
- [ ] List DTO liviano.
- [ ] Detail endpoint separado si hay relaciones grandes.
- [ ] Test tenant isolation.
- [ ] Test de limite por defecto.
- [ ] Consumidor Flutter no asume `List` unicamente.
