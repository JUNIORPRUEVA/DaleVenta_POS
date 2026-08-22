# DB-DRIFT-REPORT — app_config / admin_authorization_pin_hash

> Fecha auditoría: 2026-08-22 · Método: READ-ONLY (information_schema + `_prisma_migrations`)
> Base: `apps/api/.env` → `DATABASE_URL` (PostgreSQL remoto, easypanel)

## 1. ESTADO ANTES

### 1.1 `_prisma_migrations`
- **139 filas** registradas como aplicadas.
- Última aplicada: `20260807040000_repair_company_license_columns` (finishedAt `2026-08-07T02:31:48Z`).
- **NO incluye** las migraciones del repo fechadas `20260818+` (baseline consolidado y siguientes).

### 1.2 Carpeta `prisma/migrations` (repo)
Solo 5 migraciones consolidadas:
- `20260818190000_phase6_baseline`
- `20260818193000_quote_tax_snapshots`
- `20260818203000_sales_quote_refund_snapshots`
- `20260818213000_add_sale_issuer_customer_snapshots`
- `20260821220000_add_sale_ncf_expiration`

→ El repo adoptó un **baseline consolidado** que **nunca se aplicó** a esta BD. Historial repo vs BD **DESINCRONIZADO**.

### 1.3 Columnas reales de `app_config` (information_schema)
29 columnas, con **naming mixto** (camelCase + snake_case), consistentes con `schema.prisma` **excepto una**.

### 1.4 Tabla de diferencias (`schema.prisma` ↔ BD real)

| Campo (schema) | Columna BD | Estado |
|---|---|---|
| `id` | `id` | ✅ |
| `companyId` | `company_id` | ✅ |
| `companyName` | `companyName` | ✅ |
| `rnc` | `rnc` | ✅ |
| `phone` | `phone` | ✅ |
| `phonePreferential` | `phone_preferential` | ✅ |
| `address` | `address` | ✅ |
| `description` | `description` | ✅ |
| `instagramUrl` | `instagram_url` | ✅ |
| `facebookUrl` | `facebook_url` | ✅ |
| `websiteUrl` | `website_url` | ✅ |
| `gpsLocationUrl` | `gps_location_url` | ✅ |
| `businessHours` | `business_hours` | ✅ |
| `bankAccounts` | `bank_accounts` | ✅ |
| `legalRepresentativeName` | `legal_representative_name` | ✅ |
| `legalRepresentativeCedula` | `legal_representative_cedula` | ✅ |
| `legalRepresentativeRole` | `legal_representative_role` | ✅ |
| `legalRepresentativeNationality` | `legal_representative_nationality` | ✅ |
| `legalRepresentativeCivilStatus` | `legal_representative_civil_status` | ✅ |
| `logoBase64` | `logoBase64` | ✅ |
| `openAiApiKey` | `openAiApiKey` | ✅ |
| `openAiModel` | `openAiModel` | ✅ |
| `evolutionApiBaseUrl` | `evolution_api_base_url` | ✅ |
| `evolutionApiInstanceName` | `evolution_api_instance_name` | ✅ |
| `evolutionApiApiKey` | `evolution_api_api_key` | ✅ |
| `whatsappWebhookEnabled` | `whatsapp_webhook_enabled` | ✅ |
| `operationsTechCanViewAllServices` | `operations_tech_can_view_all_services` | ✅ |
| **`adminAuthorizationPinHash`** | **`admin_authorization_pin_hash`** | ❌ **FALTA** |
| `createdAt` | `createdAt` | ✅ |
| `updatedAt` | `updatedAt` | ✅ |

### 1.5 Causa raíz del drift
- La migración `20260730130000_add_admin_authorization_pin` figura en `_prisma_migrations` como aplicada (08-07), pero la columna **no existe** en la BD → **drift manual / historial desincronizado** (la columna nunca se materializó, o el historial se re-importó sin su efecto).
- `prisma migrate deploy` **NO es seguro** en esta BD: `phase6_baseline` recrea tablas existentes (`CREATE TABLE` sin `IF NOT EXISTS`) → fallaría. **No ejecutar `migrate deploy` hasta reconciliar el historial.**

## 2. CORRECCIÓN (aditiva, NO destructiva)

Equivalent to schema: `String? @map("admin_authorization_pin_hash")` → `TEXT NULL`.

```sql
ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "admin_authorization_pin_hash" TEXT;
```

Registrada en: `apps/api/prisma/migrations/20260822000000_add_admin_authorization_pin_drift_fix/migration.sql`

**Forma segura de aplicar (tras backup):**
```powershell
# 1) Backup (pg_dump disponible en C:\Program Files\PostgreSQL\17\bin\pg_dump.exe)
#    usar la DATABASE_URL de apps/api/.env; guardar FUERA del repo:
& "C:\Program Files\PostgreSQL\17\bin\pg_dump.exe" "<DATABASE_URL>" -Fc -f "$env:TEMP\daleventa_backup_$(Get-Date -Format yyyyMMdd_HHmmss).dump"

# 2) Aplicar el ALTER vía psql (misma URL), o node/prisma:
#    psql "<DATABASE_URL>" -c 'ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "admin_authorization_pin_hash" TEXT;'
```
> ⚠️ **PENDIENTE DE APLICAR** — se difiere hasta confirmar el deploy del backend nuevo y realizar el backup (ver AUDITORIA-NOMBRE-EMPRESA.md).

## 3. VALIDACIÓN POST-MIGRACIÓN (cuando se aplique)

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'app_config' AND column_name = 'admin_authorization_pin_hash';
```
Esperado: `admin_authorization_pin_hash | text | YES`.
Luego: probar Prisma contra `app_config` (sin `column does not exist`) y el flujo de PIN administrativo (set/validate/update/restart).

## 4. ESTADO ACTUAL DE LA EMPRESA (no relacionado al drift, verificado)
- `Company.name` = `FULLTECH, SRL`
- `AppConfig.companyName` = `FULLTECH, SRL`
- `updatedAt` = 2026-08-22T21:34:12Z

---

# DECISIÓN PRISMA_SYNC_MODE (2026-08-22)

## Dónde se usa (código verificado)
- `apps/api/scripts/start-prod.sh` (entrypoint del contenedor, `CMD ["sh", "scripts/start-prod.sh"]`).
- `package.json` `prestart: prisma migrate deploy` — **NO se ejecuta en el contenedor** (arranca con `exec node dist/main.js`).
- `.env.docker.example` / `.env.example` línea 43: `PRISMA_SYNC_MODE=push` (solo ejemplo; `push` está bloqueado en producción por el script salvo `ALLOW_PRODUCTION_DB_PUSH=true`).

## Comando real que ejecuta
- Default: `${PRISMA_SYNC_MODE:-migrate}` → **quitar la variable NO cambia el comportamiento** (sigue `migrate`).
- `migrate` → `npx prisma migrate deploy` (reintentos 10×5 s + resolver P3009 para una migración antigua específica; si falla y `MIGRATION_STRICT!=true`, el arranque continúa).
- `push` → `npx prisma db push --accept-data-loss` (DESTRUCTIVO, bloqueado en prod).

## Riesgo
- `migrate deploy` contra esta BD intentaría aplicar `phase6_baseline` (100% CREATE, sin `IF NOT EXISTS` ni `DROP`) → falla por tipos/tablas ya existentes → P3009/noise; **no destructivo, pero inútil**. `push` es destructivo y está bloqueado.

## Decisión
- **OPCIÓN D — NO sincronización automática en producción.** Mantener `PRISMA_SYNC_MODE` eliminada + **`RUN_MIGRATIONS=false`**. Cambios de esquema: manuales (backup + ALTER aditivo + validación). NO restaurar `migrate` ni usar `db push` hasta reconciliar el historial de migraciones.

---

# ⛔ DRIFT ADICIONAL CRÍTICO — tabla `companies` (2026-08-22)

Durante la validación read-only previa al ALTER se detectó drift adicional **crítico**:

- `prisma.company.findUnique` con campos fiscales falla: `The column companies.tax_enabled does not exist`.
- `information_schema` confirma que `companies` carece de **5 columnas** del schema actual:

| Campo (schema `Company`) | Columna esperada | Estado |
|---|---|---|
| `taxEnabled Boolean @default(false)` | `tax_enabled BOOLEAN NOT NULL DEFAULT false` | ❌ FALTA |
| `defaultTaxId String? @db.Uuid` | `default_tax_id UUID` | ❌ FALTA |
| `defaultTaxRate Decimal @default(0) @db.Decimal(5,4)` | `default_tax_rate DECIMAL(5,4) NOT NULL DEFAULT 0` | ❌ FALTA |
| `pricesIncludeTax Boolean @default(false)` | `prices_include_tax BOOLEAN NOT NULL DEFAULT false` | ❌ FALTA |
| `ncfEnabled Boolean @default(false)` | `ncf_enabled BOOLEAN NOT NULL DEFAULT false` | ❌ FALTA |

**Impacto en producción (backend nuevo ya desplegado):**
- `tax.service.getCompanyFiscalSettings` y `settings.service` (get/update settings y updateCompanyName) seleccionan esas columnas → **`GET/PATCH /settings` y endpoints de impuestos devolverían 500** ("column does not exist") hasta añadirlas.
- `prisma migrate status` → **exit 1** (migraciones del repo sin aplicar; historial desincronizado).

**Corrección recomendada (ADITIVA, NO aplicada — requiere autorización):**
```sql
ALTER TABLE "companies" ADD COLUMN IF NOT EXISTS "tax_enabled" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "companies" ADD COLUMN IF NOT EXISTS "default_tax_id" UUID;
ALTER TABLE "companies" ADD COLUMN IF NOT EXISTS "default_tax_rate" DECIMAL(5,4) NOT NULL DEFAULT 0;
ALTER TABLE "companies" ADD COLUMN IF NOT EXISTS "prices_include_tax" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "companies" ADD COLUMN IF NOT EXISTS "ncf_enabled" BOOLEAN NOT NULL DEFAULT false;
```
Junto con el ALTER de `app_config` (ya preparado):
```sql
ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "admin_authorization_pin_hash" TEXT;
```
> ⛔ **SIN APLICAR** — el usuario ordenó DETENERSE ante drift crítico adicional y reportarlo antes de modificar la BD. Backup listo: `%TEMP%\daleventa_backup_20260822_180416.dump` (exit 0, 445947 bytes).

**Estado de la configuración de producción (verificado en código):**
- `RUN_MIGRATIONS=false` → `start-prod.sh` salta el bloque de sync de Prisma (no ejecuta `migrate deploy` ni `db push`).
- `PRISMA_SYNC_MODE` sin definir → default `migrate`, irrelevante con `RUN_MIGRATIONS=false`.

---

# ⛔ DRIFT ES MUCHO MAYOR — falta TODA la fundación fiscal/NCF (2026-08-22)

Auditoría read-only integral (información exacta del SQL original):

## Schema exacto de las 6 columnas (schema.prisma ↔ migración original)
| Campo Prisma | `@map` | Tipo DB | Nullable | Default | Constraint/relación |
|---|---|---|---|---|---|
| `Company.taxEnabled` | `tax_enabled` | BOOLEAN | NO | `false` | sin FK/índice |
| `Company.defaultTaxId` | `default_tax_id` | UUID | SÍ | — | **sin FK** (sin relación en schema; columna UUID simple) |
| `Company.defaultTaxRate` | `default_tax_rate` | DECIMAL(5,4) | NO | `0` | sin FK/índice |
| `Company.pricesIncludeTax` | `prices_include_tax` | BOOLEAN | NO | `false` | sin FK/índice |
| `Company.ncfEnabled` | `ncf_enabled` | BOOLEAN | NO | `false` | sin FK/índice |
| `AppConfig.adminAuthorizationPinHash` | `admin_authorization_pin_hash` | TEXT | SÍ | — | sin FK/índice |

## SQL original (fuente de verdad, migraciones legacy)
- `migrations_legacy_pre_phase6/20260818120000_add_tax_and_ncf_foundation/migration.sql` — agrega las 5 columnas de `companies` + tablas `taxes`, `ncf_sequences`, `ncf_audit_logs` + columnas fiscales en `Product`, `Sale`, `SaleItem`, `Client` (todo `ADD COLUMN IF NOT EXISTS` / `CREATE TABLE IF NOT EXISTS`, aditivo e idempotente; **sin FK sobre `companies.default_tax_id`**).
- `migrations_legacy_pre_phase6/20260730130000_add_admin_authorization_pin/migration.sql` — `ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "admin_authorization_pin_hash" TEXT;`.

## Qué falta REALMENTE en producción (evidencia read-only)
- ❌ Tablas inexistentes: `taxes`, `ncf_sequences`, `ncf_audit_logs`.
- ❌ `companies`: faltan `tax_enabled`, `default_tax_id`, `default_tax_rate`, `prices_include_tax`, `ncf_enabled`.
- ❌ `Product`: faltan `tax_treatment`, `tax_rate`, `tax_price_mode`.
- ❌ `Sale`: faltan `fiscal_tax_enabled`, `fiscal_price_mode`, `taxable_base`, `tax_amount`, `exempt_amount`, `discount_amount`, `fiscal_voucher_type`, `ncf`, `fiscal_customer_tax_id`, `fiscal_customer_name`.
- ❌ `SaleItem`: faltan `gross_amount`, `line_discount_amount`, `taxable_base`, `tax_rate`, `tax_amount`, `exempt_amount`, `tax_included`, `tax_exempt`.
- ❌ `Client`: faltan `tax_id`, `business_name`, `tax_id_type`.
- ✅ `companies` count = 1 · constraints: solo `companies_pkey` · `app_config`: `app_config_pkey`, `app_config_company_id_fkey`.
- 📄 `migrations_legacy_pre_phase6/README.md`: la estrategia documentada era marcar el baseline como aplicado (`migrate resolve --applied 20260818190000_phase6_baseline`) **solo tras verificar** que el schema coincide — NO coincide (falta toda la fundación fiscal).

## Datos fiscales preexistentes / backfill
- No existe `taxes` ni configuración fiscal en otra tabla → **no hay datos que respaldar (backfill: NO)**. Defaults `false/0` son semánticamente correctos (producción ya operaba sin impuestos/NCF).

## DECISIÓN — DETENCIÓN (instrucción del usuario)
- La corrección NO es de 6 columnas: requiere **crear 3 tablas** y **agregar columnas a `Sale`/`SaleItem`/`Product`/`Client`** (modificar tablas de ventas/NCF).
- El usuario ordenó DETENERSE si se necesita crear tablas o modificar ventas/NCF → **NO se aplicó ningún ALTER**.
- Opciones a decidir (Ninguna ejecutada):
  1. Aplicar la **migración original completa** `20260818120000_add_tax_and_ncf_foundation` (aditiva/idempotente) de forma manual controlada + el ALTER de app_config. Es lo que `migrate deploy` haría para esa migración, sin `_prisma_migrations`.
  2. Reconciliar historial primero (`migrate resolve`) — trabajo separado.
  3. Mantener `RUN_MIGRATIONS=false` y no tocar BD hasta decidir.
- Impacto en producción: con el backend nuevo desplegado y esta fundación ausente, `GET/PATCH /settings` e impuestos/NCF devuelven **500** (relation/column does not exist). Urgente decidir.

---

# 🚨 EVIDENCIA CONFIRMADA EN VIVO (2026-08-22) — el drift está rompiendo el header

La regresión visual reportada ("el header muestra `FullPOS Cloud` en vez de `FULLTECH, SRL`") fue diagnosticada y **NO es corrupción de datos**:

- `Company.name` = `FULLTECH, SRL` · `AppConfig.companyName` = `FULLTECH, SRL` (verificado en DB; sin eventos de rename).
- Causa raíz confirmada: `GET /settings` → `tax.service.getCompanyFiscalSettings` → `company.findUnique({ select: companyFiscalSelect() })` (selecciona `tax_enabled`, `default_tax_id`, `default_tax_rate`, `prices_include_tax`, `ncf_enabled`) → **`PrismaClientKnownRequestError` "column companies.tax_enabled does not exist" → HTTP 500**.
- El cliente (`companySettingsProvider`) captura el 500 → cae a caché/empty → el header muestra fallback (placeholder vacío en la build nueva; `FullPOS Cloud` como branding en builds antiguas / título de escritorio).
- `products.service` NO consulta columnas fiscales → el listado de productos de Facturación funciona; solo settings/empresa fallan.

**Conclusión:** reparar este drift NO es opcional para el cierre — es la **causa raíz del header roto** y de los 500 en `/settings`/impuestos en producción con el backend nuevo. Sigue pendiente tu autorización para aplicar la migración original completa (`20260818120000_add_tax_and_ncf_foundation` + `admin_authorization_pin_hash`) sobre el backup ya tomado.

**Estado actual: NO APLICADO — en espera de autorización.**

---

# ✅ REPARACIÓN APLICADA (2026-08-22) — resultado completo

## SQL exacto ejecutado (dentro de una transacción, `BEGIN`/`COMMIT`; `ROLLBACK` ante cualquier error)
1. Contenido íntegro de `prisma/migrations_legacy_pre_phase6/20260818120000_add_tax_and_ncf_foundation/migration.sql`
   (aditivo/idempotente: `CREATE TYPE ... IF NOT EXISTS` (guarded), `CREATE EXTENSION IF NOT EXISTS btree_gist`,
   `ADD COLUMN IF NOT EXISTS` en `companies`/`Product`/`Sale`/`SaleItem`/`Client`, `CREATE TABLE IF NOT EXISTS`
   `taxes`/`ncf_sequences`/`ncf_audit_logs`, FKs y constraints guardados, índices `IF NOT EXISTS`, EXCLUDE `ncf_sequences_no_overlap`).
2. `ALTER TABLE "app_config" ADD COLUMN IF NOT EXISTS "admin_authorization_pin_hash" TEXT;`

Fail-safe previo: el script abortaba si el SQL contenía `DROP TABLE`/`TRUNCATE`/`DELETE FROM`/`RENAME`/`DROP COLUMN` (ninguno presente). NO se tocó `_prisma_migrations`; NO se usó `migrate deploy/push/reset/resolve`.

## Resultado de la transacción
```
BEGIN → migration.sql OK → app_config ALTER OK → COMMIT → MIGRATION OK
```

## Row counts ANTES → DESPUÉS (sin pérdida de datos)
| Tabla | Antes | Después |
|---|---|---|
| Sale | 0 | 0 |
| SaleItem | 0 | 0 |
| Product | 0 | 0 |
| Client | 0 | 0 |
| companies | 1 | 1 |
| app_config | 1 | 1 |
| taxes | (no existía) | 0 |
| ncf_sequences | (no existía) | 0 |
| ncf_audit_logs | (no existía) | 0 |

## Schema DESPUÉS (information_schema)
- Tablas nuevas: `taxes`, `ncf_sequences`, `ncf_audit_logs`.
- Columnas nuevas (21): `companies(tax_enabled,default_tax_id,default_tax_rate,prices_include_tax,ncf_enabled)`,
  `app_config(admin_authorization_pin_hash)`, `Product(tax_treatment,tax_rate,tax_price_mode)`,
  `Sale(fiscal_tax_enabled,fiscal_price_mode,taxable_base,tax_amount,exempt_amount,discount_amount,fiscal_voucher_type,ncf,fiscal_customer_tax_id,fiscal_customer_name)`,
  `SaleItem(gross_amount,line_discount_amount,taxable_base,tax_rate,tax_amount,exempt_amount,tax_included,tax_exempt)`,
  `Client(tax_id,business_name,tax_id_type)`.

## Prisma smoke test (9 modelos) — ✅ sin errores de columna/relación
`Company` (con fiscal), `AppConfig` (con pin), `Product`, `Sale`, `SaleItem`, `Client`, `Tax`, `NcfSequence`, `NcfAuditLog`.

## Company name
`Company.name = FULLTECH, SRL` · `AppConfig.companyName = FULLTECH, SRL` (intactos).

## `/settings` y fiscal/NCF
- Causa del 500 (`companyFiscalSelect()` → columnas faltantes) **ELIMINADA**: la consulta exacta ahora funciona vía Prisma.
- Fiscal/ITBIS y NCF verificados a nivel de BD (tablas/columnas/lecturas OK).
- ⏳ Live autenticado (`GET /settings`, flujo PIN, endpoints fiscal/NCF) pendiente de confirmación con sesión admin real (proporciono comandos).

## Tests
- Backend `npm test`: **99/99** · `npm run build`: ✅
- Flutter `flutter analyze`: **No issues found** · tests settings/account: **16/16**
- `/health` → 200 · `PATCH /settings/company-name` (unauth) → 401.

## Backups
- `%TEMP%\daleventa_backup_20260822_180416.dump` (445947 B) y `%TEMP%\daleventa_pre_migration_20260822_183231.dump` (445947 B) — fuera del repo.
