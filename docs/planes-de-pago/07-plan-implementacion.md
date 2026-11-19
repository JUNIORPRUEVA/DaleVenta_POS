# Plan de implementación definitivo

**Estado**: listo para ejecutar. Los documentos 00–06 son el qué; este es el cómo.
Base técnica: `origin/production-main` (`e6e7e8fc`). Rutas verificadas en esa rama.

---

## 1. Decisiones cerradas

| # | Decisión | Valor |
| --- | --- | --- |
| Catálogo | Básico 1.000 · Negocio 2.500 · Pro 3.500 · Empresa 5.000, mensual | Cerrado |
| Usuarios / productos | 2/100 · 5/400 · 10/1.000 · 20/5.000 | Cerrado |
| Almacenes | 1 · 1 · 5 · 10 (multi-almacén solo Pro y Empresa) | Cerrado |
| Funciones | Todo incluido llega **apagado**; excepciones: inventario y módulo de almacenes | Cerrado |
| e-CF | Bloqueada en Básico; incluida desde Negocio; cupo interno 300/1.500/5.000 | Cerrado |
| Activación | Al subir comprobante, **ACTIVE al instante**, pago `UNCONFIRMED` interno | Cerrado |
| Aviso | WhatsApp Cloud API (plantillas) al 829-436-3936 con el comprobante | Cerrado |
| Recordatorios | 5 días y 1 día antes, con instrucciones y referencia | Cerrado |
| Renovación | Automática: suma al vencimiento si está activo; empieza hoy si venció | Cerrado |
| Acceso | Planes siempre visible; al vencer solo Planes + Soporte; bloqueado fuera | Cerrado |
| CRM | Mismos botones + motivo obligatorio; excepciones desde **Editar** | Cerrado |
| Caja abierta | Se permite cerrar caja y sincronizar offline; se bloquean ventas nuevas | Cerrado |
| Cuenta bancaria | Se configura en el servidor; si falta, la app dice «contacta soporte» | Cerrado |

## 2. Prerrequisitos (antes de escribir código)

| # | Requisito | Bloquea |
| --- | --- | --- |
| 1 | **Usar la rama `agent/planes-de-pago-impl-20261116`** en `C:\src\fullpos-planes-de-pago-impl` (ya creada desde `origin/production-main`) | Todo |
| 2 | Variables `LICENSE_WA_TOKEN`, `LICENSE_WA_PHONE_NUMBER_ID`, `LICENSE_WA_VERSION`, `LICENSE_WA_TEMPLATE_LANG`, `LICENSE_ADMIN_WHATSAPP` | Avisos |
| 3 | Plantillas aprobadas en Meta: `licencia_por_vencer_5d`, `licencia_por_vencer_1d`, `licencia_pago_por_verificar` | Avisos |
| 4 | Cuenta bancaria única configurada (`LICENSE_BANK_*`) | Paso de pago |
| 5 | UAT de licencias con base aislada | Pruebas e2e |

> Los avisos y la cuenta bancaria **no bloquean** la activación: la app funciona sin ellos.

## 3. Base de datos (Prisma)

### Nuevas tablas

| Tabla | Campos clave |
| --- | --- |
| `LicensePlan` | `code` único, `name`, `version`, `monthlyPrice`, `maxUsers`, `maxProducts`, `maxWarehouses`, `multiWarehouse`, `wholesale`, `uom`, `ecf`, `taxes`, `ecfMonthlyQuota`, `active` |
| `LicensePaymentOrder` | `companyId`, `planCode`, `catalogVersion`, `currency` (DOP), `amount`, `months`, `periodStart`, `periodEnd`, `status`, `reference` único, `expiresAt`, `createdByUserId`, `notes` |
| `LicensePaymentEvidence` | `orderId`, `channel`, `storageKey`, `originalName`, `mime`, `sizeBytes`, `sha256`, `status`, `notifiedAt`, `uploadedByUserId` · único `(companyId, sha256)` |
| `LicenseCompanyOverride` | `companyId` único, `extraUsers`, `extraProducts`, `extraWarehouses`, `allowEcf`, `allowTaxes`, `allowWholesale`, `allowUom`, `note`, `grantedBy`, `grantedAt`, `expiresAt` |
| `LicenseNotificationJob` | `companyId`, `kind`, `payload` (JSON), `status`, `attempts`, `lastError`, `scheduledAt`, `sentAt` |
| `LicenseReminderLog` | `companyId`, `kind`, `periodEndSnapshot`, `sentAt`, `status` · único `(companyId, kind, periodEndSnapshot)` |

### Enums

`LicenseOrderStatus` = `CREATED`, `AWAITING_TRANSFER`, `EVIDENCE_RECEIVED`, `UNCONFIRMED`, `SETTLED`, `REJECTED`, `CANCELLED`, `EXPIRED`.
`LicenseNotificationKind` = `ADMIN_EVIDENCE`, `REMINDER_5D`, `REMINDER_1D`.

### Cambios en `Company`

- `planCode String?` (además del enum `CompanyPlan`, que se mantiene sincronizado).
- `maxWarehouses Int?` (nuevo límite).
- `planCatalogVersion Int?`.

**Migración**: `prisma migrate dev --create-only`, revisar el SQL (sin `DROP`), aplicar. El catálogo se
siembra con un script idempotente (`prisma/seed-license-plans.ts`).

## 4. API (NestJS)

### 4.1 Política de acceso — lo primero

| Archivo | Cambio |
| --- | --- |
| `src/license/license.access.policy.ts` **(nuevo)** | `resolveAccess(company)` → `FULL` / `RESTRICTED` / `BLOCKED` con motivos |
| `src/license/license-access.guard.ts` **(nuevo)** | Guard global **fail-closed** con lista blanca: `auth`, `health`, `license`, `app-updates`, soporte |
| `src/auth/jwt.strategy.ts` | Quitar el `throw` por `BLOCKED`/`EXPIRED`/trial vencido; adjuntar `licenseAccess` |
| `src/auth/auth.service.ts` | `login` y `refresh` permiten licencia vencida; devuelven `licenseAccess` |
| `src/license/license.service.ts` | Cerrar autoservicio: `activateMyLicense`, `blockMyLicense`, `updateMyLimits` → solo puente administrativo |
| `src/settings/settings.service.ts` | Rechazar encender `ncfEnabled`/`taxEnabled`/mayoreo/UoM si el plan no lo incluye y no hay excepción |

### 4.2 Catálogo y órdenes

| Endpoint | Acceso | Qué hace |
| --- | --- | --- |
| `GET /license/plans` | **Público** (solo lectura) | Catálogo vigente; alimenta la app y la landing |
| `GET /license/payment-instructions` | Autenticado | Cuenta bancaria o `{ configured: false }` |
| `POST /license/orders` | Autenticado | Crea o reutiliza la orden abierta; importe y periodo del servidor |
| `GET /license/orders` | Autenticado | Órdenes de mi empresa |
| `POST /license/orders/:id/evidence` | Autenticado | Multipart; valida tipo real, tamaño, hash; guarda privado; **activa** |
| `GET /license/orders/:id/evidence/:evidenceId` | Autenticado | Descarga privada (dueño o administrador) |
| `POST /license/orders/:id/cancel` | Autenticado | Solo si `CREATED` y sin evidencia |

**Activación** (`license.activation.service.ts`, nuevo): aplica plan + cuotas + flags apagados,
`licenseStatus = ACTIVE`, `licenseExpiresAt` = suma o hoy, escribe notas, audita y encola el aviso.

### 4.3 Administración (reutilizando el puente CRM que ya existe)

**Verificado en `origin/production-main`**: ya existen
`GET /license/integrations/crm/capabilities`, `GET /license/integrations/crm/companies`,
`GET /license/integrations/crm/companies/:companyId` y
`POST /license/integrations/crm/:companyId/commands`, con acciones `update`, `suspend`, `reactivate`
y `revoke`, **`reason` obligatorio (5–500 caracteres)**, `operationId` (idempotencia),
`expectedVersion` y auditoría. **No hay que crear un panel nuevo ni botones nuevos.**

Lo que falta añadir a ese puente:

| Cambio | Detalle |
| --- | --- |
| Marcar el pago | Aceptar `paymentOrderId` + `paymentStatus` (`SETTLED` / `UNCONFIRMED` / `REJECTED`) dentro de `commands` |
| Lista de comprobantes | `GET /license/integrations/crm/orders?status=` y descarga autenticada de la evidencia |
| Excepciones | El `update` ya cambia límites; añadir `maxWarehouses` y los flags de funciones |
| Motivo | Ya es obligatorio en el puente: solo hay que **mapearlo** a la orden de pago |

### 4.4 WhatsApp Cloud API

| Archivo | Contenido |
| --- | --- |
| `src/license/notifications/meta-cloud.client.ts` **(nuevo)** | `sendTemplate({ to, name, lang, bodyParams, header? })` y `uploadMedia(buffer, mime, name)` |
| `src/license/notifications/license.templates.ts` **(nuevo)** | Tres plantillas y sus variables |
| `src/license/notifications/license-notifier.service.ts` **(nuevo)** | Encola y procesa `LicenseNotificationJob` con reintentos |
| `src/license/notifications/license-reminder.scheduler.ts` **(nuevo)** | Diario: 5 y 1 día antes; crea orden y encola aviso |

Reglas: **siempre plantilla** (fuera de la ventana de 24 h el texto libre falla), media subida a
`/media` y enviada por `id`, una sola vez por `(empresa, nivel, periodo)`, nunca bloquea por un fallo
de WhatsApp.

## 5. Flutter

| Archivo | Cambio |
| --- | --- |
| `lib/core/license/license_repository.dart` | `getPlans`, `paymentInstructions`, `createOrder`, `uploadEvidence`, `listOrders` |
| `lib/features/plans/` **(nuevo)** | `plans_screen.dart`, `plan_usage_card.dart`, `plan_compare.dart`, `checkout_sheet.dart`, `voucher_upload.dart`, `order_tracking.dart`, `data/plans_repository.dart` |
| `lib/core/routing/route_access.dart` + `app_router.dart` | Con `RESTRICTED`, solo Planes y Soporte |
| `lib/core/auth/auth_interceptor.dart` | No cerrar sesión por `LICENSE_RESTRICTED` |
| `lib/features/account/account_menu_screens.dart` | «Licencias» pasa a enlazar a Planes |
| `lib/features/auth/presentation/landing_screen.dart` | Quitar `_plans` hardcodeado; usar `GET /license/plans` |

La pantalla Planes incluye: plan actual, estado, vencimiento, días restantes, uso vs límite con aviso
al 80 %, funciones con su interruptor, «Ampliación autorizada», comparador y cambio de plan con el
aviso de que no se pierden datos.

## 6. Web (`website/`)

`src/config/site.ts`: precios **1.000 / 2.500 / 3.500 / 5.000**, Básico **sin** facturación
electrónica, Negocio **1 almacén**, Pro/Empresa «más uso». Se despliega junto con el catálogo del
servidor el mismo día.

## 2b. Migraciones y datos iniciales (cómo funciona de verdad)

Verificado en `apps/api/scripts/start-prod.sh` y `apps/api/Dockerfile`:

| Variable | Valor por defecto | Qué significa |
| --- | --- | --- |
| `RUN_MIGRATIONS` | **`true`** | Al arrancar el contenedor se ejecuta **`prisma migrate deploy` automáticamente**. **No hay que aplicar nada a mano.** |
| `PRISMA_SYNC_MODE` | `migrate` | Usa migraciones (correcto para producción). |
| `MIGRATION_STRICT` | **`false`** | ⚠ Si una migración falla, **la API arranca igual** y queda desincronizada. Para esta entrega conviene ponerlo en **`true`**. |
| `RUN_SEED` | **no definido** | El seed **no** se ejecuta solo. El catálogo hay que sembrarlo una vez. |

### Qué implica

1. **La migración no se escribe a mano**: el SQL de
   `20261116180000_license_plans_and_orders` se generó con `prisma migrate diff` comparando el esquema
   anterior con el nuevo. Solo crea estructuras nuevas.
2. Al desplegar, `migrate deploy` la aplica sola. Si se quiere garantía, poner `MIGRATION_STRICT=true`
   y revisar el log `[startup] migrations applied`.
3. **El catálogo necesita un seed una vez**:
   `npx ts-node --transpile-only -P tsconfig.scripts.json scripts/seed-license-plans.ts`.
   Es idempotente (upsert por `code`), así que puede repetirse sin duplicar.
   Alternativa: `RUN_SEED=true`, que ejecuta `prisma/seed.cjs` (también idempotente).
4. Si el catálogo está vacío, la API **no se rompe**: `LicensePlansService` registra un aviso al
   arrancar y `GET /license/plans` devuelve una lista vacía.

## 7. Orden de etapas

> **«Etapa» no es un pull request de GitHub.** Son pasos de trabajo en esta misma rama: se implementa,
> se prueba y se anota. Si algún día quieres revisarlos antes de integrar, se puede abrir un PR con
> las etapas que quieras.

| Etapa | Contenido | Depende | Riesgo | Estado |
| --- | --- | --- | --- | --- |
| **Etapa 0** | Worktree y rama desde `origin/production-main` + documentos | — | Bajo | ✅ hecha |
| **Etapa 1** | Esquema + catálogo + seed + `GET /license/plans` | Etapa 0 | Medio (migración) | ✅ hecha |
| **Etapa 2** | Política de acceso + guard + login/JWT + cerrar autoservicio + gate de funciones | Etapa 1 | **Alto** (autenticación) | ⏳ siguiente |
| **Etapa 3** | Órdenes + comprobantes privados + activación | Etapa 2 | Medio | ⏳ |
| **Etapa 4** | Pantalla Planes + navegación restringida | Etapa 3 | Medio | ⏳ |
| **Etapa 5** | Cloud API: cliente, plantillas, aviso al administrador, outbox | Etapa 3 | Medio | ⏳ |
| **Etapa 6** | Recordatorios 5d/1d + renovación automática | Etapa 5 | Medio | ⏳ |
| **Etapa 7** | CRM: extender el puente existente (marcar pago con motivo) | Etapa 3 | Bajo | ⏳ |
| **Etapa 8** | Web: precios y beneficios publicados | Etapa 1 | Bajo | ⏳ |
| **Etapa 9** | Endurecimiento: retención, límite de subidas, logs sin secretos | Etapa 7 | Bajo | ⏳ |

## 8. Pruebas obligatorias

**API**
- `licencia-activacion.e2e-spec.ts`: subir comprobante → `ACTIVE`, cuotas del plan, flags apagados.
- `licencia-acceso.e2e-spec.ts`: vencido entra, `POST /sales` 403 `LICENSE_RESTRICTED`, `GET /license` 200; activo sin cambios; bloqueado 401.
- `licencia-evidencias.e2e-spec.ts`: PDF falso rechazado, duplicado por hash no activa, tamaño, descarga solo del dueño.
- `licencia-renovacion.e2e-spec.ts`: activo suma un mes; vencido empieza hoy; dos comprobantes distintos suman dos meses.
- `licencia-recordatorios.spec.ts`: envía 5d y 1d una sola vez, en horario, sin teléfono no envía.
- `licencia-wa.spec.ts`: payload de plantilla correcto, cabecera con media id, error de API no altera licencia.
- `npm run test:security`, `npm run test:tenant`, `npm run test:e2e`.

**Flutter**
- Widget tests de los pasos de Planes (elegir, subir, seguimiento, cambio de plan con el mensaje).
- `flutter analyze` y `flutter test`.

**Visual (obligatorio antes de dar por terminado)**
- Capturas reales de Planes en 390×844, 834×1112 y 1264×681, con un comprobante subido de verdad.

## 9. Riesgos

| Riesgo | Mitigación |
| --- | --- |
| El guard de acceso rompe apps antiguas | Código de error estable + versión mínima en `app-updates` |
| Migración destructiva | `--create-only`, revisar SQL, backups y UAT |
| Plantillas sin aprobar | El flujo funciona sin WhatsApp; aviso in-app |
| Comprobante en carpeta pública | Ruta privada + endpoint autenticado (nunca `/uploads`) |
| Cliente se autoconcede licencia | Cerrar autoservicio en PR-2 |
| Caja abierta al vencer | Prueba funcional explícita en PR-2 |

## 10. Definición de terminado

1. Las pruebas de §8 pasan y están anotadas en `.project-memory-local/TESTS-LOCAL.md`.
2. Evidencia visual de Planes.
3. Ninguna regresión en el flujo de licencia vigente.
4. Web y catálogo con los mismos precios.
5. Documentación actualizada en `docs/planes-de-pago/`.

## 11. Fuera de alcance de esta entrega

- Conciliación automática con extracto bancario o API del banco.
- Prorrateo de meses fraccionados.
- Emisión de comprobantes fiscales por la suscripción (requiere criterio contable/DGII).
- Migración masiva de clientes históricos al nuevo catálogo.
