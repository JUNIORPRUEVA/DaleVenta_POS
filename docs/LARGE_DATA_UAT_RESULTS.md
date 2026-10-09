# Large data UAT results

Fecha: 2026-10-08

## Entorno UAT local

Estado: **BLOCKED_EXTERNAL / infraestructura local**.

Evidencia:

- Existe `apps/api/.env.uat.local`.
- La configuracion apunta a `127.0.0.1:55432/daleventa_uat_local`.
- `127.0.0.1:55432` no esta escuchando.
- `docker` no esta instalado o no esta en `PATH`.
- `scripts/uat/start.ps1` fallo antes de cualquier escritura con: Docker no instalado/no disponible.
- `127.0.0.1:5432` responde en red, pero no acepto las credenciales locales/UAT conocidas; no se uso para escrituras porque no se pudo demostrar aislamiento UAT.

Produccion:

- Writes: NO.
- Migrations: NO.
- Deploy: NO.
- Repair/close shift/restart: NO.

## Generador large-data

Dry-runs ejecutados sin escrituras:

| Perfil | Resultado | Dataset key | Base date |
| --- | --- | --- | --- |
| 1K | PASS previo | `uat-smoke` | `2026-10-08T00:00:00.000Z` |
| 10K | PASS | `uat-10k` | `2026-10-08T00:00:00.000Z` |
| 50K | PASS | `uat-50k` | `2026-10-08T00:00:00.000Z` |

El generador queda listo para ejecutar con `--execute` solo cuando exista una DB UAT local/desechable alcanzable y validada por las guardas.

## Reports

Validado localmente con tests:

- Ruta agregada DB completa sin filtro de categoria.
- Assertion de no materializacion: no llama `Sale.findMany` ni `Product.findMany` en la ruta agregada real.
- Fallback materializado permanece para filtro de categoria hasta migrar prorrateo category-filtered con equivalencia dedicada.

Validaciones:

- `npm --workspace apps/api test -- --runTestsByPath src/reports/reports.service.spec.ts src/reports/reports.credit-collection.spec.ts`: PASS, 30 tests.
- `npm run api:build`: PASS.
- `npm --workspace apps/api test`: PASS, 644 tests.
- `npx prisma validate`: PASS.
- `node scripts/audit-large-dataset-queries.mjs --fail-on-open`: PASS, open findings 0.

## Pendiente desbloqueable

Para ejecutar 1K/10K/50K real:

1. Instalar/iniciar Docker Desktop, o proveer PostgreSQL local aislado equivalente.
2. Ejecutar `scripts/uat/start.ps1`.
3. Confirmar DB `daleventa_uat_local` en `127.0.0.1:55432`.
4. Ejecutar generador con `--execute`.

No se requiere ningun dato de produccion ni Cafeteria La Bomba para este flujo.
