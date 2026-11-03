# Plan de commits atómicos — NO EJECUTADO

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-18**.

> **Nada de esto se ha ejecutado.** No hay `git add`, ni `commit`, ni `push`, ni
> `merge`. Este documento es una propuesta para revisión.

Estado: **114 cambios sin confirmar** (`git status --short`).

## 1. Reglas del plan

1. **Un commit por grupo**, en el orden indicado: cada uno compila y pasa sus
   pruebas por separado.
2. **Nunca `git add .`**: se añaden rutas explícitas.
3. Antes de cada commit: `git diff --cached` revisado y `git diff --check`.
4. Ningún fichero con secretos entra en ningún grupo (§4).

## 2. Grupos

### C1 — Prisma: esquema y migraciones e-CF

- **Objetivo:** establecer la base de datos del módulo.
- **Archivos:** `apps/api/prisma/schema.prisma`,
  `apps/api/prisma/migrations/20261014120000_*` … `20261016191000_*` (13 migraciones).
- **Dependencias:** ninguna (va primero).
- **Pruebas:** `npx prisma validate`, `prisma migrate deploy` sobre base desechable.
- **Riesgos:** dos `CREATE INDEX` no concurrentes sobre `ecf_evidences`; medir
  filas antes de aplicar en un entorno con datos.

### C2 — Backend: módulo e-CF

- **Objetivo:** motor fiscal, E31/E32/E34, habilitación DGII, clasificación F1,
  simulador y pruebas.
- **Archivos:** `apps/api/src/ecf/**`, `apps/api/src/app.module.ts`,
  `apps/api/src/main.ts`, `apps/api/src/common/uat-safety.ts`,
  `apps/api/src/common/redact-secrets*.ts`.
- **Dependencias:** C1.
- **Pruebas:** `run-focused.ps1 -Pattern "src/ecf"` y `tsc --noEmit`.
- **Riesgos:** ninguno sobre el POS (no importa `sales`).

### C3 — Backend: integración con el POS y ajustes

- **Objetivo:** contrato financiero legacy, snapshots fiscales y dependencias.
- **Archivos:** `apps/api/src/sales/sales.service.ts` (+ spec),
  `apps/api/src/settings/settings.service.ts` (+ spec),
  `apps/api/package.json`, `package-lock.json`, `package.json` (raíz).
- **Dependencias:** C1, C2.
- **Pruebas:** **legacy 10/10** (ejecutadas 2026-10-18) + suites de ventas.
- **Riesgos:** **alto** — es el área que factura todos los días. Revisar el diff
  línea a línea; no debe cambiar el contrato existente, solo añadirlo.

### C4 — Flutter: núcleo (rutas, permisos, configuración UAT)

- **Objetivo:** exponer el módulo en el cliente y blindar el perfil UAT.
- **Archivos:** `lib/core/api/api_routes.dart`, `lib/core/api/env.dart`,
  `lib/core/config/uat_api_config.dart`,
  `lib/core/auth/app_permissions.dart`,
  `lib/core/company/company_settings_model.dart`,
  `lib/core/routing/*`, `lib/core/widgets/*`,
  `lib/features/account/account_menu_screens.dart`,
  `lib/modules/ventas/mis_ventas_screen.dart`,
  `pubspec.yaml`, `pubspec.lock`, `test/core/config/*`.
- **Dependencias:** C2 (contratos).
- **Pruebas:** `flutter analyze`, `flutter test test/core`.
- **Riesgos:** `env.dart` y `app_router.dart` afectan a toda la app.

### C5 — Flutter: interfaz e-CF

- **Objetivo:** pantallas e-CF, diálogo F1, notas de crédito y pruebas.
- **Archivos:** `lib/features/ecf/**`, `test/features/ecf/**`,
  `test/features/account/ecf_company_toggle_drawer_test.dart`,
  `integration_test/ecf_visual_e2e_test.dart`.
- **Dependencias:** C4.
- **Pruebas:** `flutter test test/features/ecf`, `flutter analyze`.

### C6 — Windows: ficheros generados

- **Objetivo:** registrar los plugins nuevos del build de Windows.
- **Archivos:** `apps/fulltech_app/windows/flutter/generated_plugin_registrant.cc`,
  `.h`, `generated_plugins.cmake`.
- **Dependencias:** C4 (cambio de dependencias).
- **Riesgos:** bajo; son artefactos generados. Deben ir con el cambio de `pubspec`.

### C7 — Documentación

- **Objetivo:** informes, matrices y estado técnico.
- **Archivos:** los 57 ficheros `docs/ECF_*.md` y matrices nuevas
  (`ECF_E31/E32/E34_CERTIFICATION_MATRIX.md`, `ECF_CURRENT_TECHNICAL_STATUS.md`,
  `ECF_UAT_PROFILE_BUILD_SAFETY.md`, `ECF_COMMIT_PLAN.md`).
- **Dependencias:** C1–C6 (documentan lo anterior).
- **Riesgos:** ninguno funcional.

### C8 — Higiene del repositorio

- **Objetivo:** reglas de ignorado y plantilla de entorno.
- **Archivos:** `.gitignore`, `AGENTS.md`,
  `apps/api/.env.alanube.uat.local.example`.
- **Dependencias:** ninguna, pero debe ir al final para no alterar el entorno de
  los commits anteriores.
- **Riesgos:** `.gitignore` mal ajustado podría dejar fuera ficheros necesarios.

## 3. Archivos que NO son de este trabajo

| Archivo | Observación |
| --- | --- |
| `docs/settings-notifications-visual-evidence/settings-screen-units-rejected-desktop.png` | Modificados por otra sesión; **no atribuir** a este trabajo |
| `docs/settings-notifications-visual-evidence/settings-screen-units-rejected-mobile.png` | Ídem |
| `docs/settings-notifications-visual-evidence/settings-screen-units-rejected-mobile-closed.png` | Ídem |

Deben revisarse antes de incluirlos: si no pertenecen al cambio e-CF, van en un
commit propio o se descartan.

## 4. Verificación de secretos (antes de cualquier commit)

| Comprobación | Resultado |
| --- | --- |
| `.env.alanube.uat.local.example` contiene tokens o contraseñas | **No** — solo referencias (`env://…`) y banderas |
| `.env.alanube.uat.local` / `.env.ecf.visual.uat.local` en el índice | **No** — están ignorados |
| Claves privadas o certificados en el diff | **No detectado** |
| `ALANUBE_TEST_RNC` en el ejemplo | Identificador fiscal de prueba, **no** credencial |

Comando recomendado antes de cada commit:

```powershell
git diff --cached | Select-String -Pattern 'BEGIN .*PRIVATE KEY|password\s*=|token\s*=|secret\s*='
```

## 5. Orden de ejecución propuesto

```text
C1 -> C2 -> C3 -> C4 -> C5 -> C6 -> C7 -> C8
```

Cada paso debe dejar el árbol en estado compilable y con sus pruebas en verde
antes de pasar al siguiente.

## 6. Actualización 2026-10-18 — grupo C0 (seguridad UAT)

Commit **independiente y previo** a C4, porque toca el núcleo de red y sesión:

| Archivo | Cambio |
| --- | --- |
| `lib/core/config/uat_network_guard.dart` | **nuevo** — guardia de destinos UAT |
| `lib/core/api/env.dart` | resuelve las tres URLs a través de la guardia |
| `lib/core/api/api_client.dart` | sin redirecciones en UAT + interceptor de destino |
| `lib/core/auth/token_storage.dart` | prefijo `uat.` en las claves de sesión |
| `lib/core/offline/offline_store.dart` | SQLite y claves Web con nombre propio en UAT |
| `test/core/config/uat_network_guard_test.dart` | **nuevo** — 15 pruebas |
| `scripts/build/build_windows_ecf_uat.ps1` | **nuevo** — build oficial blindado |

Pruebas del grupo: `flutter analyze` y
`flutter test test/core/config/uat_network_guard_test.dart` (15/15).

**Riesgo:** toca `env.dart` y `api_client.dart`, que usa toda la aplicación. Es
el commit que más conviene revisar línea a línea; los builds comerciales no
cambian de comportamiento (la guardia solo actúa cuando `isUat` es true).
