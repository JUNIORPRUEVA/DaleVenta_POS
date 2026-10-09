# Large data UAT generator

Fecha: 2026-10-08

## Script

`apps/api/scripts/generate-large-dataset.cjs`

## Modo seguro

Por defecto es `DRY_RUN` y no escribe en base de datos.

Ejemplo dry-run:

```powershell
node apps/api/scripts/generate-large-dataset.cjs --company-id=<uuid> --user-id=<uuid> --profile=10k --dataset-key=uat-10k --base-date=2026-10-08T00:00:00.000Z
```

Para escribir exige:

- `--execute`
- `--company-id=<uuid>`
- `--user-id=<uuid>`
- `--profile=1k|10k|50k` o `--scale=<N>`; si ambos se envian, `--scale` manda
- `--dataset-key=<nombre>` para IDs/marcadores determinísticos por empresa
- `--base-date=<ISO>` para fechas reproducibles; por defecto `2026-10-08T00:00:00.000Z`
- entorno UAT/local desechable:
  - `APP_ENV=uat`, o
  - `UAT_LOCAL_ONLY=true`, o
  - `LARGE_DATA_GENERATOR_ALLOW_WRITE=true`

Tambien bloquea URLs de base que parezcan produccion (`prod`, `production`, `gcdndd`, `easypanel`).

## Datos generados

Para `--scale=N`:

- clientes: `max(10, N/10)`
- productos: `max(10, N/25)`
- ventas: `N`
- sale items: `2N`
- abonos credito: `N/5`
- refunds: `N/20`
- cash movements: `N/10`
- suppliers: `max(5, N/1000)`
- purchase orders: `max(10, N/20)`
- purchase order items: `max(10, N/10)`
- purchase invoices: aproximadamente `purchase orders / 4`
- inventory movements: `max(10, N/10)`
- quotes: `max(10, N/15)`
- quote items: `max(20, N/8)`
- service orders: `max(10, N/25)`
- cash session abierta para la prueba
- warehouse UAT `LD-UAT`

## Estado

- DRY_RUN 1K ejecutado: PASS.
- DRY_RUN 1K con `--dataset-key=uat-smoke` y `--base-date=2026-10-08T00:00:00.000Z`: PASS.
- DRY_RUN `--profile=10k`: PASS.
- DRY_RUN `--profile=50k`: PASS.
- Escritura UAT 10K: PENDIENTE.
- Escritura UAT 50K: PENDIENTE.
- Purchases, inventory movements, quotes y service orders: IMPLEMENTADO EN SCRIPT / PENDIENTE EJECUCION UAT.
