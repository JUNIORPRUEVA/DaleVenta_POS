# e-CF — Integración del interruptor de empresa y el Drawer

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-15**.
Sin `commit`, sin `push`, sin `deploy`. Producción y UAT histórica **intactas**.

---

## 1. Auditoría: qué existía ya

| Pieza | Estado encontrado |
| --- | --- |
| Rutas e-CF | **Ya existían y están montadas**: `/ecf` → `EcfDocumentsPage`, `/ecf/config` → `EcfConfigPage` (`app_router.dart:173-178`) |
| Interruptor e-CF | **Ya existía**: `PATCH /ecf/config {enabled}` + `ecf.capabilities().enabled`, con permiso `manageEcfConfig` |
| Pantallas e-CF | **Ya existían**: bandeja, detalle, acción E31/E32 desde la venta, acción E34 |
| Drawer | `buildAppNavigationSections` en `core/widgets/app_navigation.dart`, consumido por `app_drawer.dart` (móvil) y `responsive_shell.dart` (escritorio) |
| Entrada e-CF en el menú | **Existía, pero mal integrada**: `'Comprobantes e-CF'`, a mitad del menú, filtrada **solo por permiso** — se mostraba aunque la empresa tuviera e-CF **desactivado** |

**No había que crear nada nuevo**: el trabajo era corregir la integración, exactamente
como pedía la misión.

## 2. Cambios realizados

`lib/core/widgets/app_navigation.dart`:

1. Nuevo parámetro **`bool ecfEnabled = false`** en `buildAppNavigationSections`.
2. **Eliminada** la entrada `'Comprobantes e-CF'` situada a mitad del menú.
3. **Añadida al FINAL del menú** (última sección, tras `Usuario`) la opción
   **`'Facturación electrónica'`**, condicionada a
   `ecfEnabled && canOrAuthorize(AppPermission.viewEcfDocuments)`.

**Decisión de diseño:** el valor por defecto `false` es deliberado. Un llamador que
no pase el interruptor no muestra e-CF, así que **un fallo de red o una
configuración sin confirmar nunca dejan el módulo a la vista** — que es lo que
pedía la misión.

## 3. Cableado del interruptor al Drawer — RESUELTO

La sesión anterior dejó esto pendiente. Se resolvió **sin añadir ninguna petición
de red al menú**, llevando la bandera a la configuración de empresa que el Drawer
**ya observaba**:

| Capa | Cambio |
| --- | --- |
| Backend | `settings.service.ts`: única lectura `ecfEnabledFor(companyId)` (ámbito de la empresa autenticada) y **`toPublicSettings` la publica**. Sin ese segundo paso el flag se perdía: ver §3.d, defecto 2 |
| Modelo Flutter | `CompanySettings.ecfEnabled` (campo, constructor con valor por defecto `false`, `toJson` y `fromJson`) |
| Drawer móvil | `app_drawer.dart`: `ecfEnabled = ref.watch(companySettingsProvider).valueOrNull?.ecfEnabled ?? false` |
| Shell escritorio | `responsive_shell.dart`: mismo origen, `ref.watch(companySettingsProvider)` |

**Por qué esto no repite el error anterior:** `companySettingsProvider` es un
`FutureProvider` **no autoDispose**, compartido y con caché por sesión, que el
Drawer **ya** consumía para multi-almacén. No hay proveedor nuevo, no hay
petición nueva y **las 17 pruebas de Drawer que rompieron siguen pasando** (ya
sobrescriben ese mismo provider).

Mientras la configuración no esté confirmada, `valueOrNull` es `null` → **`false`**:
un error de red nunca deja el módulo a la vista.

## 3.b Interruptor en Configuración de empresa — IMPLEMENTADO

`AccountCompanySettingsScreen` (`/configuracion/empresa`,
`lib/features/account/account_menu_screens.dart`) incorpora la sección
**«Facturación electrónica (e-CF)»** con el texto pedido, indicador de estado,
interruptor, indicador de guardado, error recuperable con «Reintentar» y acceso a
la configuración avanzada (`/ecf/config`).

Decisiones que importan:

- **Nunca optimista:** el interruptor refleja `companySettings.ecfEnabled`, es
  decir lo confirmado por el backend. Si el `PATCH` falla, vuelve a mostrar el
  último estado confirmado y explica el error; nunca presenta como guardado algo
  que el servidor rechazó.
- **Sincronización:** tras la respuesta correcta se invalidan
  `companySettingsProvider` y `ecfCapabilitiesProvider`, así que el Drawer se
  reconstruye **sin reiniciar** (la cadena de §3).
- **Sin condiciones de carrera:** mientras guarda, el interruptor se
deshabilita y muestra un indicador; no se disparan solicitudes duplicadas.
- **Permisos:** solo `manageEcfConfig` puede cambiarlo; el resto lo ve en modo
  lectura con el motivo.
- **Desactivar pide confirmación** y no borra nada: los comprobantes históricos,
  las ventas, la caja y el inventario se conservan.
- **Sin catch-22:** la sección se muestra SIEMPRE a quien puede gestionarla,
  incluso con el módulo apagado — que es justo donde se activa.

Activar el módulo **no** habilita emisión real ni credenciales de Alanube: esas
compuertas siguen siendo independientes.

## 3.c Lo que sigue SIN PROBAR

**Nada de esta cadena queda sin prueba automatizada.** Lo único pendiente es la
**comprobación visual del interruptor** dentro de una sesión autenticada real,
que está **BLOCKED** por falta de credenciales UAT (ver §3.d). No se declara
ningún PASS visual que no se haya ejecutado.

## 3.d Verificación ejecutada — 2026-10-15

### Prueba funcional (una sola escena: pantalla REAL + Drawer REAL)

`apps/fulltech_app/test/features/account/ecf_company_toggle_drawer_test.dart`
monta `AccountCompanySettingsScreen`, el `AppDrawer` real (el que entrega
`buildAdaptiveDrawer`), el `companySettingsProvider` real con un backend simulado
detrás, los permisos reales y un repositorio e-CF simulado. Sin red: un `Dio`
instrumentado registra cualquier petición y la hace fallar.

| # | Caso | Resultado |
| --- | --- | --- |
| 1 | Empresa desactivada: la opción no existe en el Drawer | PASS |
| 2/3 | El administrador activa; el backend confirma (`PATCH` único, valor y empresa correctos) | PASS |
| 4 | El Drawer muestra «Facturación electrónica» **sin reiniciar** | PASS |
| 5 | Pulsar la opción abre `/ecf` | PASS |
| 6/7/8 | Desactivar: confirmación → `PATCH false` → el Drawer la oculta | PASS |
| — | Cancelar la desactivación no envía nada | PASS |
| 9 | Si el `PATCH` falla, se mantiene el estado confirmado y **no hay activación ficticia** | PASS |
| 10 | Sin permiso (`manageEcfConfig`) el interruptor está deshabilitado y no envía | PASS |
| 11 | Al cambiar de empresa **no se reutiliza** la bandera anterior | PASS |
| — | El Drawer **no genera ninguna petición HTTP** | PASS |
| — | Regresión de modelo: `copyWith` y `toMap` propagan `ecfEnabled` | PASS |
| — | Guardián estructural: el Drawer no referencia `ecfRepositoryProvider` ni `ecfCapabilitiesProvider` | PASS |

**Falsabilidad comprobada:** revirtiendo temporalmente la corrección del menú,
**4 de estas pruebas fallan** con `Found 0 widgets with text "Facturación
electrónica"`. No son pruebas que pasen por construcción.

### Regresión backend

`pwsh scripts/ecf-test-db/run-tests.ps1` → **1376 pasan / 8 omitidas, 127 suites**,
`ISOLATION OK: historical UAT unchanged` (708 empresas / 568 trials / 3462
documentos). Spec dedicado nuevo en `settings.service.spec.ts`:
`exposes the company e-CF switch as ecfEnabled, scoped to the authenticated
company`.

### Defectos encontrados y corregidos (los encontró la verificación)

1. **`CompanySettings.copyWith` perdía `ecfEnabled`.** `saveSettingsOrQueue` y
   `saveCompanyNameOrQueue` escriben el resultado de `copyWith` en la **caché
   local**, así que guardar los datos (o solo el nombre) de la empresa dejaba la
   caché con el e-CF apagado; una carga respaldada en caché ocultaba el módulo.
   Corregido propagando el campo.
2. **`toPublicSettings` no publicaba `ecfEnabled`.** `getSettings` construye la
   respuesta con ese mapeo, que no incluía el campo: la afirmación previa
   («el payload ya expone el flag») era **falsa** y solo se había comprobado con
   `tsc`. En producción el Drawer **siempre** habría leído `false`. Corregido con
   una única lectura `ecfEnabledFor()` y su publicación en las tres respuestas
   (`getSettings`, `updateSettings`, `updateCompanyName`).
3. **El Drawer mostraba «Más módulos» en vez del módulo.** El ítem cae en el
   grupo de sobrantes, y con un único elemento `hasSubmenu` es `false`: el tile
   pinta el título del grupo, así que la opción visible era «Más módulos».
   Corregido: con un solo ítem se usa **su propio nombre e icono** (móvil y
   escritorio).

El contrato de `settings.service.spec.ts` se **amplió** (se modeló
`ecfCompanyConfiguration`), no se debilitó: ningún `expect` se relajó.

### Ejecución Windows UAT

- Build correcto con ruta corta (`subst X:`): `Built
  build\windows\x64\runner\Debug\fullpos_cloud.exe`.
- **Causa exacta del anterior «Unable to start the app on the device»:** una
  instancia UAT previa del propio worktree (PID 29336, del 14-oct 15:36) retenía
  el mutex `Local\DaleVentasPOSSingleInstance`; `windows/runner/main.cpp` sale con
  `EXIT_SUCCESS` cuando ya existe una instancia. Cerrada esa instancia, el build
  nuevo **arranca y se mantiene** (PID 21732, «FullPOS Cloud - Sistema de
  facturación») y se capturó su pantalla de inicio de sesión (`PrintWindow`).
- **PASS visual limitado al arranque.** La comprobación visual del interruptor y
  del Drawer queda **BLOCKED**: exige una sesión autenticada con una empresa UAT y
  el build de depuración cae a un backend remoto cuando falta `API_BASE_URL`, así
  que **no se inició sesión ni se creó ningún negocio**. Sin PASS visual del
  interruptor.


## 4. Pruebas

`test/core/widgets/app_navigation_sections_test.dart` — **actualizada y ampliada**
(11 pruebas):

| Prueba | Qué fija |
| --- | --- |
| Con el módulo **apagado** la opción no existe | `ecfEnabled: false` → ausente |
| Con el módulo **encendido** aparece y va **AL FINAL** | `titles.last == 'Facturación electrónica'` |
| Encender **solo AÑADE** la opción | `on == [...off, 'Facturación electrónica']` |
| El resto del menú es idéntico con el módulo apagado | Facturación, Productos y Usuario siguen igual |
| Paridad desktop (ambas variantes de multi-almacén) | Árbol exacto sin `'Comprobantes e-CF'` |

La prueba de **paridad desktop** congelaba el árbol anterior: se actualizó de forma
explícita porque el cambio de menú es una decisión de producto de esta misión, no
un efecto colateral. **No se relajó ninguna expectativa** para tapar un defecto: se
sustituyó una entrada por otra, en la posición pedida.

## 5. Validación

```
flutter analyze                            → No issues found!
flutter test                               → 1329 passed, 1 skipped  (+4 nuevas)
git diff --check                           → DIFFCHECK_EXIT=0
```

Las 17 pruebas de Drawer que rompieron con el cableado **vuelven a pasar** tras
revertirlo.

## 6. Estado de las demás fases

| Fase | Estado |
| --- | --- |
| 1 · Auditoría | **COMPLETA** (§1) |
| 2 · Configuración de empresa | **PENDIENTE**: el interruptor existe en `EcfConfigPage`; llevarlo a Configuración de empresa y a `companySettings` es el paso que desbloquea el Drawer |
| 3 · Activación/desactivación segura | **PENDIENTE**: `PATCH /ecf/config` ya persiste por empresa y exige `manageEcfConfig`; falta el flujo de confirmación en la UI |
| 4 · Drawer | **PARCIAL**: compuerta implementada y probada; cableado pendiente (§3) |
| 5 · Navegación al módulo | **YA EXISTÍA** y sigue funcionando por ruta |
| 6 · Estados y UX | Implementado en la bandeja (14 estados, aceptación del proveedor ≠ DGII) |
| 7 · Seguridad | El backend ya exige empresa habilitada + permiso; sin cambios |
| 8 · Pruebas | Drawer cubierto; multiempresa y roles, cubiertos por suites previas |
| 9 · Ejecución visual | **BLOQUEADA** por infraestructura (ver `ECF_INTEGRATION_FINAL_GATE.md` §3) |
| 10 · Pendientes anteriores | Sin avance en esta sesión |

## 7. Riesgos

| Riesgo | Severidad | Estado |
| --- | --- | --- |
| El módulo no es alcanzable desde el menú para una empresa habilitada | **Media** | **Abierto**: es el paso que falta (§3) |
| Cualquier proveedor de red nuevo en el Drawer rompe 17 pruebas y acopla el menú a la red | Media | **Demostrado y evitado** |
| Prueba de paridad desktop actualizada | Baja | Justificada y documentada en §4 |

## 8. GO / NO-GO

| Entorno | Veredicto |
| --- | --- |
| **Desarrollo local** | **GO** — analyze limpio, 1329 pruebas, diff limpio |
| **UAT** | **GO CON RESERVA** — la integración del interruptor con el menú queda incompleta (§3) |
| **Sandbox Alanube / certificación DGII / producción / emisión real** | **NO-GO** (sin cambios respecto a la compuerta anterior) |
