# Integración de actividad y gestión fiscal — 15/11/2026

## Alcance y procedencia

Base productiva: `859bc5a985fd6d1f1e5dc816c10879b8c40a0ddd` (PR46).
Worktree exclusivo: `C:/src/fullpos-fiscal-activity-integration-20261115`.
Rama: `agent/fiscal-activity-integration-20261115`.

El propietario confirmó que el agente de actividades había terminado. El origen
quedó limpio en `0576cfd0`. La integración conserva por merge los commits
`ec6c2b05` (API, reporte y tabla auxiliar) y `0576cfd0` (cliente opcional), sin
reescribir historia ni tocar el worktree original. El merge `5db36b6b` conserva
también la totalidad de la integración fiscal, visual y de licencias anterior.
Las antiguas ramas de preparación de imágenes no son funcionalidades pendientes:
sus artefactos/recibos corresponden a versiones anteriores y no se fusionan
indiscriminadamente sobre el código actual.

## Cambios

- «Gestión fiscal» sustituye al menú «Postulación». Distingue facturas generadas
  de numeración y configuración, reutilizando las rutas existentes.
- La bandeja vacía distingue producción de pruebas y ofrece «Numeración fiscal».
  No simula documentos ni mezcla TEST con producción.
- El reporte administrativo de actividad exige el secreto de integración existente.
  Los pulsos usan empresa/sesión del JWT; rechazan campos de empresa enviados
  por el cliente. Consultas y unicidad permanecen separadas por empresa.
- La medición cuenta intervalos acotados en primer plano, descuenta inactividad,
  deduplica secuencias, limita frecuencia y conserva 35 días de pulsos auxiliares.
  No registra pulsaciones, contenido, documentos ni duración histórica inventada.
- El reporte devuelve estadísticas sin exigir la tabla opcional: informa
  `not_installed` cuando falta la migración.
- El arranque conserva el AppErrorOverlay sensible a login y añade el boundary
  opcional sin retirar los overlays, la activación ni el asistente existentes.
- Tests HTTP nuevos y ampliación del gate CI; imports de tests nuevos corregidos.

## Archivos modificados respecto a production-main

- `.github/workflows/multi-tenant-security.yml`
- `apps/api/.env.example`
- `apps/api/prisma/schema.prisma`
- `apps/api/prisma/migrations/20261115160000_add_company_usage_pulses/migration.sql`
- `apps/api/src/license/company-activity.controller.ts`
- `apps/api/src/license/company-activity.service.ts`
- `apps/api/src/license/company-activity.integration-spec.ts`
- `apps/api/src/license/company-activity-http.e2e-spec.ts`
- `apps/api/src/license/license.module.ts`
- `apps/api/src/usage-telemetry/usage-telemetry.interceptor.ts`
- `apps/fulltech_app/lib/core/usage/foreground_activity_meter.dart`
- `apps/fulltech_app/lib/core/usage/usage_activity_boundary.dart`
- `apps/fulltech_app/lib/core/widgets/app_navigation.dart`
- `apps/fulltech_app/lib/core/widgets/responsive_shell.dart`
- `apps/fulltech_app/lib/features/ecf/ui/ecf_documents_page.dart`
- `apps/fulltech_app/lib/main.dart`
- `apps/fulltech_app/test/core/usage/foreground_activity_meter_test.dart`
- `apps/fulltech_app/test/core/usage/usage_activity_boundary_test.dart`
- `apps/fulltech_app/test/core/widgets/app_navigation_sections_test.dart`
- `apps/fulltech_app/test/features/ecf/ecf_documents_page_test.dart`
- `docs/EXECUTION_STATE.md`
- `docs/INTEGRACION_ACTIVIDAD_GESTION_FISCAL_20261115.md`

## Validación y límites

Evidencia privada sin credenciales publicadas:
`C:/Users/pc/.codex/backups/fullpos-fiscal-activity-integration-20261115/`.

- `npm ci --ignore-scripts --no-audit --no-fund`: PASS,706 paquetes.
- `npm run api:build`: PASS; Prisma5.22 generado en este worktree.
- `npx prisma validate`: PASS.
- `npx prisma migrate deploy`: PASS solamente sobre las dos bases desechables
  locales de56701, después de verificar contenedor y binding loopback.
- `npm test -- --forceExit`:3362 PASS,101 omisiones condicionadas;282 suites PASS.
- Regresión fiscal PostgreSQL separada:32 PASS; no llamadas externas reales.
- `flutter analyze --no-pub`: PASS,89.1s. La primera ejecución detectó dos imports
  relativos en los tests recibidos, corregidos sin debilitar reglas.
- Primer grupo Flutter de actividad/bandeja/navegación:38 PASS.
- Lock Docker:756 paquetes verificados, sin cambios de dependencias.
- Regresión Flutter ampliada:767 PASS,164s, incluyendo e-CF, actividad,
  impresión, errores, arranque y navegación.
- HTTP:56 PASS en5 suites; la nueva frontera de actividad usa guard JWT
  simulado, mientras las suites PostgreSQL prueban el servicio real.
- `flutter build web --release`: PASS,80.7s, destino UAT local.
- Navegador: harness sintético con las vistas reales, validación final en curso.

Los primeros intentos del harness visual privado fallaron por un import faltante;
el harness es externo al repositorio. La primera invocación de la regresión
Flutter con entorno reducido no arrancó por falta de PROGRAMFILES(X86); se
repitió preservando las variables de herramientas de Windows. Estos fallos no
se presentan como pruebas satisfactorias.

## Producción

No se ejecutaron SSH, migraciones, cambios de datos, activaciones, reinicios ni
deploy en producción durante esta integración. No se emitieron comprobantes.
La tabla nueva es aditiva; no altera numeraciones, credenciales, licencias,
documentos históricos ni contadores. No habilitar colección antes de aprobar
separadamente su instalación y configuración.

`CRM_ACTIVITY_COLLECTION_ENABLED=false` y el build define
`ACTIVITY_REPORTING_ENABLED=false` conservan el comportamiento por defecto.
Una publicación del código no activa por sí misma la nueva medición.
El propietario aún puede añadir las ediciones visuales pendientes al mismo PR.

Estado de deploy: **NO-GO**, hasta cerrar validaciones y autorización de publicación.
