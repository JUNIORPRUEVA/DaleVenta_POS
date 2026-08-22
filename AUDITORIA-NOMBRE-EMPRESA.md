# 🔍 AUDITORÍA NOMBRE DE EMPRESA — DaleVentas POS

> **Fecha:** 2026-08-22
> **Alcance:** `Company.name` (nombre maestro de empresa) sobrescrito por valores de producto/software (`FullPOS Cloud`, `DaleVenta POS`).
> **Método:** Auditoría forense de código + consulta **solo-lectura** a la base de datos real.
> **Estado de la corrección:** ⛔ **NO aplicada todavía** (pendiente de aprobación; causa raíz demostrada a nivel de código y evidencia de BD).

---

## 0. Estado del repositorio (FASE 1)

- Rama: `main`
- HEAD: `359ef560`
- Existen cambios sin commitear PREEXISTENTES (caja, catálogo, cotizaciones, etc.). **No se modificaron.**
- No se ejecutaron `reset --hard`, `clean` ni `checkout .`.
- Archivo temporal de auditoría BD: `apps/api/_audit_company_readonly.js` (solo lectura; pendiente de eliminación).

---

## 1. Fuente oficial de verdad (FASE 2)

```
Fuente oficial:
tabla:  companies          (Prisma model Company, @@map("companies"))
columna: name              (String, NOT NULL)
companyId: be1fb5e7-5fb8-4d70-a2b8-db7011e8bb03   (única empresa en la BD)
valor actual: "DaleVenta POS"                      ← nombre de PRODUCTO, no de empresa
createdAt: 2026-07-28T01:12:36.019Z
updatedAt: 2026-07-28T01:41:01.457Z
```

Archivo: `apps/api/prisma/schema.prisma` (modelo `Company`, líneas 614-698).

**Copias derivadas (NO son fuente):**
- `AppConfig.companyName` — copia de visualización/ajustes, sincronizada DESDE `Company.name` por `ensureConfig` en `apps/api/src/settings/settings.service.ts` (líneas 199-220). Verificado en BD: `AppConfig.companyName = "DaleVenta POS"` (mismo valor, mismo `updatedAt`).
- `CompanyLicenseAuditLog` — tabla de auditoría (`companyLicenseAuditLog`). **Vacía** en la BD consultada.

---

## 2. Todos los lugares que ESCRIBEN `Company.name` (FASE 4)

Matriz completa de escrituras (evidencia real):

| # | Origen | Endpoint / Método | ¿Puede escribir `name`? | Requiere | Audit log |
|---|--------|-------------------|------------------------|----------|-----------|
| 1 | `apps/api/src/auth/auth.service.ts` `registerBusiness` | `POST /auth/register` → `tx.company.create` | Sí (solo CREACIÓN) | Registro (form explícito `commercialName`) | No |
| 2 | `apps/api/src/settings/settings.service.ts` `updateSettings` | `PATCH /settings` | ✅ SÍ — `tx.company.update({ data: { name: companyName } })` si `companyName` no vacío | Admin (`isAdminLike`) | ✅ `settings.company_name_update` |
| 3 | `apps/api/src/license/license.service.ts` `activateCompany` / `updateCompanyLicense` | `POST /license/activate`, `PATCH /license/limits` (+ variantes admin) | ✅ SÍ — `name: displayName` si `dto.companyName|businessName|name` presente | Admin / `LICENSE_ADMIN_SECRET` | ✅ `license.*` |
| 4 | `apps/api/src/tax/tax.service.ts` (varios) | fiscal | ❌ NO (solo `taxEnabled`, `defaultTaxId`, `defaultTaxRate`, `pricesIncludeTax`, `ncfEnabled`) | Admin | — |
| 5 | `apps/api/src/license/license.service.ts` `blockCompany` / `deleteCompanyLicense` | — | ❌ NO | — | ✅ |

### Clientes (Flutter)

| Origen | Método | ¿Puede escribir `name`? |
|--------|--------|------------------------|
| `apps/fulltech_app/lib/core/company/company_settings_repository.dart` `_saveSettingsRemote` | `PATCH /settings` con **objeto COMPLETO** incl. `companyName` | ✅ SÍ |
| `license_repository.dart` `activate`/`updateLimits`/`block` | `POST/PATCH /license/*` | ❌ NO (no envía `companyName`/`businessName`/`name`) |

Únicos llamadores de `_saveSettingsRemote`:
1. Editor de empresa: `apps/fulltech_app/lib/features/account/account_menu_screens.dart` `_save()` → `saveSettingsOrQueue` (línea ~1989).
2. Replay offline: handler `settings.save` en `company_settings_repository.dart` (líneas 88-97), disparado por `SyncQueueService.processPending`.

**No existe ningún write automático en startup, login, bootstrap ni reconnect.** Verificado en `main.dart` (flujos de licencia son GET/invalidación), `app_startup_controller.dart` (`prepareAppFirstFrame` solo carga env y repara SharedPreferences), `app_bootstrap_status.dart` (solo lectura).

---

## 3. Todas las apariciones de `FullPOS Cloud` (FASE 3)

Clasificación (solo código fuente; se excluyeron logs y artefactos de build):

| Archivo | Línea(s) | Propósito | ¿UI? | ¿Fallback? | ¿Puede llegar a modelo/persistencia? |
|---------|----------|-----------|------|-----------|--------------------------------------|
| `core/loading/app_loading_screen.dart` | 95 | Texto splash/carga | ✅ | no | ❌ |
| `core/widgets/app_drawer.dart` | 562 | Texto UI | ✅ | no | ❌ |
| `core/widgets/app_navigation.dart` | 249-252 | Título por defecto (fallback de segmento) | ✅ | visual | ❌ |
| `core/widgets/responsive_shell.dart` | 206, 291, 1637 | Footer/título | ✅ | no | ❌ |
| `core/routing/app_navigator.dart` | 375 | Diálogo cerrar app | ✅ | no | ❌ |
| `core/startup/app_startup_controller.dart` | 37, 143, 159 | Títulos de estado | ✅ | no | ❌ |
| `features/auth/presentation/{landing,login,register,splash}_screen.dart` | varias | Texto marketing/login | ✅ | no | ❌ |
| `core/pdf/pdf_kit.dart` | 238 | `brand` por defecto en PDF (autor) | ✅ | visual | ❌ |
| `features/reports/utils/sales_report_pdf_service.dart` | 62, 79 | Autor/texto PDF | ✅ | visual | ❌ |
| `core/printing/esc_pos/*`, `html/*`, `ticket_builder.dart` | varias | Cabecera de ticket térmico | ✅ | visual | ❌ |
| `modules/cash/cash_close_ticket_printer.dart` | 969 | Footer "Documento generado por..." | ✅ | no | ❌ |
| `features/settings/data/cloud_backup_service.dart` | 58-59, 181, 217 | Llaves de almacenamiento y carpeta de backup | ✅ | no (storage) | ❌ |
| `core/app_access/app_access_links.dart` | 29-77 | URLs PWA/descargas | ✅ | no | ❌ |
| `core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart` | 132 | `companyName: 'FULLTECH, SRL'` (default de preview) | ✅ | visual (impresión) | ❌ |
| `main.dart` | 360, 403, 486 | Título ventana + textos de licencia | ✅ | no | ❌ |

**Conclusión FASE 3:** `FullPOS Cloud` se usa **exclusivamente** para UI, PDFs/tickets (presentación) y almacenamiento local. **Ninguna aparición alimenta `CompanySettings.companyName`** (`CompanySettings.empty()` = `''`, `fromMap` = `(map['companyName'] ?? '')`, `copyWith` = `companyName ?? this.companyName`). Verificado: NO existe el patrón `?? 'FullPOS Cloud'` en `lib/`.

Apariciones de **`DaleVenta POS`** (producto actual):
- `modules/cotizaciones/cotizaciones_screen.dart` líneas 8391 y 8393 — fallback de **presentación** en el panel "Licencias" (`_LicenseAccountCard`). **No persiste.**

Apariciones de **`FULLTECH, SRL`** (hardcode de visualización en PDFs/impresión):
- `features/contabilidad/utils/{deposit_order,fiscal_invoices}_pdf_service.dart`
- `modules/nomina/mis_pagos_screen.dart`, `modules/ventas/sales_credit_screen.dart`, etc. — solo presentación.

---

## 4. PUT vs PATCH y DTOs (FASES 5-7)

- El endpoint es `PATCH /settings` (parcial), pero **el cliente envía el objeto COMPLETO**:
  - `company_settings_repository.dart` `_saveSettingsRemote` (líneas 222-280): payload con `companyName`, `rnc`, `phone`, `address`, ... en **cada** guardado.
- El backend `updateSettings` (settings.service.ts líneas 37-101):
  - Si `dto.companyName` está presente y **no vacío** → `tx.company.update({ data: { name: companyName, ...fiscal } })`.
  - Si `companyName` está presente y vacío → `BadRequestException('El nombre de la empresa es obligatorio')`.
  - Si NO viene `companyName` → no toca `name`.
- **Riesgo confirmado (FASE 7):** como el cliente siempre manda `companyName`, un guardado de solo teléfono **SÍ reescribe** `Company.name` con el valor cargado en ese momento (remoto/caché/fallback). No hay flag que distinga "edición explícita del nombre" de "guardar otros campos".

---

## 5. Caché local (FASES 8-9, 22)

- `company_settings_repository.dart`:
  - Clave: `company_settings_cache_v1:company:<companyId>`.
  - `getSettings()`: remoto primero → caché (maxAge 14 días) → `CompanySettings.empty()`.
- `LocalJsonCache` (`core/cache/local_json_cache.dart`): antepone `ft_cache:<companyId del token>:` a la clave. Scope por empresa (bien).
- `getCachedSettings()` fallback a clave sin scope solo cuando `_cacheScope == null` (sin empresa). Con el prefijo del token sigue siendo por empresa.

**Hallazgo:** no se encontró código actual que escriba `FullPOS Cloud`/`DaleVenta POS` en la caché de settings. Históricamente `companyName: 'FullPOS Cloud'` solo existió en `apps/api/src/settings/settings.service.spec.ts` (test), no en código de producción.

---

## 6. Sincronización offline / write-back (FASE 11)

- `saveSettingsOrQueue` (company_settings_repository.dart líneas 288-310):
  1. Escribe caché (`settings.toMap()`).
  2. Intenta `PATCH /settings`.
  3. Si falla (sin red / 5xx) → `enqueue('settings.save', payload: {'settings': settings.toMap()})`.
- `SyncQueueService` (`core/offline/sync_queue_service.dart`):
  - `start()` cada 20s + `processPending()` en resume/reconnect.
  - Filtra acciones por `companyId`+`userId` del token actual (protegido contra cruce de tenants).
  - Handler `settings.save` (company_settings_repository.dart 88-97) → `_saveSettingsRemote(settings)` con el objeto **completo** guardado.

**Riesgo confirmado:** la cola offline puede re-aplicar un objeto completo de settings (con un `companyName` posiblemente desactualizado) al reconectar. Android (red móvil inestable, cierre de app en background) es el escenario más probable de encolar y luego reproducir — **coincide con el síntoma "después de usar Android"**.

---

## 7. Flujo Android vs Windows (FASES 8, 25-26)

- Windows y Android comparten el mismo código Flutter (`CompanySettingsRepository`).
- **No hay diferencia de código** en la ruta de escritura por plataforma. La diferencia práctica es **conectividad**:
  - Windows (escritorio): normalmente online → `getSettings()` remoto siempre → editor carga nombre real.
  - Android: puede arrancar/operar offline o con red inestable → `getSettings()` puede devolver **caché** (14 días) o `empty()`; un guardado posterior (o el replay de la cola) reenvía ese objeto.
- No se observó ningún `Platform.isAndroid` que active un write automático de settings/empresa en el arranque.

---

## 8. ENDPOINT Y PAYLOAD RESPONSABLE

```
PATCH /settings   (apps/api/src/settings/settings.controller.ts → settings.service.ts updateSettings)
Body (client, SIEMPRE con companyName):
{
  "companyName": "<valor cargado actualmente>",
  "rnc": "...", "phone": "...", "address": "...", ...   ← resto de campos
}
→ settingsData(dto) → si companyName no vacío → prisma.company.update({ data: { name: companyName } })
```

---

## 9. CAUSA RAÍZ (demostrada)

**Cadena exacta (código):**

```
1. Cliente carga CompanySettings (remoto → CACHÉ → empty)      [company_settings_repository.getSettings]
2. Usuario guarda ajustes (p. ej. solo teléfono)                [account_menu_screens _save → saveSettingsOrQueue]
3. _saveSettingsRemote construye payload COMPLETO incl. companyName  [líneas 222-280]
4. PATCH /settings                                               [settings.controller]
5. updateSettings: companyName no vacío → company.update(name)  [settings.service líneas 56-98]
6. Company.name queda = valor cargado (posiblemente caché/fallback antiguo)
```

**Alternativa offline (misma raíz):**
```
saveSettingsOrQueue offline → enqueue settings.save (objeto completo)
→ reconexión → SyncQueueService.processPending → handler → _saveSettingsRemote → PATCH /settings → Company.name = valor del objeto encolado
```

**Naturaleza del problema:** No hay separación entre "nombre almacenado" y "nombre mostrado/por defecto". El endpoint de ajustes acepta `Company.name` desde cualquier payload genérico, y el cliente no distingue cuándo es un cambio explícito de nombre. Un valor por defecto/fallback/caché de **nombre de producto** (`FullPOS Cloud`, `DaleVenta POS`) puede entrar así a `Company.name` sin que el usuario lo edite.

---

## 10. EVIDENCIA (FASE 46-47)

### BD (solo lectura, apps/api/_audit_company_readonly.js)
- `Company.name = "DaleVenta POS"` → **es un nombre de producto**, no la empresa. Evidencia de que un valor de producto ha sido persistido en el campo maestro.
- `updatedAt = 2026-07-28T01:41:01Z` (creación 01:12:36Z, ~29 min después hubo un update del registro, posiblemente fiscal/trial, no necesariamente del nombre).
- `CompanyLicenseAuditLog` **vacía** → no hay historial de cambios de nombre vía settings/license (o la tabla se agregó después). Imposible determinar por audit trail quién puso el valor actual.
- `AppConfig.companyName` idéntico (consistente con la política server-wins de `ensureConfig`).

### Código
- Payload completo con `companyName` en cada guardado: `company_settings_repository.dart:222-280`.
- Backend persiste `name` desde el payload: `settings.service.ts:56-98`.
- Replay offline del objeto completo: `company_settings_repository.dart:88-97` + `sync_queue_service.dart`.
- Fallbacks de producto: `cotizaciones_screen.dart:8391,8393` (`DaleVenta POS`); múltiples `FullPOS Cloud` en UI/PDF/print (sección 3).

---

## 11. CORRECCIÓN RECOMENDADA (FASE 34 — NO aplicada aún)

### Defensa primaria (arquitectónica)
1. **Backend `PATCH /settings`:** escribir `Company.name` SOLO cuando el DTO traiga un flag explícito de edición de nombre (p. ej. `updateCompanyName: true`) o mover el nombre a un endpoint dedicado (`PATCH /settings/company-name`). En guardados genéricos de settings, NUNCA tocar `name`.
2. **Cliente `_saveSettingsRemote`:** NO incluir `companyName` salvo edición explícita del campo nombre en el editor (detectar cambio vs. valor cargado). Separar `storedCompanyName` vs `displayCompanyName`.
3. **Server-wins para datos maestros:** al cargar settings desde caché, no permitir que ese objeto sea la base de un guardado sin revalidar el nombre contra el servidor.

### Defensa secundaria (offline / robustez)
4. **Cola offline:** en el handler `settings.save`, descartar el objeto si el `companyName` local difiere del nombre del servidor recién leído (o marcar el payload con el nombre esperado del servidor y validarlo en backend).
5. **Audit log completo:** registrar TODOS los cambios de `Company.name` (settings ya lo hace; ampliar a flujos de licencia) con `companyId, actorId, field, oldValue, newValue, source`.
6. **Endpoints de licencia:** whitelist — solo aceptar `companyName` en el endpoint de branding explícito, no en `updateLimits`.

> ⛔ **NO** se bloquea el literal `FullPOS Cloud` ni se hardcodea `FULLTECH, SRL`: la defensa es estructural (impedir que un valor no-editorial llegue a `Company.name`).

---

## 12. PLAN DE TESTS (FASE 35)

| Test | Escenario | Esperado |
|------|-----------|----------|
| 1 | PATCH /settings sin `companyName` (o sin flag de edición) | `Company.name` NO cambia |
| 2 | Payload parcial (solo `phone`) | `Company.name` permanece |
| 3 | Bootstrap móvil / login / startup | NO genera write de `name` |
| 4 | Caché local con nombre viejo | Servidor gana (`server wins`) |
| 5 | Empresa A y B | Sin contaminación cruzada |
| 6 | Fallback de UI (`FullPOS Cloud`/`DaleVenta POS`) | Se muestra solo si corresponde, NUNCA se persiste en `Company.name` |

---

## 13. PRUEBA CROSS-DEVICE (FASES 36-38)

1. Fijar `Company.name = <nombre real>` en servidor.
2. Windows: login → navegar → cerrar → abrir → verificar nombre intacto.
3. Android: login → navegar módulos → venta/cotización → sync → cerrar → abrir → verificar.
4. Repetir Windows → Android varias veces. El nombre solo cambia con edición explícita.

---

## 14. PREGUNTAS CLAVE RESPONDIDAS (resumen)

1. **¿Fuente oficial?** `companies.name`.
2. **¿Quién puede escribirla?** Register (create), `PATCH /settings` (admin), flujos de licencia (admin/secreto). Cliente Flutter: solo vía `PATCH /settings` desde el editor o replay offline.
3. **¿Fallback `FullPOS Cloud`?** Sí, pero SOLO presentación (UI/PDF/tickets); **no** se persiste hoy.
4. **¿Android envía el valor?** No hay write automático en Android; el riesgo es la caché + cola offline en Android.
5. **¿Windows lo envía?** Misma ruta que Android (solo editor/replay).
6. **¿Sync local→servidor sobrescribe?** La cola offline reenvía el objeto completo de settings (riesgo), pero está scopeada por tenant.
7. **¿`PUT`/`PATCH` con objeto completo?** `PATCH /settings` con objeto completo desde el cliente → puede reemplazar el nombre.
8. **¿Por qué solo a veces / una empresa?** Requiere que el objeto cargado tenga un nombre distinto al master (caché vieja/sesión previa/instalación con default de producto) + un guardado o replay offline. Depende del estado local del dispositivo, no de la empresa; la BD actual tiene una sola empresa.

---

# ✅ IMPLEMENTACIÓN APLICADA (2026-08-22)

Blindaje arquitectónico implementado y probado. Ya NO es solo análisis.

## Ruta vieja (eliminada)
```
cliente → payload completo (incl. companyName) → PATCH /settings → Company.name sobreescrito
```

## Ruta nueva
```
PATCH /settings                    → teléfono, dirección, logo, fiscal, etc.  (NUNCA toca Company.name)
PATCH /settings/company-name       → única vía de cambio de nombre (admin + audit log)
replay offline settings.save       → sanea/elimina companyName (payloads legacy)
replay offline settings.save_name  → usa la vía dedicada de nombre
```

## Cambios aplicados

### Backend
- `apps/api/src/settings/settings.service.ts`
  - `updateSettings` (PATCH /settings) ahora **ignora `companyName`** (`withoutCompanyName`) → no escribe `Company.name` ni propaga el nombre a `AppConfig` desde payloads genéricos/legacy. El fiscal sigue fluyendo por `taxes.updateFiscalSettings`.
  - Nuevo `updateCompanyName` (PATCH /settings/company-name): requiere admin, valida nombre no vacío, actualiza `Company.name` + `AppConfig.companyName`, escribe audit log `settings.company_name_update` (before/after), emite realtime `license.company_name_updated`.
- `apps/api/src/settings/settings.controller.ts`: nuevo endpoint `@Patch('company-name')`.
- `apps/api/src/settings/settings.service.spec.ts`: tests actualizados + nuevos (renombrado dedicado, no-admin rechazado, legacy ignorado, fiscal intacto).

### Flutter
- `apps/fulltech_app/lib/core/api/api_routes.dart`: `settingsCompanyName = '/settings/company-name'`.
- `apps/fulltech_app/lib/core/company/company_settings_repository.dart`
  - `_saveSettingsRemote`: el payload genérico **ya no incluye `companyName`**.
  - Nuevo `_saveCompanyNameRemote` + `saveCompanyNameOrQueue` (vía dedicada con reintento offline `settings.save_name`).
  - Handler `settings.save`: **sanea payloads legacy** (`remove('companyName')`) antes de reenviar — protege instalaciones Android antiguas con colas pendientes.
- `apps/fulltech_app/lib/features/account/account_menu_screens.dart`: el editor solo envía el nombre por la vía explícita cuando el usuario **realmente lo editó** (`nameChanged`); guardar teléfono/dirección/logo/impuestos no reenvía nombre.
- `apps/fulltech_app/test/core/company/company_settings_repository_test.dart`: tests nuevos (generic save no envía nombre, replay legacy sanea, endpoint dedicado, offline queue de nombre, empty/non-admin rechazados).

## Audit log de nombre
Cada cambio legítimo registra: `companyId, actorId, action='settings.company_name_update', before, after, createdAt`. Los flujos de licencia ya auditaban `Company.name` vía `companySnapshot` (before/after).

## DB ANTES/DESPUÉS (operación administrativa puntual, con audit)
| Campo | ANTES | DESPUÉS |
|-------|-------|---------|
| `Company.name` | `DaleVenta POS` | `FULLTECH, SRL` |
| `AppConfig.companyName` | `DaleVenta POS` | `FULLTECH, SRL` |
| `updatedAt` | 2026-07-28 | 2026-08-22T21:34:12Z |
| Audit entry | (vacía) | `settings.company_name_update` / reason `admin_restore_after_hardening` |

## Hallazgo adicional (drift de BD)
La tabla `app_config` de esta BD usa nombres de columna en camelCase y **carece de `admin_authorization_pin_hash`** (columna del schema actual). La BD necesita aplicarse las migraciones pendientes (no se tocó: riesgo/out of scope). Esto no afecta la protección del nombre, pero `setAdminPin` fallará en esta BD hasta migrar.

## PRUEBAS (resultados)
- Backend `npm test`: **99/99 passed** (20 suites), incluidos los 6 de settings.
- Backend `npm run build` (tsc): ✅ sin errores.
- Flutter `flutter analyze` (full): **No issues found**.
- Flutter `company_settings_repository_test.dart`: **12/12 passed**.
- Flutter `company_account_menu_navigation_test.dart` + `sales_company_topbar_bootstrap_test.dart`: **4/4 passed**.
