# Cobro, turno y recuperación — corrección local, 2026-11-27

## Estado y alcance

GO para revisión de la implementación local. No se ha publicado, fusionado ni
desplegado. Producción y sus datos no se modificaron. No requiere migraciones,
cambios de API, credenciales ni configuración fiscal.

- Base: `production-main`, `ebc9486a6bba430efb929fe5ed5b5fe335b5cda7`.
- Rama: `agent/cobro-turno-recuperacion-20261127`.
- Worktree exclusivo: `C:/t/fp-cash-recovery-20261127`.
- Las aplicaciones ya abiertas desde otras ramas/worktrees se conservaron.

## Causas verificadas

1. El POS comprobaba únicamente `activeSession != null`. Ignoraba
   `canOperate`, `staleBusinessDate`, `requiresClosure`, `pendingClose` y
   `requiresReview` al abrir el pago.
2. El backend rechaza el turno fuera de su ventana antes de la transacción
   de venta. `sales.service.ts` resuelve la sesión antes de `prisma.$transaction`
   y devuelve códigos de caja tipados. La app conservaba todos los 409 como
   posibles cobros inciertos, incluso esos rechazos concluyentes.
3. La resolución manual conserva el registro como `review_resolved`. La
   reserva del mismo `clientRequestId` seguía encontrándolo. La prueba anterior
   de «mismo carrito» usaba una identidad nueva; no cubría el ticket original.

La revisión se hizo sobre código y contratos reales. No se consultó ni alteró
el registro productivo particular del incidente comunicado.

## Correcciones

- `CashGateState.checkoutBlockReason` centraliza el bloqueo de cobro. Un
  snapshot de caché de un día comercial anterior tampoco autoriza una venta
  nueva. Se usa el calendario existente de Santo Domingo.
- El POS verifica el dictamen antes de abrir el pago. Conserva carrito y ticket
  y muestra el aviso compacto existente. La preparación del pago es single
  flight: un doble toque no abre consultas/diálogos simultáneos. Un error de
  consulta se informa y libera ese bloqueo de interfaz para reintentar.
- El repositorio reconsulta la caja antes de reservar el intento durable:
  cubre que el turno cambie mientras está abierto el diálogo de pago. La
  validación del backend permanece intacta para cualquier carrera posterior.
- Solo los 409 cuyos `code` y `errorCode` coinciden con los rechazos de caja
  pretransaccionales comprobados liberan el intento local: `CASH_SESSION_STALE`,
  `ORIGIN_SESSION_CLOSED`, `ORIGIN_SESSION_NOT_FOUND`,
  `CASH_OPERATION_BEFORE_SHIFT` y `CASH_OPERATION_AFTER_CLOSE`.
  Timeout, 5xx, conflicto genérico y código contradictorio siguen protegidos.
- El mismo ticket puede continuar con una revisión de identidad nueva solo
  tras un archivo `RESOLVED_NOT_PERFORMED` con su ID de revisión confirmado.
  Se conservan payload, identidad y estado de los intentos anteriores.
- La revisión cero conserva exactamente el algoritmo de identidad anterior.
  Las siguientes incluyen su revisión en el hash de empresa, usuario,
  dispositivo y ticket. No se envía un campo nuevo al contrato de ventas.
- SQLite sigue reservando atómicamente: dos confirmaciones de la revisión
  nueva producen un solo POST financiero. Un resultado incierto conserva la
  misma identidad a través de reinicios. Una respuesta satisfactoria repetida
  conserva también esa identidad para la idempotencia del servidor.
- Ventas registradas, dinero declarado, retiradas no confirmadas o archivos
  sin prueba no autorizan una identidad nueva. La protección del ticket
  original no bloquea tickets independientes. Los datos de otra empresa o
  usuario no se usan como autorización.

## Validaciones ejecutadas

Directorio de Flutter: `apps/fulltech_app`.

| Comando | Resultado |
| --- | --- |
| `flutter pub get` | PASS |
| `flutter analyze --no-pub` | PASS, sin incidencias en la comprobación final |
| `flutter test --no-pub --concurrency=1 test/core/offline test/modules/cash test/modules/ventas test/modules/cotizaciones` | PASS: 795, omitidas 3 |
| `flutter test --no-pub --concurrency=1 test/modules/ventas/checkout_cash_recovery_test.dart test/core/offline/recovery_owner_switch_test.dart test/modules/cotizaciones/billing_ticket_removal_test.dart` | PASS final: 36; se solapa con la regresión, no sumar como pruebas únicas |
| `flutter test --no-pub --concurrency=1 test/features/ventas/ventas_offline_tax_ticket_test.dart test/features/ventas/ventas_fiscal_payload_test.dart test/features/catalogo/catalog_offline_uat_integrity_test.dart` | PASS: 16, omitidas 2 optativas de UAT |
| `flutter test --no-pub test/modules/cotizaciones/billing_ecf_selector_visible_test.dart --plain-name 'expired open shift'` | PASS: Windows, Android e iOS; capturas inspeccionadas |
| `flutter test --no-pub test/modules/cotizaciones/billing_ecf_selector_visible_test.dart --plain-name 'checkout ignores double taps'` | PASS |
| `flutter test --no-pub --platform chrome test/sale_ticket_withdrawal_web_test.dart` | PASS: 3 en Chrome real, con adaptación local del arnés descrita abajo |
| `flutter build windows --debug --no-pub` | PASS final; compilación de desarrollo, no instalador publicado |
| `flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn --dart-define=APP_ENV=uat --dart-define=API_BASE_URL=http://127.0.0.1:45991 --dart-define=APP_BASE_URL=http://127.0.0.1:45992` | PASS; artefacto UAT local, no productivo |
| `git diff --check` | PASS |

Las tres omisiones de la regresión amplia son pruebas optativas de
`offline_mayoreo_http_acceptance_test`, `offline_store_uat_copy_test` y
`phase16_process_worker_test`, que requieren su API descartable, copia UAT
o proceso hijo configurado. Las dos adicionales requieren las evidencias y el
API de su UAT histórico del catálogo. No se modificaron para hacerlas pasar.

### Pruebas reales frente a simulación

- Reales: transacciones, archivo y reapertura de SQLite en directorios
  temporales aislados; componentes reales de Flutter; render de Windows,
  Android e iOS mediante widget tests; SharedPreferences web en Chrome real;
  compilación de Windows y web.
- Simuladas: respuestas HTTP de caja, ventas y revisión administrativa con
  adaptadores Dio controlados. La prueba de retirada utiliza el repositorio
  real de recuperación y verifica su correspondencia de empresa, usuario,
  operación e importe. No se emitieron ventas ni comprobantes reales.
- No ejecutado: cobros en producción, validación física de impresoras ni una
  nueva compilación nativa de iOS. No son presentados como verificados.

### Incidencias durante la validación

- Dos fixtures antiguos de cambio de propietario no respondían `/cash/state`.
  Se añadió un turno válido perteneciente al propietario del ámbito y se
  conservaron sus comprobaciones de aislamiento y cancelación por cambio de
  identidad. Las pruebas finales pasan.
- La prueba estructural del retiro de tickets se delimitó a la función de
  finalización: ahora existe además un aviso de error previo al pago. Se
  conserva la exigencia de retirar únicamente después de persistir la venta.
- La prueba nueva de doble toque debía esperar la consulta asíncrona y la
  transición del diálogo, no la finalización de todas las animaciones del aviso.
  Conserva los asserts de una sola consulta y reapertura después del error.
- El fixture de la prueba nueva con CashRepository real necesitaba el mismo
  resolvedor de ámbito que el proveedor productivo. Se corrigió el fixture y
  se exigió el mensaje concreto de caja para no aceptar como éxito un rechazo
  por identidad. La pasada focalizada final de 36 pruebas pasa.
- Se corrigieron dos avisos de llaves en pruebas nuevas; el análisis final
  pasó sin incidencias.
- Flutter 3.41.6 en Windows produjo 404 al servir CanvasKit: el handler local
  comprueba un prefijo con `/` después de convertir la ruta a separadores de
  Windows. También fallaba la resolución del nombre de una prueba web anidada.
  La prueba web se dejó en la raíz de `test`. Un puente CDP efímero sirvió al
  navegador de prueba los dos archivos exactos del SDK instalado. No se
  cambió el SDK, la aplicación, sus respuestas de negocio ni los asserts.
  Utilidad local no versionada: `.uat/chrome_canvaskit_bridge.py`.

## Evidencias locales

- Logs: `apps/fulltech_app/.dart_tool/cash-regression-final.log`,
  `cash-core-verified.log`, `cash-analysis-verified.log`, `cash-sales-extra.log`,
  `cash-web-test-final.log`, `cash-windows-final.log`, `cash-web-build.log`.
- Capturas: `.uat/visual/stale-shift-checkout-blocked-windows.png`,
  `stale-shift-checkout-blocked-android.png`, `stale-shift-checkout-blocked-iOS.png`.
- Son evidencias locales descartables, no datos de empresas reales.

## Inventario de archivos

```text
apps/fulltech_app/lib/core/offline/offline_store.dart
apps/fulltech_app/lib/core/offline/pos_sale_identity.dart
apps/fulltech_app/lib/modules/cash/cash_models.dart
apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart
apps/fulltech_app/test/core/offline/recovery_owner_switch_test.dart
apps/fulltech_app/test/modules/cotizaciones/billing_ecf_selector_visible_test.dart
apps/fulltech_app/test/modules/cotizaciones/billing_ticket_removal_test.dart
apps/fulltech_app/test/modules/ventas/checkout_cash_recovery_test.dart
apps/fulltech_app/test/sale_ticket_withdrawal_web_test.dart
docs/PRODUCT_SPEC.md
docs/ARCHITECTURE.md
docs/audits/COBRO_TURNO_RECUPERACION_20261127.md
```

## Publicación pendiente

No hay commit, push, PR, merge ni deploy de esta corrección en esta tarea. El
alcance autorizado fue implementar y probar localmente. El código debe pasar
por revisión e integración y por la actualización de las aplicaciones antes
de que cambie el comportamiento de las instalaciones actuales. No se borraron
ni desbloquearon por intervención manual incidencias históricas productivas.
