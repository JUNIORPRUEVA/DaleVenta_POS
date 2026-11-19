# Implementación ejecutada (Etapas 2–8)

Fecha: 2026-11-16 · Rama `agent/planes-de-pago-impl-20261116` (worktree `C:\src\fullpos-planes-de-pago-impl`)
Catálogo y decisiones: [`05-definicion-tecnica-de-planes.md`](./05-definicion-tecnica-de-planes.md) ·
Proceso: [`06-proceso-de-activacion.md`](./06-proceso-de-activacion.md)

---

## 1. Qué quedó implementado

| Etapa | Estado | Dónde |
| --- | --- | --- |
| 1 · Esquema, catálogo y seed | ✅ | `prisma/schema.prisma`, `migrations/20261116180000_license_plans_and_orders`, `scripts/seed-license-plans.ts`, `license/plans/license-plans.service.ts` |
| 2 · Acceso, guard y gate de funciones | ✅ | `license/license.access.policy.ts`, `license/license-access.interceptor.ts`, `auth/jwt.strategy.ts`, `license/plans/license-entitlements.service.ts`, `settings/settings.service.ts` |
| 3 · Órdenes, comprobantes y activación | ✅ | `license/orders/license-orders.service.ts`, `license/orders/license-activation.service.ts`, `license/orders/license-evidence.storage.ts`, `license/license.controller.ts` |
| 4 · Pantalla Planes (Flutter) | ✅ | `apps/fulltech_app/lib/features/plans/` (`data/plans_repository.dart`, `presentation/plans_screen.dart`), `core/api/api_routes.dart`, `core/routing/routes.dart`, `core/routing/app_router.dart`, `core/license/license_repository.dart` |
| 5 · WhatsApp Cloud API | ✅ | `license/notifications/meta-cloud.client.ts`, `license.templates.ts`, `license-notifier.service.ts` |
| 6 · Recordatorios 5d / 1d | ✅ | `license/notifications/license-reminder.scheduler.ts` |
| 7 · Puente del CRM | ✅ | `license/crm-license.service.ts`, `crm-license.controller.ts` + `FULLTECHPOS_BAKEND_LICENCIA/backend/routes/serviceDaleventasRoutes.js` |
| 8 · Web (precios y módulos) | ✅ | `website/src/config/site.ts`, `pages/precios.astro`, `pages/index.astro`, `pages/funciones.astro` |
| 9 · Endurecimiento | ◐ parcial | comprobante privado, tope 10 MB, 3 subidas/día, hash único, sin claves en respuestas |

### Cambios de la última revisión (2026-11-16, tarde)

- **Usuarios por plan**: **1 / 3 / 4 / 7** (antes 2 / 5 / 10 / 20). Aplicado en el catálogo, el seed,
  la web y las pruebas. El plan de 1.000 lleva **1** usuario, el de 2.500 **3**, el de 3.500 **4** y el
  de 5.000 **7**.
- **Pantalla Planes** (Flutter): tarjetas rectas (sin radio) con el plan destacado, precio del
  servidor, funciones incluidas y **no incluidas** (tachadas), estado y uso con aviso al 80 %,
  referencia de pago con botón de copiar, datos bancarios, subida de comprobante y historial. Se
  entra por `/planes` y por `/licencias`.
- **Diseño recto en el CRM**: `CrmButton` ya no lleva radio y la lista de licencias usa filas y chips
  rectos.
- **CRM ordenado por plan**: la lista ordena básico → negocio → pro → empresa y cada fila muestra el
  plan del negocio (`planCode` viaja en la proyección de APPYRA).

## 2. Reglas aplicadas (contrato del producto)

- **La licencia vencida no expulsa**: `JwtStrategy` ya no responde 401 por vencimiento. Se adjunta
  `licenseAccess` (`FULL` / `RESTRICTED` / `BLOCKED`) y `LicenseAccessInterceptor` falla cerrado salvo
  en `/auth`, `/health`, `/license`, `/support`, `/notifications`, `/app-updates`.
- **Con `RESTRICTED`** solo se permite leer y, para escribir, renovar (`/license/orders`) o pedir soporte.
  `/license/admin/*` queda fuera siempre.
- **Bloqueada = 401** (decisión humana, reversible con «Reactivar»).
- **Al subir el comprobante se activa al instante**; el pago queda `UNCONFIRMED` (interno) y se encola
  el aviso al administrador.
- **Renovación**: si la licencia sigue vigente el periodo **suma** al vencimiento; si venció, empieza hoy.
- **Todo lo opcional llega apagado**; si el plan no incluye una función, se apaga al activar.
- **El plan decide qué se puede encender**: `SettingsService` rechaza encender e-CF, impuestos, mayoreo
  o unidad de medida cuando el plan (y sus excepciones) no lo incluye. Apagar siempre se permite.
- **Almacenes**: el módulo está activo en los cuatro planes; lo que limita es `maxWarehouses`
  (1 / 1 / 5 / 10) y se comprueba **dentro de la transacción** al crear.
- **Excepciones** (`LicenseCompanyOverride`): suman cuotas o habilitan una función, con nota, quién la
  concedió y caducidad opcional. Una excepción caducada se ignora.

## 3. Endpoints añadidos

Autenticados (empresa):

| Método | Ruta | Qué hace |
| --- | --- | --- |
| GET | `/license/access` | Acceso efectivo para la app |
| GET | `/license/payment-instructions` | Cuenta bancaria; `configured:false` si no existe |
| POST | `/license/orders` | Crea o reutiliza la orden abierta |
| GET | `/license/orders` | Órdenes de la empresa |
| POST | `/license/orders/:id/cancel` | Cancela si no hay comprobante |
| POST | `/license/orders/:id/evidence` | Multipart; valida firma real, tamaño, hash y **activa** |
| GET | `/license/orders/:id/evidence/:evidenceId` | Descarga privada del comprobante |

Público: `GET /license/plans` (catálogo).

Puente administrativo (`x-license-admin-secret`):

| Método | Ruta | Qué hace |
| --- | --- | --- |
| GET | `/license/integrations/crm/orders?companyId=&status=` | Órdenes con comprobantes |
| GET | `/license/integrations/crm/orders/:orderId/evidence/:evidenceId` | Descarga para el administrador |
| POST | `/license/integrations/crm/companies/:companyId/overrides` | Concede excepción |
| DELETE | `/license/integrations/crm/companies/:companyId/overrides` | Retira excepción |
| POST | `/license/integrations/crm/:companyId/commands` | Ahora acepta `paymentOrderId` + `paymentStatus` y `fields.maxWarehouses` |

APPYRA los reexpone como `GET /api/service/daleventas/licenses/:id/orders`,
`POST|DELETE /api/service/daleventas/licenses/:id/overrides` y acepta los campos de pago en `commands`.

## 4. Variables de entorno

| Variable | Obligatoria | Uso |
| --- | --- | --- |
| `LICENSE_BANK_NAME` / `_ACCOUNT` / `_ACCOUNT_TYPE` / `_HOLDER` / `_HOLDER_TAX_ID` | No | Datos de transferencia. Sin ellos la app dice «contacta soporte» |
| `LICENSE_EVIDENCE_DIR` | No | Directorio **privado** de comprobantes (por defecto `storage/license-evidence`) |
| `LICENSE_WA_TOKEN` / `LICENSE_WA_PHONE_NUMBER_ID` | No | WhatsApp Cloud API oficial |
| `LICENSE_WA_VERSION` / `LICENSE_WA_TEMPLATE_LANG` | No | Por defecto `v21.0` y `es` |
| `LICENSE_ADMIN_WHATSAPP` | No | Destino de los avisos (por defecto `18294363936`) |
| `CRM_LICENSE_MANAGEMENT_ENABLED` | Sí para el puente | `true` habilita escritura desde el CRM |

Sin WhatsApp configurado los avisos quedan `SKIPPED`: **la activación no depende de WhatsApp**.

Plantillas que deben estar aprobadas en Meta: `licencia_pago_por_verificar`,
`licencia_por_vencer_5d`, `licencia_por_vencer_1d`.

## 5. Cómo probar (entorno local ya preparado)

Base aislada creada y migrada: `appyra_license_e2e` en el contenedor
`fullpos_license_fiscal_pg_20261115` (puerto 56701). Las 85 migraciones se aplicaron de cero y el
catálogo quedó sembrado con los cuatro planes.

```powershell
cd C:\src\fullpos-planes-de-pago-impl\apps\api
$env:DATABASE_URL = "postgresql://ci:<clave>@127.0.0.1:56701/appyra_license_e2e?schema=public"
npx prisma migrate deploy
npx ts-node --transpile-only -P tsconfig.scripts.json scripts/seed-license-plans.ts
npm run start:dev
```

Prueba de integración del flujo completo (se salta si falta la URL):

```powershell
$env:LICENSE_PAYMENTS_FIXTURE_URL = $env:DATABASE_URL
npx jest --runInBand src/license/orders/license-orders.integration-spec.ts
```

## 6. Verificación ejecutada

| Comprobación | Resultado |
| --- | --- |
| `tsc -p tsconfig.build.json --noEmit` | 0 errores |
| `npm test` (unitarias) | **2.925 pasan, 0 fallan** (55 suites e2e/integración omitidas sin base) |
| `license-orders.integration-spec` (PostgreSQL real) | **5/5** — orden, activación inmediata, duplicado, renovación acumulada, plan inferior apaga funciones |
| `prisma migrate deploy` en base vacía | 85 migraciones aplicadas |
| Seed del catálogo | 4 planes, precios 1.000 / 2.500 / 3.500 / 5.000 |
| APPYRA `node --test tests/service-daleventas-read.test.js` | 28/28 |
| Web `astro check` / `build` / `npm test` | 0 errores · 14 páginas · 13/13 |
| App `flutter analyze lib` | **No issues found** |
| App `flutter test test/features/plans` | **2/2** — catálogo y plan actual en 1320 px, y sin desbordes en 390 px |
| Web publicada | 1 / 3 / 4 / 7 usuarios; ya no aparece «2 usuarios» ni «20 usuarios» |

## 7. Qué falta

1. **Entrada visible a Planes**: el enlace del menú sigue diciendo «Licencias» (ya abre Planes);
   conviene renombrarlo y añadir un aviso en Inicio cuando la licencia está por vencer.
2. **Landing de la app**: quitar `_plans` hardcodeado y leer `GET /license/plans` (hoy publica
   precios viejos y un total trimestral).
3. **Botones del CRM en APPYRA** (interfaz): usar los endpoints nuevos para «Ver comprobante» y
   «Pago recibido», y el selector de excepciones dentro de «Editar».
4. **Pruebas APPYRA** de `orders` y `overrides` (las nuevas rutas solo tienen validación de sintaxis).
5. **Endurecimiento pendiente**: retención de comprobantes y límite de tamaño en el puente.
6. **Despliegue**: no ejecutado. `RUN_SEED` no está activo; el catálogo necesita el seed una vez.

> Nota de entorno: para poder compilar y probar la app se creó `apps/fulltech_app/.env` **local**
> (ignorado por Git) apuntando a `http://127.0.0.1:4097`. No contiene secretos reales.
