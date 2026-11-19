# 18 — Preparación del despliegue (sin desplegar)

Fecha: 2026-11-19
Estado: **preparado y probado en local**. No se ha desplegado nada, ni se ha
tocado la base de producción.

## 1. La garantía que se pide

> Ningún cliente que hoy trabaja puede quedarse fuera ni perder funciones.

Eso se traduce en cuatro reglas que el código ya cumple:

| Regla | Cómo se cumple |
| --- | --- |
| Sigue **activo** | El backfill **no toca** `license_status` ni `status`. |
| Conserva **sus meses** | El backfill **no toca** `license_expires_at` ni `license_activated_at`. |
| Conserva sus **límites** | Lo que el plan Básico no cubre se concede como excepción (usuarios, productos, almacenes). |
| Conserva sus **funciones** | e-CF, impuestos, mayoreo, unidades de medida y multi-almacén se conservan como excepción. |

Y una regla de seguridad: si el script detecta que la migración **recortaría**
algo de una empresa, **no la toca** y la marca como `SALTADA` para revisarla.

## 2. Qué se despliega

**API** (`apps/api`):

- Migración aditiva `20261119200000_license_override_multiwarehouse`
  (una columna con `DEFAULT false`; no cambia ninguna concesión existente).
- `LicenseEntitlementsService` y el CRM aceptan la excepción de multi-almacén.
- Tres utilidades nuevas:
  - `scripts/deploy-preflight.ts` — comprobaciones previas (no escribe).
  - `scripts/plan-migration-check.ts` — radiografía de licencias (no escribe).
  - `scripts/backfill-plan-basico.ts` — migración de clientes (simula por defecto).

**App** (`apps/fulltech_app`): catálogo rediseñado y pantalla de demo. No cambia
el contrato: sigue llamando a `/license`, `/license/plans`, `/license/orders`,
`/license/orders/quote`, `/license/payment-instructions`, `/license/plan-requests`,
`/license/orders/:id/cancel` y `/license/orders/:id/evidence`. Todas existen en
`license.controller.ts`.

## 3. Orden exacto del despliegue

Todo se ejecuta **desde `apps/api`** y con el entorno del servidor cargado
(`DATABASE_URL`, `JWT_SECRET`, `LICENSE_*`).

### Paso 0 — Copia de seguridad

```bash
pg_dump "$DATABASE_URL" --format=custom --file=/backups/pre-planes-$(date +%Y%m%d-%H%M).dump
```

Sin este archivo no se sigue.

### Paso 1 — Comprobaciones previas (solo lectura)

```bash
npm run license:preflight
```

Debe salir **0 errores**. Los avisos se revisan uno a uno; los más importantes:

- `LICENSE_BANK_ACCOUNT` sin definir o con menos de 4 dígitos → los comprobantes
  quedarían todos en revisión.
- `LICENSE_EVIDENCE_DIR` no escribible → no se pueden guardar comprobantes.
- `N empresa(s) ACTIVO sin plan` → es lo que migra el paso 3.

### Paso 2 — Migraciones y catálogo

El contenedor aplica las migraciones al arrancar (`RUN_MIGRATIONS=true`). Para
hacerlo a mano y ver el resultado:

```bash
npx prisma migrate deploy
npm run license:seed
```

`license:seed` es idempotente: si los planes ya existen, solo actualiza precios y
límites del catálogo. **No** toca empresas.

> No activar `RUN_SEED=true`: ese seed es el general de la aplicación y no hace
> falta para los planes.

### Paso 3 — Migrar a los clientes activos (simulación primero)

```bash
npm run license:backfill
```

Esto **no escribe nada**: imprime, empresa por empresa, a qué plan iría, hasta
cuándo tiene pagado y qué excepciones se le concederían. Revisar la lista y,
sobre todo, que ninguna salga como `SALTADA`.

Cuando la lista cuadre:

```bash
npm run license:backfill -- --apply --operator=deploy-2026-11-19
```

Qué hace por cada empresa **activa sin plan**:

1. Le asigna `plan_code = 'basico'` y la versión del catálogo.
2. **No toca** el estado, el vencimiento, los límites ni los interruptores de la
   empresa.
3. Si la empresa ya usaba más de lo que da Básico, crea una **excepción**
   (`license_company_overrides`) con la diferencia y el motivo. Sin esto, pasar
   de «sin plan» a Básico le apagaría la facturación electrónica o los impuestos.
4. Deja el rastro en `company_license_audit_logs`
   (`action = license.plan.catalog_backfill`) con el antes y el después.

Es **idempotente**: la segunda ejecución no encuentra empresas y no cambia nada.

Para una sola empresa, antes de lanzarlo con todas:

```bash
npm run license:backfill -- --company=<slug> --apply
```

### Paso 4 — Verificación posterior

```bash
npm run license:check
```

Debe quedar en **0 hallazgos** (o solo `ACTIVA_SIN_VENCIMIENTO`, si hay licencias
perpetuas conocidas):

- Ninguna empresa activa sin plan.
- Ningún plan fuera del catálogo.
- Ninguna función encendida sin cobertura.
- Nadie por encima de sus límites.

### Paso 5 — Humo funcional

1. Abrir la app y entrar con un cliente que estaba activo: debe ver el mismo
   estado, el mismo vencimiento y las mismas funciones.
2. Ir a **Planes**: debe aparecer «Plan actual» con el plan Básico y los usos.
3. Abrir **Transferencia**: debe mostrar los datos bancarios (si
   `LICENSE_BANK_ACCOUNT` está configurado).
4. Entrar con una empresa en demo: debe decir «Aún no tienes un plan activo».

### Paso 6 — App

```bash
cd ../fulltech_app
flutter build windows --release --dart-define=API_BASE_URL=https://daleventapos-backend.gcdndd.easypanel.host
flutter build web --release
```

`API_BASE_URL` explícito evita el error de un build que cae en producción sin
querer (o al contrario).

## 4. Rollback

### Si falla el despliegue de la API

La migración es **aditiva**: la API anterior funciona con la columna nueva
presente. Basta con volver a la imagen anterior; no hay que revertir la base.

### Si hay que deshacer la migración de planes

La auditoría dice exactamente qué se hizo, así que el rollback es quirúrgico:

```sql
-- 1) Empresas migradas por este backfill
SELECT company_id, action, reason, created_at
FROM company_license_audit_logs
WHERE action = 'license.plan.catalog_backfill'
ORDER BY created_at DESC;

-- 2) Devolver esas empresas a «sin plan»
UPDATE companies c
SET plan_code = NULL, plan_catalog_version = NULL
FROM company_license_audit_logs l
WHERE l.company_id = c.id
  AND l.action = 'license.plan.catalog_backfill'
  AND l.actor_email = 'deploy-2026-11-19';

-- 3) Retirar SOLO las excepciones creadas por el backfill
DELETE FROM license_company_overrides
WHERE granted_by = 'deploy-2026-11-19';
```

Los registros de auditoría **no se borran** (son append-only); queda constancia
de la ida y de la vuelta.

### Nunca

- `prisma migrate reset` en producción.
- `db push` en producción (`ALLOW_PRODUCTION_DB_PUSH` está bloqueado a propósito).
- Borrar `license_company_overrides` de concesiones que no creó este despliegue:
  filtrar siempre por `granted_by`.

## 5. Variables de entorno que la licencia necesita

| Variable | Valor esperado | Si falta |
| --- | --- | --- |
| `DATABASE_URL` | cadena de PostgreSQL | la API no arranca |
| `JWT_SECRET` | ≥ 32 caracteres, distinto de `change-me` | sesiones inseguras |
| `LICENSE_BANK_ACCOUNT` | cuenta destino, ≥ 4 dígitos | comprobantes siempre en revisión |
| `LICENSE_BANK_ACCOUNT_TYPE` | texto que ve el cliente | hueco en la pantalla de pago |
| `LICENSE_EVIDENCE_DIR` | ruta escribible | no se guardan comprobantes |
| `LICENSE_RECEIPT_UTC_OFFSET_HOURS` | `-4` (RD) | el tope diario cuenta en otra zona |
| `CRM_LICENSE_MANAGEMENT_ENABLED` | `true` para gestionar desde el CRM | CRM sin licencias |
| `LICENSE_WA_DRY_RUN` | `false` para avisos reales | avisos simulados |
| `RUN_MIGRATIONS` | `true` | migraciones no aplicadas |
| `RUN_SEED` | **vacío** | seed general en cada arranque |

`license:preflight` comprueba todas menos el tipo de cuenta y el offset.

## 6. Lo que se probó en local (y lo que no)

| Comprobación | Resultado |
| --- | --- |
| Migración aplicada en `planes_local` | 90/90, esquema al día |
| `tsc -p tsconfig.build.json` | Sin errores |
| Jest de `src/license` | **132 pruebas en 19 suites, todas en verde** |
| `license:backfill` (simulación) | 2 empresas detectadas |
| `license:backfill --apply` en local | 2 migradas, excepciones +19 usuarios y +900 productos |
| Estado, vencimiento, uso y límites antes/después | **Idénticos** |
| Segunda ejecución | 0 empresas: **idempotente** |
| `license:check` | 0 hallazgos de cobertura; solo avisos de «sin vencimiento» (datos UAT) |
| `license:preflight` | 8 correctas, 5 avisos propios del entorno local, 0 errores |
| Contrato app ↔ API | Las 9 rutas que usa la app existen en el controlador |

**No probado**:

- Contra la base de producción (no hay acceso desde aquí).
- Con clientes reales que tengan e-CF, impuestos o multi-almacén activados: el
  script los compensa, pero el caso no está reproducido con datos reales.
- La app instalada en Windows/Android con la nueva versión.

## 7. Decisiones que necesito confirmadas antes de desplegar

1. **Plan destino**: el script usa `basico`. Si se quiere otro, `--plan=<code>`
   (el catálogo tiene `negocio`, `pro` y `empresa`).
2. **Empresas en prueba**: por defecto el backfill **solo** toca `ACTIVE`. Con
   `--include-trial` también migra las que están en demo.
3. **Excepciones**: se crean sin caducidad para no interrumpir. Conviene revisar
   en enero cuáles siguen teniendo sentido cuando esos clientes renueven.
4. **`LICENSE_BANK_ACCOUNT`**: hay que confirmar la cuenta real antes del humo.
