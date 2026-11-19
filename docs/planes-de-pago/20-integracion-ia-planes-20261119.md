# Integración local de IA y planes — 19/11/2026

## Alcance y procedencia

Worktree exclusivo: `C:/src/fullpos-integrate-ia-planes-20261119`.
Rama: `agent/integrate-ia-planes-20261119`.
Base remota verificada: `e6e7e8fc` (`origin/production-main`).
La rama local llamada `production-main` está 399 commits detrás de esa base;
no se usa como fuente ni se modifica.

Se conservan mediante integración Git los commits originales:

- Planes: `21f61aeb`, `7f1abb04`, `47ce2790`.
- Consulta de cuenta IA: `1bb48ae0`.
- Diseño del chat: `19d3a57c`, `bf03b30e`, `b2fb1b54`.

El commit `13e039b1`, que retira módulos del menú, queda fuera por alcance.
Los cambios sin commit de otros worktrees, incluidas web pública, documentos,
capturas y generados, permanecen en su ubicación original.

## Compatibilidad y correcciones

- El conflicto de `license.service.ts` conserva el resumen de cuenta IA, pero
  no restaura los métodos retirados de activación/bloqueo/ampliación por
  autoservicio. La IA consulta; no concede licencias ni cambia su vigencia.
- El resumen IA utiliza nombre y límites efectivos del catálogo y concesiones,
  conservando el campo de plan anterior para consumidores existentes. No
  devuelve claves, notas internas ni contactos personales.
- La consulta de licencia de la aplicación muestra también los cupos efectivos
  de los clientes con catálogo; no anuncia un límite inferior al autorizado por
  una concesión. Los campos de límites configurados mantienen su significado.
- Las empresas sin catálogo no reciben un nuevo límite comercial de almacenes.
  La asignación de un plan sigue siendo una operación independiente y explícita.
- La creación de almacenes serializa por empresa antes de leer límite y uso.
  La lectura de concesiones se realiza dentro de la misma transacción.
- La activación/renovación respeta concesiones vigentes para conservar
  interruptores ya encendidos; no enciende módulos ni conserva concesiones
  vencidas. Los cupos base siguen guardándose sin sumar dos veces las excepciones.
- Las fechas pagadas vigentes se usan como inicio del periodo adicional.
  No se ejecuta backfill ni se cambia ninguna licencia existente por integrar código.

## Salvaguardas de publicación: reemplazan las instrucciones anteriores

Las secciones de migración automática en los documentos 18, 19 y el README
no deben utilizarse para este candidato. La configuración productiva conocida
mantiene `RUN_MIGRATIONS=false`; no se cambia a true como atajo.

Esta tarea autoriza implementación y pruebas locales únicamente. No autoriza
push, merge a `production-main`, despliegue, reinicios, variables productivas,
migraciones compartidas, seed productivo ni backfill aplicado.

Antes de una futura publicación se requiere:

1. Auditoría autorizada de licencias reales y estado de migraciones, solo lectura.
2. Comparar por empresa estado, vigencia, límites, funciones, uso y concesiones.
   No asignar Básico en masa ni sustituir contratos existentes por inferencia.
3. Revisar cuenta de transferencia, almacenamiento persistente de comprobantes
   y configuración de servicios externos sin divulgar secretos.
4. Respaldos y aprobación de un procedimiento manual de migraciones aditivas,
   separadas del arranque del servicio. Mantener seed general desactivado.
5. Autorizar por separado el catálogo si no existe. No aplicar backfill por defecto.
6. Construcción limpia fuera del host productivo, imágenes inmutables, hashes,
   cliente Prisma y contrato API/PWA comprobados; conservar imagen de reversión.
7. Publicar solo tras autorización expresa y controles del candidato integrado.

La API nueva necesita el esquema nuevo: no debe desplegarse con migraciones
pendientes suponiendo que `RUN_MIGRATIONS=false` las ejecutará automáticamente.

## Validación

Entorno: Node 24.14.1, Prisma 5.22.0, Flutter 3.41.6 / Dart 3.11.4.
Contenedor propio `fullpos_ia_planes_test_20261119`, etiquetado para la tarea y
enlazado exclusivamente a `127.0.0.1:56701`. Bases sintéticas independientes:
`fullpos_ecf_ephemeral_test`, `appyra_license_e2e` y `crm_license_fixture`.
Las 90 migraciones existentes se aplicaron únicamente a bases nuevas propias.
No se cambió ningún archivo de migración ni se accedió a la base productiva.
Las suites HTTP fiscales crean y limpian además bases efímeras con sus propios
prefijos dentro de ese mismo contenedor.

| Comprobación ejecutada | Resultado |
| --- | --- |
| `npm ci --no-audit --no-fund` | PASS; dependencias del lockfile, sin actualización |
| `npm run api:build` | PASS final; generación Prisma y TypeScript |
| `npx prisma validate` | PASS con destino local explícito |
| TypeScript estricto de los tres archivos de pruebas nuevos | PASS, configuración privada con `noEmit` |
| Cuatro suites dirigidas de compatibilidad, protección activa, almacenes y contexto IA | 35 PASS |
| Revalidación tras revisar el diff: compatibilidad, servicio de licencia, almacenes y contexto IA | 4 suites / 39 PASS |
| `npm --workspace apps/api test`, ejecución final posterior al ajuste de cupos visibles | 260 suites / 3.023 pruebas PASS; 57 suites / 594 pruebas opt-in omitidas |
| PostgreSQL de órdenes y nuevas regresiones de integración | 2 suites / 18 PASS; renovaciones concurrentes, excepciones, aislamiento y límite de almacenes |
| PostgreSQL fiscal: readiness, checkout atómico y devoluciones E34 | 3 suites / 32 PASS; proveedor real deshabilitado |
| PostgreSQL CRM/licencia/numeración fiscal | 1 suite / 1 PASS |
| HTTP IA, CRM, documentos y despacho DOSA local | 4 suites / 42 PASS, con `--forceExit` del harness existente |
| HTTP IA por separado, sin cierre forzado | 2 PASS; firma, caducidad, dirección y empresa del contexto |
| `node C:/Users/pc/.codex/backups/fullpos-integrate-ia-planes-20261119/compiled-api-smoke.cjs` | 12 comprobaciones PASS sobre `dist/main.js`: salud, firma obligatoria, dos empresas, catálogo, cupos y privacidad |
| `flutter pub get` | PASS; sin actualización de dependencias |
| `flutter analyze --no-pub` | PASS, sin incidencias |
| `flutter test test/core/ai_assistant test/features/plans --reporter expanded` | 73 PASS; incluye goldens y comportamiento de planes |
| `flutter test --reporter expanded` | 2.491 PASS / 10 SKIP, sin fallos; 10 min 40 s |
| `flutter build web --release --dart-define=API_BASE_URL=http://127.0.0.1:4000` | PASS, JavaScript/PWA local, 91,2 s; `build/web/index.html` y `main.dart.js` presentes |

Se inspeccionaron los goldens de chat a 390 y 1280 px que coincidieron con la
ejecución de sus pruebas. Es evidencia de widgets, no una nueva sesión visual
de producción ni una ejecución contra el servicio externo de IA.

Los 5.502 tests del informe anterior no se atribuyen a este candidato integrado.
Los conteos de suites generales y focalizadas se solapan: no deben sumarse.
La evidencia privada está en
`C:/Users/pc/.codex/backups/fullpos-integrate-ia-planes-20261119/`.

### Incidencias de validación corregidas y límites

- El fixture nuevo de almacenes omitía el usuario; se completó sin relajar
  autenticación. El análisis estricto detectó además un argumento omitido en
  otro fixture nuevo; se completó y el chequeo estricto final pasó.
- La primera ejecución de readiness no declaró `ECF_EMISSION_ENABLED=false`;
  su guarda detuvo el caso. Se corrigió el entorno de prueba y las tres suites
  fiscales finales pasaron. La suite CRM se ejecutó después con su fixture propio.
- Un build concurrente con Jest encontró la DLL Prisma retenida (`EPERM`). Se
  repitió secuencialmente al acabar Jest y el build completo pasó.
- El primer arranque del smoke compilado fue detenido por la guarda UAT por
  nombre de base no declarado. Se configuraron los valores esperados exactos
  de su base/puerto propios; no se cambió ni desactivó la guarda. El proceso
  final escuchó solo en loopback, se comprobó y se cerró; las filas sintéticas
  del smoke se retiraron exclusivamente por sus identificadores y prefijo.
- El harness HTTP completo usa `--forceExit`; el éxito de sus aserciones no
  demuestra ausencia de recursos abiertos del harness. El HTTP nuevo de IA
  también pasó sin esa opción.
- La comparación completa contra la base detecta cinco avisos de línea vacía
  final heredados de `47ce2790` (migración inicial de planes, script de evidencia,
  prueba de purga, servicio de órdenes y pantalla de pago). Se reprodujeron sin
  estos cambios. No se reescribe una migración ni se formatean archivos ajenos
  para ocultarlos. `git diff --check HEAD` de las correcciones propias pasó.
- Las advertencias de cuenta bancaria ausente y los errores fiscales inyectados
  pertenecen a escenarios locales; no se presentan como pagos o emisiones reales.
- El build web advierte incompatibilidades de dependencias con el ensayo Wasm;
  el build JavaScript solicitado pasó. No se declara soporte Wasm ni se actualizan
  dependencias para silenciar estos avisos.

Al finalizar se detuvo únicamente el contenedor propio, tras volver a comprobar
su etiqueta y enlace loopback. Se conservan sus datos locales. No se detuvieron
servicios ajenos. `git ls-remote` confirmó que la base remota sigue en `e6e7e8fc`.
Las siete revisiones fuente están conservadas como ancestros de la rama integrada.

**Estado de esta fase: GO para la integración y revisión local; NO-GO para
publicación o producción.** No se hizo push ni merge en `production-main`.

## Archivos de las correcciones propias

- `apps/api/src/license/license.service.ts`.
- `apps/api/src/license/orders/license-activation.service.ts`.
- `apps/api/src/license/plans/license-entitlements.service.ts`.
- `apps/api/src/warehouses/warehouses.service.ts`.
- `apps/api/src/license/license-active-protection.spec.ts`.
- `apps/api/src/warehouses/warehouses.service.spec.ts`.
- `apps/api/src/license/license-integration-compatibility.spec.ts`.
- `apps/api/src/license/license-integration-postgres.integration-spec.ts`.
- `apps/api/src/ai-assistant/ai-account-http.e2e-spec.ts`.
- `docs/planes-de-pago/18-preparacion-deploy.md`.
- `docs/planes-de-pago/19-publicacion-y-rollback.md`.
- `docs/planes-de-pago/README.md`.
- Este informe.

Los generados Flutter y las capturas de settings producidas por las pruebas
en el worktree propio no forman parte del cambio. El `.env` local es ignorado
y contiene exclusivamente un destino loopback de prueba; no se copió un entorno
de producción. El cliente compilado para validación local no es un paquete
aprobado para distribuir a clientes.

## Riesgos y siguiente fase

No se auditó la base productiva: no se garantiza por inferencia que las licencias
reales coincidan con los fixtures. Antes de publicar se deben revisar los estados,
vigencias y concesiones actuales, las migraciones pendientes, la cuenta bancaria
y el almacenamiento de evidencias. Las pruebas de OCR, pago, proveedor fiscal y
asistente externo no son una nueva transferencia bancaria ni una aceptación DGII.

No se fabricó una nueva prueba física de impresión ni un instalador Windows,
APK o paquete iOS. La interfaz importada se analizó y se probó como widgets
incluidos en la suite completa; la publicación multiplataforma conserva sus
procedimientos de release propios.

Esta fase solo prepara y valida la integración local. Push, merge productivo,
despliegue, cambios de entorno y migraciones compartidas siguen fuera de alcance.

## Inventario integrado contra la base remota

149 archivos, incluidos los commits originales y las correcciones propias.
No incluye pendientes sin commit de otros worktrees ni archivos privados.

- `.gitignore`.
- `apps/api/.env.example`.
- `apps/api/package.json`.
- `apps/api/prisma/migrations/20261116180000_license_plans_and_orders/migration.sql`.
- `apps/api/prisma/migrations/20261117170000_license_plan_requests/migration.sql`.
- `apps/api/prisma/migrations/20261117190000_evidence_insights/migration.sql`.
- `apps/api/prisma/migrations/20261117200000_provisional_activation/migration.sql`.
- `apps/api/prisma/migrations/20261117210000_evidence_validation/migration.sql`.
- `apps/api/prisma/migrations/20261119200000_license_override_multiwarehouse/migration.sql`.
- `apps/api/prisma/schema.prisma`.
- `apps/api/scripts/backfill-plan-basico.ts`.
- `apps/api/scripts/deploy-preflight.ts`.
- `apps/api/scripts/license-scenarios-evidence.ps1`.
- `apps/api/scripts/license-state.ps1`.
- `apps/api/scripts/plan-migration-check.ts`.
- `apps/api/scripts/seed-license-plans.ts`.
- `apps/api/src/ai-assistant/ai-account-http.e2e-spec.ts`.
- `apps/api/src/ai-assistant/ai-account.controller.ts`.
- `apps/api/src/ai-assistant/ai-assistant.module.ts`.
- `apps/api/src/ai-assistant/appyra-context.spec.ts`.
- `apps/api/src/ai-assistant/appyra-context.ts`.
- `apps/api/src/auth/auth.service.ts`.
- `apps/api/src/auth/jwt.strategy.spec.ts`.
- `apps/api/src/auth/jwt.strategy.ts`.
- `apps/api/src/ecf/sandbox/e32-sandbox.cli.ts`.
- `apps/api/src/guardian/guardian.alert.channels.ts`.
- `apps/api/src/license/crm-license-http.e2e-spec.ts`.
- `apps/api/src/license/crm-license.controller.ts`.
- `apps/api/src/license/crm-license.service.ts`.
- `apps/api/src/license/evidence/bank-transfer.analysis.spec.ts`.
- `apps/api/src/license/evidence/bank-transfer.analysis.ts`.
- `apps/api/src/license/evidence/ocr.engine.ts`.
- `apps/api/src/license/license-access.interceptor.spec.ts`.
- `apps/api/src/license/license-access.interceptor.ts`.
- `apps/api/src/license/license-active-protection.spec.ts`.
- `apps/api/src/license/license-company-purge.spec.ts`.
- `apps/api/src/license/license-integration-compatibility.spec.ts`.
- `apps/api/src/license/license-integration-postgres.integration-spec.ts`.
- `apps/api/src/license/license-trial.spec.ts`.
- `apps/api/src/license/license.access.policy.spec.ts`.
- `apps/api/src/license/license.access.policy.ts`.
- `apps/api/src/license/license.controller.ts`.
- `apps/api/src/license/license.module.ts`.
- `apps/api/src/license/license.service.spec.ts`.
- `apps/api/src/license/license.service.ts`.
- `apps/api/src/license/notifications/license-notifications.spec.ts`.
- `apps/api/src/license/notifications/license-notifier.service.ts`.
- `apps/api/src/license/notifications/license-reminder.scheduler.ts`.
- `apps/api/src/license/notifications/license.templates.ts`.
- `apps/api/src/license/notifications/meta-cloud.client.ts`.
- `apps/api/src/license/orders/license-activation.service.ts`.
- `apps/api/src/license/orders/license-evidence.storage.spec.ts`.
- `apps/api/src/license/orders/license-evidence.storage.ts`.
- `apps/api/src/license/orders/license-evidence.validation.spec.ts`.
- `apps/api/src/license/orders/license-evidence.validation.ts`.
- `apps/api/src/license/orders/license-order-insights.spec.ts`.
- `apps/api/src/license/orders/license-order-insights.ts`.
- `apps/api/src/license/orders/license-orders.integration-spec.ts`.
- `apps/api/src/license/orders/license-orders.service.ts`.
- `apps/api/src/license/orders/license-provisional.policy.spec.ts`.
- `apps/api/src/license/orders/license-provisional.scheduler.spec.ts`.
- `apps/api/src/license/orders/license-provisional.scheduler.ts`.
- `apps/api/src/license/orders/license-provisional.service.spec.ts`.
- `apps/api/src/license/orders/license-provisional.service.ts`.
- `apps/api/src/license/plans/license-entitlements.service.spec.ts`.
- `apps/api/src/license/plans/license-entitlements.service.ts`.
- `apps/api/src/license/plans/license-plans.service.spec.ts`.
- `apps/api/src/license/plans/license-plans.service.ts`.
- `apps/api/src/license/renewal/license-plan-request.service.spec.ts`.
- `apps/api/src/license/renewal/license-plan-request.service.ts`.
- `apps/api/src/license/renewal/license-renewal.policy.spec.ts`.
- `apps/api/src/license/renewal/license-renewal.policy.ts`.
- `apps/api/src/license/renewal/license-renewal.service.spec.ts`.
- `apps/api/src/license/renewal/license-renewal.service.ts`.
- `apps/api/src/settings/settings.service.spec.ts`.
- `apps/api/src/settings/settings.service.ts`.
- `apps/api/src/warehouses/warehouses.service.spec.ts`.
- `apps/api/src/warehouses/warehouses.service.ts`.
- `apps/fulltech_app/lib/core/ai_assistant/application/ai_assistant_controller.dart`.
- `apps/fulltech_app/lib/core/ai_assistant/domain/models/ai_assistant_message.dart`.
- `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart`.
- `apps/fulltech_app/lib/core/api/api_routes.dart`.
- `apps/fulltech_app/lib/core/license/license_demo_state.dart`.
- `apps/fulltech_app/lib/core/license/license_repository.dart`.
- `apps/fulltech_app/lib/core/routing/app_router.dart`.
- `apps/fulltech_app/lib/core/routing/route_access.dart`.
- `apps/fulltech_app/lib/core/routing/routes.dart`.
- `apps/fulltech_app/lib/core/widgets/responsive_shell.dart`.
- `apps/fulltech_app/lib/features/home/home_shell.dart`.
- `apps/fulltech_app/lib/features/plans/data/plans_repository.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/plans_open_provider.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/plans_shell.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/license_expired_screen_v2.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/license_overview_screen.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/license_suspended_screen.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/license_trial_ended_screen.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/orders_history_screen.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/payment_screen.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/plans_catalog_screen.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/preview/license_expired_v2_preview.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/preview/license_suspended_preview.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/screens/preview/license_trial_ended_preview.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/widgets/license_expiry_gate.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/widgets/license_notice_card.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/widgets/plan_card.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/widgets/plan_ui.dart`.
- `apps/fulltech_app/lib/features/plans/presentation/widgets/plans_action_mixin.dart`.
- `apps/fulltech_app/lib/features/plans/preview/plans_preview.dart`.
- `apps/fulltech_app/test/core/ai_assistant/ai_assistant_controller_test.dart`.
- `apps/fulltech_app/test/core/ai_assistant/ai_assistant_sheet_composer_test.dart`.
- `apps/fulltech_app/test/core/ai_assistant/goldens/assistant_1280.png`.
- `apps/fulltech_app/test/core/ai_assistant/goldens/assistant_390.png`.
- `apps/fulltech_app/test/core/ai_assistant/goldens/assistant_dock.png`.
- `apps/fulltech_app/test/core/ai_assistant/goldens/linux/assistant_1280.png`.
- `apps/fulltech_app/test/core/ai_assistant/goldens/linux/assistant_390.png`.
- `apps/fulltech_app/test/core/ai_assistant/goldens/linux/assistant_dock.png`.
- `apps/fulltech_app/test/features/onboarding/onboarding_flow_test.dart`.
- `apps/fulltech_app/test/features/plans/license_demo_state_test.dart`.
- `apps/fulltech_app/test/features/plans/license_expiry_gate_test.dart`.
- `apps/fulltech_app/test/features/plans/license_reactivation_test.dart`.
- `apps/fulltech_app/test/features/plans/license_suspended_screen_test.dart`.
- `apps/fulltech_app/test/features/plans/license_trial_ended_screen_test.dart`.
- `apps/fulltech_app/test/features/plans/plans_sections_test.dart`.
- `apps/fulltech_app/test/modules/cotizaciones/company_account_menu_navigation_test.dart`.
- `docs/planes-de-pago/00-estudio-informe-original.md`.
- `docs/planes-de-pago/01-inventario-tecnico-verificado.md`.
- `docs/planes-de-pago/02-plan-maestro-implementacion.md`.
- `docs/planes-de-pago/03-decisiones-pendientes.md`.
- `docs/planes-de-pago/04-catalogo-oficial-planes.md`.
- `docs/planes-de-pago/05-definicion-tecnica-de-planes.md`.
- `docs/planes-de-pago/06-proceso-de-activacion.md`.
- `docs/planes-de-pago/07-plan-implementacion.md`.
- `docs/planes-de-pago/08-arquitectura-verificada-real.md`.
- `docs/planes-de-pago/09-auditoria-completa.md`.
- `docs/planes-de-pago/10-estado-verificacion-d2.md`.
- `docs/planes-de-pago/11-implementacion-ejecutada.md`.
- `docs/planes-de-pago/12-preview-pantalla-planes.md`.
- `docs/planes-de-pago/13-estabilizacion-final.md`.
- `docs/planes-de-pago/14-auditoria-fraude-comprobantes.md`.
- `docs/planes-de-pago/15-correccion-a1-a6.md`.
- `docs/planes-de-pago/16-rediseno-catalogo.md`.
- `docs/planes-de-pago/17-demo-sin-interrupcion.md`.
- `docs/planes-de-pago/18-preparacion-deploy.md`.
- `docs/planes-de-pago/19-publicacion-y-rollback.md`.
- `docs/planes-de-pago/20-integracion-ia-planes-20261119.md`.
- `docs/planes-de-pago/README.md`.
- `docs/planes-de-pago/deploy-paths.txt`.
- `docs/planes-de-pago/fuentes/Informe_Integral_FullPOS_Planes_Pagos_Licencias_2026-11-07.pdf`.
- `docs/planes-de-pago/fuentes/informe-original-texto-extraido.txt`.
