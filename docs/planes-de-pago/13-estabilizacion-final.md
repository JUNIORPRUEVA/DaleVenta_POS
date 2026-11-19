# Estabilización final del sistema de licencias — informe FASE 4

Fecha: 2026-11-19 · Rama `agent/planes-de-pago-impl-20261116` · Worktree
`C:\src\fullpos-planes-de-pago-impl` · Base local `planes_local` · **sin despliegues, sin commits**

Prioridad aplicada: **ningún cliente con plan ACTIVO podía verse afectado**. Todo lo que sigue se
ejecutó contra la base local y el servidor local (`http://127.0.0.1:4097`).

## 1. Resultado por tipo de prueba

| Tipo | Comando | Resultado |
| --- | --- | --- |
| Tipos backend | `npx tsc -p tsconfig.build.json` | **PASS** · 0 errores |
| Unitarias backend | `npm test` (excluye e2e) | **PASS** · 258 suites / 3.005 pruebas, 0 fallos (56 suites omitidas por el propio repo) |
| Extremo a extremo licencias | `npx jest --runInBand --testPathPatterns='license.*e2e-spec\|crm-license-http'` | **PASS** · 2 suites / 12 pruebas |
| Flutter estático | `flutter analyze lib test` | **PASS** · sin avisos |
| Flutter unitarias/widgets | `flutter test` | **PASS** · 2.489 pruebas, 10 omitidas, **0 fallos** |
| Flutter planes | `flutter test test/features/plans` | **PASS** · 50/50 |
| Visual Windows (4 estados) | sesión real en la app | **PENDIENTE** (ver §5) |
| Visual Web/móvil | — | **NO EJECUTADO** (ver §5) |
| APPYRA CRM ↔ puente | app del CRM local | **NO EJECUTADO**; contrato verificado por e2e |

## 2. Comparación antes/después de la empresa ACTIVO

Script reproducible: `apps/api/scripts/license-scenarios-evidence.ps1 -RunSuites`. Toma una foto de
licencia, cuotas, fechas, notas, clave, `updated_at` y número de registros de auditoría **antes** y
**después** de ejecutar las once suites de licencia.

```
empresa semilla 11111111-1111-4111-8111-111111111111
ANTES   : ACTIVE|STANDARD|-|-|ACTIVE|-|-|-|-|-|20|1000|1|f|-|-|2026-11-19 02:59:11.475 | 15|0
DESPUÉS : ACTIVE|STANDARD|-|-|ACTIVE|-|-|-|-|-|20|1000|1|f|-|-|2026-11-19 02:59:11.475 | 15|0
RESULTADO: PASS — idéntica (plan, estado, cuotas, multi-almacén y fecha de actualización incluidos)
```

Lectura: la empresa ACTIVO conserva `STANDARD`, `license_status ACTIVE`, sin vencimiento (periodo
ilimitado heredado), 20 usuarios, 1.000 productos, multi-almacén heredado y **la misma** `updated_at`,
así que ninguna prueba la escribió.

## 3. Los siete escenarios, con su prueba

| Escenario | Evidencia | Estado |
| --- | --- | --- |
| ACTIVO conserva acceso y cuotas | `license-active-protection.spec.ts` (incluye empresa heredada sin plan) | PASS |
| ACTIVO renueva sumando meses al periodo pagado | `license-renewal.service.spec.ts` + protección ACTIVO | PASS |
| VENCIDO renueva y recupera acceso | `license-renewal.service.spec.ts` + `license-access.interceptor.spec.ts` | PASS |
| DEMO terminada contrata su primer plan | `license-trial.spec.ts` (una sola demo, 7 días exactos, 409 al repetir) | PASS |
| SUSPENDIDO sigue suspendido aunque llegue un comprobante | `license-provisional.service.spec.ts` (la reversión mantiene `BLOCKED`) | PASS |
| Pago rechazado revierte solo el beneficio provisional | `license-provisional.service.spec.ts` + `bank-transfer.analysis.spec.ts` | PASS |
| Mejora de plan respeta plan y periodos pagados | `license-entitlements.service.spec.ts` + `license-plans.service.spec.ts` | PASS |

Once suites ejecutadas una por una por el script: **11/11 PASS**.

## 4. Correcciones aplicadas en esta fase

1. **Borrado permanente devolvía 500** (encontrado en la fase anterior). Causa: borrado manual tabla a
   tabla en orden alfabético, que eliminaba `warehouses` antes que `terminals` (clave foránea
   `RESTRICT`); el intento posterior falló con `operator does not exist: uuid = text`. Solución final:
   se apoya en los `ON DELETE CASCADE` que ya existen hacia `companies` y solo borra a mano
   `password_reset_audit_logs` con `$1::uuid`. **Verificado**: cinco empresas de prueba borradas con
   HTTP 200 y sus usuarios huérfanos eliminados; respaldo previo en
   `docs/backups/planes_local_20261118-231306.dump` (795 KB).
2. **Múltiples almacenes** responde `403 PLAN_FEATURE_NOT_INCLUDED` cuando el plan no lo incluye (antes
   daba un mensaje ambiguo). Cubierto por `warehouses.service.spec.ts` (24 pruebas entre almacenes y
   derechos del plan).
3. **Demo**: se quitó el inicio automático en el login; ahora es acción administrativa
   (`POST /license/admin/:companyId/trial`), 7 días exactos, 409 al repetir.
4. **Regresión propia detectada y corregida hoy**: seis pruebas Flutter fallaban por un temporizador de
   18 s pendiente (`LicenseRepository.getLicense` consumido desde el menú de cuenta) y por la etiqueta
   antigua `Licencias` del menú, ya renombrada a `Plan actual` en el rediseño. Se inyectó una licencia
   falsa en las dos pruebas y se actualizó la expectativa: **10/10 PASS**. Comprobado antes que las
   mismas dos suites pasan en `HEAD` (10/10), así que el fallo era del trabajo de la rama.

## 5. Pendiente (no se declara verificado)

- **Visual Windows de los cuatro estados**: la ventana Flutter de este equipo no acepta clics ni teclado
  sintéticos, así que la verificación visual requiere una sesión manual
  (`uat.admin@daleventa.local`) con `scripts/license-state.ps1` en `expired`, `trial-expired`,
  `blocked` y `active`.
- **Web y móvil**: no ejecutados.
- **APPYRA CRM local ↔ puente de licencias**: el **contrato** está cubierto por las pruebas e2e
  (`crm-license-http.e2e-spec`), pero la app del CRM no se levantó; no se ha probado el flujo desde su
  interfaz.
- **Despliegue**: no se ha desplegado nada y no se declara GO a producción.

## 6. Riesgos vivos

1. **Empresas antiguas en TRIAL sin fechas conservan acceso completo indefinidamente.** No se ha tocado
   a propósito (cambiarlo sí afectaría a clientes en uso). Requiere decisión de negocio antes de
   producción.
2. **El motor OCR no está en la imagen de producción.** Sin el media-worker (o
   `APPYRA_MEDIA_BASE_URL`), todo comprobante cae en revisión manual; sin `LICENSE_ADMIN_SECRET` y
   `CRM_LICENSE_MANAGEMENT_ENABLED=true` nadie puede confirmarlo y el pago queda `UNCONFIRMED`.
3. **`prisma generate` falla con el servidor de desarrollo levantado** (EPERM sobre
   `query_engine-windows.dll.node`). Es un bloqueo de entorno, no del código: para compilar hay que
   parar el servidor o usar `npx tsc -p tsconfig.build.json`.
4. **La rama no tiene commits.** Todo el trabajo está en el árbol de trabajo; nada viaja a `main` ni a
   producción sin autorización.

## Veredicto

**GO WITH ISSUES** para dar por cerrada la estabilización **en local**: código y suites en verde, la
empresa ACTIVO intacta antes/después, los siete escenarios cubiertos y los 500 corregidos y verificados.
**NO-GO a producción** mientras falten la verificación visual real de los cuatro estados, la prueba en
web/móvil, el flujo desde APPYRA CRM y la decisión sobre las empresas TRIAL heredadas sin fechas.
