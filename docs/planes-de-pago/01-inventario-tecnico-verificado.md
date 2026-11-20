# Inventario técnico verificado — FullPOS (base `6b3e38ed`)

**Alcance**: worktree `C:\src\fullpos-planes-de-pago-20261116`, rama
`agent/planes-de-pago-20261116`, base `production-main` @ `6b3e38ed`.
Todo lo marcado **HECHO** se comprobó leyendo el código de esta rama.

> **Aviso de base (verificado 2026-11-16)**: la `production-main` local está **399 commits por
detrás** de `origin/production-main` (`e6e7e8fc`) y **no contiene `website/`**. La web publicada vive
en `origin/production-main`. Antes de escribir código hay que recrear la rama desde ahí.

Evidencia usada (reproducible):

```powershell
$wt = 'C:\src\fullpos-planes-de-pago-20261116'
Get-ChildItem "$wt\apps\api\src\license"
Get-ChildItem "$wt\apps\api\src" -Recurse -Include *.ts |
  Select-String 'assertCompanyCanUseApp|LicenseStatus|licenseExpiresAt'
Get-Content "$wt\apps\api\prisma\schema.prisma" | Select-String 'enum LicenseStatus','enum CompanyPlan','model Company'
Get-Content "$wt\apps\api\src\auth\jwt.strategy.ts"
Get-Content "$wt\apps\api\src\license\license.service.ts"
Get-ChildItem "$wt\apps\fulltech_app\lib" -Recurse -Filter *.dart |
  Select-String 'Licencias|license'
```

---

## 1. API (NestJS) — lo que existe hoy

### Módulo de licencia — HECHO

`apps/api/src/license/` contiene exactamente cuatro archivos:
`license.controller.ts`, `license.module.ts`, `license.service.ts`, `license.service.spec.ts`.

| Endpoint | Autorización | Efecto |
| --- | --- | --- |
| `GET /license` | JWT + Roles | Devuelve el estado de licencia de la empresa del token |
| `POST /license/activate` | JWT + Roles + **admin de la empresa** | **Autoservicio**: activa la licencia de la propia empresa aceptando `maxUsers`, `maxProducts` y `expiresAt` del cuerpo |
| `POST /license/block` | JWT + Roles + **admin de la empresa** | **Autoservicio**: bloquea la propia licencia |
| `PATCH /license/limits` | JWT + Roles + **admin de la empresa** | **Autoservicio**: cambia límites y vencimiento |
| `GET /license/admin/companies` | Header `x-license-admin-secret` | Listado para el backoffice |
| `GET /license/admin/:companyId/usage` | Header `x-license-admin-secret` | Uso de recursos (productos, usuarios, almacenes, dispositivos) |
| `GET /license/admin/:companyId` | Header `x-license-admin-secret` | Estado + últimos 25 registros de auditoría |
| `POST /license/admin/:companyId/activate` | Header secreto + `x-license-admin-actor` | Activación desde el puente administrativo |
| `POST /license/admin/:companyId/block` | Header secreto + actor | Bloqueo administrativo |
| `PATCH /license/admin/:companyId` | Header secreto + actor | Actualización de licencia |
| `DELETE /license/admin/:companyId` | Header secreto + actor | Baja/limpieza de licencia |
| `DELETE /license/admin/:companyId/permanent` | Header secreto + actor | Borrado permanente |

> **Hallazgo H-01 (crítico de negocio)**: hoy cualquier usuario **administrador de la empresa** puede
> llamar a `POST /license/activate` y `PATCH /license/limits` con su propio JWT y concederse
> usuarios, productos y fecha de vencimiento. El informe da por hecho que la activación la decide la
> administración comercial; **el código actual no lo impone**. La pantalla «Planes» **no puede**
> reutilizar estos endpoints tal cual.

### Puntos de bloqueo por licencia — HECHO

| Archivo | Qué hace |
| --- | --- |
| `apps/api/src/auth/jwt.strategy.ts` | En cada petición autenticada llama a `assertCompanyCanUseApp(companyId)`; además lanza `UnauthorizedException('Licencia no activa')` si `licenseStatus` es `BLOCKED`/`EXPIRED`, si el trial venció o si `licenseExpiresAt` ya pasó |
| `apps/api/src/auth/auth.service.ts` | `login` y `refresh` llaman a `assertCompanyCanUseApp(...)` antes de emitir tokens |
| `apps/api/src/onboarding/onboarding.service.ts` | Comprueba la licencia durante el alta |
| `apps/api/src/usage-telemetry/usage-telemetry.service.ts` | Lee el estado de licencia para telemetría |
| `apps/api/src/backups/backup-extractor.ts` | Consulta el estado de licencia |
| `apps/api/src/license/license.service.ts` | `assertCanCreateUser` / `assertCanCreateProduct` aplican cuotas en transacción (`PLAN_LIMIT_REACHED`) |

Consecuencia **HECHA**: con la licencia vencida el cliente recibe **401** (no 403) y **no puede ni
autenticarse**; el flujo «vence, permanece dentro y paga» **no existe**. Además, el propio informe
advierte que un 401 se confunde fácilmente con «contraseña incorrecta» en el cliente.

### Cuotas que sí se aplican — HECHO

`getAdminCompanyUsage()` devuelve:

| Recurso | Aplicado | Semántica |
| --- | --- | --- |
| `products` | **sí** | `active_non_archived_products` |
| `users` | **sí** | `active_non_blocked_users_or_active_memberships` |
| `warehouses` | **no** | `enforced: false`, `supported: false` |
| `devices` | **no** | `enforced: false`, `supported: false` |

Esto confirma el punto del informe §3: **los límites anunciados de almacenes (y e-CF) no están
implementados**. La pantalla de Planes no puede prometer límites que el servidor no aplica.

### Puente administrativo — HECHO (con riesgo)

`assertAdminSecret()` exige `LICENSE_ADMIN_SECRET` (config o `process.env`) y **si no está
configurado responde 403**. Es un **secreto estático en cabecera**, sin timestamp, nonce ni firma del
cuerpo: exactamente el riesgo que el informe pide reforzar de forma compatible y gradual.

## 2. Base de datos (Prisma) — lo que existe hoy

**HECHO** — `apps/api/prisma/schema.prisma`:

```prisma
enum LicenseStatus { TRIAL  ACTIVE  BLOCKED  EXPIRED }
enum CompanyPlan   { STANDARD  ENTERPRISE }
```

Campos de `Company` relevantes: `plan`, `licenseStatus`, `licenseKey`, `trialStartedAt`,
`trialEndsAt`, `licenseActivatedAt`, `licenseExpiresAt`, `licenseBlockedAt`, `licenseNotes`,
`maxUsers` (por defecto **2**), `maxProducts` (por defecto **100**).

- El **trial es de 7 días** (`auth.service.ts`: `trialEndsAt = now + 7 días`).
- Migraciones en `apps/api/prisma/migrations`: **29** (contadas en esta base).
- Modelos de licencia comercial: **solo** los campos de `Company` + `CompanyLicenseAuditLog`.

**HECHO — no existe** en FullPOS ninguna tabla de:
órdenes de pago, comprobantes, suscripciones, pagos, conciliaciones ni outbox de activación.
Las tablas con «Order/Payment/Invoice» del esquema (`PurchaseOrder`, `PurchaseInvoice`,
`SaleCreditPayment`, `DepositOrder`, `ServiceOrder`) son **operación del negocio del cliente**, no
cobros de la licencia. **No confundirlas.**

## 3. Cliente Flutter — lo que existe hoy

| Archivo | Contenido |
| --- | --- |
| `apps/fulltech_app/lib/core/license/license_repository.dart` | `licenseRepositoryProvider`, `licenseStatusProvider` (`FutureProvider<LicenseStatusModel>`), `getLicense()`, `activate()`, `block()`, `updateLimits()`, `LicenseStatusModel` |
| `apps/fulltech_app/lib/features/account/account_menu_screens.dart` | `AccountLicensesScreen` + `_LicensePlanCard` con plan, estado, límites, vigencia y fecha |
| `apps/fulltech_app/lib/core/api/api_routes.dart` | Rutas de licencia usadas por el repositorio |
| `apps/fulltech_app/lib/core/auth/auth_interceptor.dart`, `core/lifecycle/app_lifecycle_coordinator.dart` | Reaccionan al bloqueo/expiración y a la sesión |

La pantalla actual **muestra** el estado y permite operaciones de administración local; **no** hay
catálogo de planes, orden, transferencia, subida de comprobante ni seguimiento.

### Catálogo de precios embebido en el cliente — HECHO (riesgo de triple verdad)

`apps/fulltech_app/lib/features/auth/presentation/landing_screen.dart`, constante `_plans`
(líneas ~2481-2519):

| Plan | Total mostrado | Equivalente mensual | Límites anunciados |
| --- | --- | --- | --- |
| Básico | RD$3,000 | RD$1,000 | 100 productos · 2 usuarios · **1 almacén** · 1 caja |
| Negocio | RD$4,500 | RD$1,500 | 400 productos · 3 usuarios · **2 almacenes** · 2 cajas |
| Pro | RD$7,500 | RD$2,500 | 1,000 productos · 5 usuarios · **3 almacenes** · 3 cajas |

Consecuencias verificadas:

1. Es una **tercera fuente de precios** (además de la migración 052 y del sitio Astro).
2. Los totales son **3 × mensual**: la app ya comunica el mínimo de tres meses que el propietario
   quiere sustituir por contratación mensual.
3. Anuncia **almacenes y cajas** que el servidor **no** aplica (`enforced: false` en
   `getAdminCompanyUsage`).

## 4. Lo que el informe afirma y aquí no se ha podido verificar

| Afirmación del informe | Estado en esta rama |
| --- | --- |
| Catálogo del sitio Astro divergente (2.000/3.000/4.500) | **PENDIENTE**: el sitio no está en este repositorio |
| 53 migraciones y ~78 tablas en `FULLTECHPOS_BAKEND_LICENCIA` | **PENDIENTE**: no se auditó esa base (su árbol tiene cambios locales sin commitear) |
| `company_subscriptions`, `subscription_payments`, `license_payment_orders`, `paypal_orders` existen allí | **PENDIENTE**: no verificado en esta rama |
| 54 controladores que revisar | **PENDIENTE**: hay que censarlos aquí; no se ha ejecutado el censo |
| Comportamiento de caja abierta y cola offline al vencer | **PENDIENTE**: requiere prueba funcional, no lectura |
| Proveedor de WhatsApp (Cloud API / Evolution) | **PENDIENTE**: no verificado. En `apps/api/src` **no hay** módulo `whatsapp` (sí hay scripts `whatsapp:*` en `package.json`, que no prueban un canal activo) |
| Permisos granulares del admin sin aplicar (`x-session-id`) | **HIPÓTESIS** del informe; aplica al repositorio administrativo |

## 5. Hallazgos que condicionan el plan

| ID | Hallazgo | Impacto | Fase que lo resuelve |
| --- | --- | --- | --- |
| H-01 | El admin de la empresa puede autoconcederse licencia (`/license/activate`, `/license/limits`) | Alto: el cliente podría darse años o límites infinitos | F1/F2 |
| H-02 | Licencia vencida ⇒ **401** en login y en cada petición | Bloquea todo el flujo de pago | F1 |
| H-03 | El trial vencido cuenta como no usable ⇒ expulsa | Igual que H-02 | F1 |
| H-04 | Almacenes y dispositivos no se aplican aunque se anuncien | Publicidad de límites inexistentes | F1 (decidir) |
| H-05 | Secreto de administración estático en cabecera | Riesgo de suplantación del puente | F5 |
| H-06 | No existe modelo de orden/comprobante/conciliación | Todo el expediente de pago está por construir | F2 |
| H-07 | El cliente Flutter trata códigos de licencia como cierre de sesión | Expulsa al vencido en vez de llevarlo a Planes | F1/F3 |
| H-08 | Cola offline y caja abierta al vencer | Riesgo de pérdida de ventas capturadas | F1 (prueba) |
| H-09 | Catálogo de precios hardcodeado en `landing_screen.dart` (3× mensual, almacenes/cajas no aplicados) | Tercera verdad de precios y promesa de límites inexistentes | F3 |

> El detalle de qué dice la web publicada y en qué se diferencia de la app está en
> [`04-catalogo-oficial-planes.md`](./04-catalogo-oficial-planes.md).

## 6. Criterio de verificación para esta rama

- `flutter analyze` y `flutter test` en `apps/fulltech_app`.
- `npm run test` / `npm run test:e2e` en `apps/api` (según exista el script en esta base; se
  confirmará al abrir la Fase 1).
- Ninguna fase se marca `VERIFICADO` sin comando y resultado anotados en
  `.project-memory-local/TESTS-LOCAL.md`.
