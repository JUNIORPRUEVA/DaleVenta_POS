# Riesgo de migraciones e-CF

> Basado en la lectura del SQL real de las migraciones e-CF y en la ejecución de
> `prisma migrate deploy` contra bases **desechables**. No se aplicó ninguna
> migración sobre datos compartidos ni productivos.

## 1. Veredicto

**GO CON RESERVA.** Las migraciones e-CF son **puramente aditivas** y una sola
toca una tabla del POS. La reserva son dos `CREATE INDEX` no concurrentes sobre
`ecf_evidences` y la deriva preexistente, que **no se corrige a propósito**.

## 2. Qué se verificó (HECHO)

Barrido de las 12 migraciones e-CF y de las específicas sobre tablas del POS:

| Operación | ¿Aparece? |
| --- | --- |
| `DROP TABLE` | **No** |
| `DROP COLUMN` | **No** |
| `TRUNCATE` | **No** |
| `DELETE FROM` | **No** |
| `ALTER COLUMN … TYPE` | **No** |
| `ADD COLUMN … NOT NULL` **sin** `DEFAULT` | **No** |
| `CREATE INDEX` | Sí (todas sobre tablas `ecf_*`, salvo la columna del POS) |

Consecuencia: no hay ninguna migración capaz de destruir datos ni de romper la
compatibilidad de lectura de un cliente antiguo.

## 3. Las dos únicas adiciones `NOT NULL`

```sql
-- 20261016120000_ecf_dgii_company_habilitation
ALTER TABLE "ecf_evidences" ADD COLUMN "source" "ecf_evidence_source"
  NOT NULL DEFAULT 'MANUAL_DECLARATION';

-- 20261016180000_ecf_dgii_evidence_review
ALTER TABLE "ecf_evidences"
  ADD COLUMN "review_status" "ecf_evidence_review_status"
  NOT NULL DEFAULT 'PENDING';
```

Ambas llevan `DEFAULT`, así que se aplican sobre una tabla con filas sin
reescritura destructiva y sin dejar valores indefinidos. El `DEFAULT` es
**conservador**: una evidencia previa queda como «declaración manual» y «sin
revisar», que es exactamente lo que era: ninguna evidencia existente se
promueve a documento oficial por efecto de la migración.

## 4. La única huella en el POS

```sql
-- 20261015120000_sale_item_type_snapshot
ALTER TABLE "SaleItem" ADD COLUMN "item_type_snapshot" "product_item_type";
```

Nullable, sin `DEFAULT`, sin `NOT NULL`, sin *backfill*. Una fila creada por un
cliente antiguo queda con `NULL` y el módulo e-CF **se niega** a facturarla en
lugar de adivinar (ver `ECF_LEGACY_POS_COMPATIBILITY.md`). Es reversible con un
`DROP COLUMN` sin pérdida de datos del POS.

## 5. Reserva: índices no concurrentes

`CREATE INDEX` sin `CONCURRENTLY` toma un bloqueo de escritura sobre la tabla
mientras se construye. En las tablas `ecf_*` recién creadas es irrelevante. En
`ecf_evidences` deja de serlo si la tabla ya tiene volumen:

| Migración | Índice | Mitigación si la tabla es grande |
| --- | --- | --- |
| `..._ecf_dgii_company_habilitation` | `ecf_evidences_company_id_source_idx` | Crear con `CONCURRENTLY` en ventana de mantenimiento |
| `..._ecf_dgii_evidence_review` | `ecf_evidences_company_id_review_status_idx` | Igual |

**Recomendación:** medir el número de filas de `ecf_evidences` antes de aplicar
en un entorno con datos. Si es pequeño, no hay acción.

## 6. Deriva preexistente — NO se corrige

`prisma migrate diff` sigue reportando deriva **ajena a este trabajo**:

- 16 diferencias de `DEFAULT` en columnas UUID;
- el índice único parcial `telemetry_outbox_dedupe_key_key`.

**No se corrige** por decisión explícita de la misión. Motivo técnico: forzar
esos cambios generaría `DROP DEFAULT` y recreación de índices sobre tablas del
POS y de telemetría, riesgo desproporcionado frente al beneficio. El índice
parcial además **no es expresable** en el esquema de Prisma, así que una
migración automática lo eliminaría.

## 7. Cómo se validó

```text
npx prisma validate                     -> The schema ... is valid
npx prisma migrate status               -> 41 migrations found / Database schema is up to date!
pwsh scripts/ecf-test-db/run-tests.ps1  -> ISOLATION OK: historical UAT unchanged
```

`prisma migrate deploy` se aplicó **únicamente** sobre la base efímera de
pruebas. No se ejecutó `prisma db push` en ninguna base persistente.

## 8. Pendiente

| # | Pendiente | Riesgo |
| --- | --- | --- |
| M1 | Probar la migración sobre un esquema sintético grande (restauración desechable con volumen realista) | Medio |
| M2 | Medir filas de `ecf_evidences` antes de aplicar en un entorno con datos | Bajo |
| M3 | Decidir si la deriva preexistente se asume documentalmente o se aborda en una tarea propia | Medio |
