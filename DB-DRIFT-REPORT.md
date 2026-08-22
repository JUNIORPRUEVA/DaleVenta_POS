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
