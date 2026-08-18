# FullPOS Tax Phase 5 - Staging Validation

Fecha: 2026-08-18

# Entorno Staging

- Host PostgreSQL: `gcdndd.easypanel.host`
- Base staging: `fullpos_staging`
- Produccion: no se migro, no se reseteo, no se modifico
- Credenciales: no documentadas ni impresas

# Reparacion De Drift

Inspeccion read-only inicial:

- `_prisma_migrations`: no existia
- Tablas: 108
- Datos no vacios: solo `companies=2` y `users=2`
- Usuarios detectados: fixtures `phase5-...@example.test`

Conclusion: staging era desechable/test y probablemente creada con `db push`.

Accion ejecutada:

```text
DROP DATABASE fullpos_staging
CREATE DATABASE fullpos_staging
npx prisma migrate deploy
npx prisma migrate status
```

Resultado:

```text
Database schema is up to date!
```

# Migraciones Aplicadas

- `20260818190000_phase6_baseline`
- `20260818193000_quote_tax_snapshots`
- `20260818203000_sales_quote_refund_snapshots`
- `20260818213000_add_sale_issuer_customer_snapshots`

# Columnas Criticas Confirmadas

- `Sale.source_quotation_id`
- `Sale.issuer_name_snapshot`
- `Sale.issuer_tax_id_snapshot`
- `Sale.issuer_address_snapshot`
- `Sale.issuer_phone_snapshot`
- `Sale.issuer_email_snapshot`
- `Sale.customer_address_snapshot`
- `Sale.customer_phone_snapshot`

# Resultado Fiscal Staging

Comando:

```text
npm run test:staging:fiscal
```

Resultado: `PASS`

```json
{
  "database": "fullpos_staging",
  "duplicateNcf": {
    "sameCompanyDuplicate": "blocked",
    "crossCompanySameNcf": "allowed"
  },
  "concurrency20": {
    "requested": 20,
    "maxParallel": 20,
    "sales": 20,
    "uniqueNcf": 20,
    "nextNumber": 21
  },
  "concurrency100": {
    "requested": 100,
    "maxParallel": 20,
    "sales": 100,
    "uniqueNcf": 100,
    "nextNumber": 101
  },
  "idempotency": {
    "concurrentRequests": 20,
    "maxParallel": 20,
    "persistedSales": 1,
    "uniqueSaleIds": 1,
    "uniqueNcf": 1,
    "nextNumber": 2
  },
  "exhausted": {
    "first": "B0100000014",
    "second": "B0100000015",
    "third": "blocked",
    "nextNumber": 16
  },
  "sequenceRules": {
    "secondActive": "blocked",
    "overlappingInactive": "blocked"
  },
  "quotes": {
    "quotes": 100,
    "ncfConsumed": 0,
    "fulltechTotal": "25700.00",
    "fulltechBase": "21779.66",
    "fulltechItbis": "3920.34"
  }
}
```

# Nota De Pool

El servidor remoto rechazo `connection_limit=120` con `too many clients already`. La suite usa `FISCAL_STAGING_MAX_PARALLEL=20` y `connection_limit=30`, procesando 100 emisiones fiscales por el mismo camino transaccional `FOR UPDATE` sin duplicar NCF.

# Quality Gate Asociado

- `npx prisma validate`: PASS
- `npm run build`: PASS
- `npm test`: PASS - 10 suites / 45 tests
- `npm run test:e2e`: PASS - 1 suite / 4 tests
- `flutter analyze`: PASS
- `flutter test`: PASS - 132 tests
- `flutter build web`: PASS

# Readiness

Staging fiscal tradicional queda `READY`.

Pendiente fuera de desarrollo:

- QA humana PC/mobile
- QA visual PDF/ticket
- prueba fisica 80mm
- backup/rollback y despliegue controlado de produccion

e-CF sigue fuera de alcance.
