# Revisión de mensajes al cliente — offline 48 h

Fecha: 2026-10-17. Worktree: `C:\src\fullpos-offline-safe-48h`.
Rama: `feature/offline-safe-48h`. Base: `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.

## Resultado y alcance

**HECHO:** el trabajo anterior ya filtraba algunos errores de sincronización y nombraba operaciones de caja, pero quedaban rutas que mostraban excepciones directamente, mensajes ambiguos y explicaciones que atribuían a falta de conexión un rechazo por inventario o revisión de turno.

Esta corrección revisa los mensajes de cobro, existencias, autorización para trabajar sin internet, almacenamiento local y operaciones pendientes de caja/ventas. No es una certificación de todos los textos de todos los módulos de la aplicación.

Los cambios son locales en el cliente Flutter. No se cambió el backend, su contrato, la autorización de 48 horas, los permisos, la selección de turnos, los estados de las operaciones, sus identificadores ni las reglas de reintento. No se generó instalador ni se actualizó una instalación. Los artefactos de aceptación de la Fase 17 corresponden a su código anterior y no certifican estos cambios posteriores.

## Hallazgos y correcciones

| Superficie | Hallazgo verificado en el código | Corrección |
| --- | --- | --- |
| Cobro de escritorio | El `catch` usaba directamente `e.message` o la excepción interpolada. | Filtro de presentación; diagnóstico original con pila en `TraceLog`. Si el resultado no se puede confirmar, indica revisar historial antes de volver a cobrar. |
| Existencias | Se reutilizaba una explicación de desconexión; se perdían el producto y cantidades al presentar el conflicto. | Traducción del código de existencias con `productName`, `requestedQuantity`, `availableQuantity` cuando vienen en la respuesta. Nunca se inventan esos valores. |
| Sincronización histórica | Un error técnico de rechazo podía convertirse en una promesa de envío al recuperar internet. | Un conflicto requiere revisar historial y consultar al encargado; no se presenta como falta de conexión. |
| Turno sin comprobar | Se recomendaba actualizar Fullpos como solución a `LEGACY_MISSING_SESSION`. | Explica que no se pudo comprobar el turno; pide revisión con soporte y prohíbe registrarlo en otro turno. |
| Estado del menú | Podía mostrar «Todo sincronizado» con operaciones detenidas para revisión. | «Revisión pendiente»; la cabecera conserva el estado de atención cuando hay conflictos. |
| Legibilidad | El error de sincronización y el aviso de cobro cortaban el mensaje a tres líneas. | Mensaje completo; ancho del aviso adaptado a pantalla. El error de cobro permanece 15 segundos y se puede cerrar. |
| Permiso de 48 h | Textos de validación local y cambios del reloj usaban lenguaje técnico. | Explican comprobar sesión, conectar el equipo, renovar permiso o revisar fecha/hora según el motivo real. |
| Almacenamiento | Algunos textos mostraban SQLite o garantizaban continuidad de forma demasiado amplia. | Explican que no se pudo guardar/abrir los datos, piden soporte y no afirman que el cobro esté completado. |
| Caja | El filtro quitaba prefijos, pero podía dejar el contenido técnico de una excepción. | Traduce conflictos conocidos y oculta el resto de detalles técnicos. |
| Detalles de producto | Una operación de eliminación mostraba el identificador interno del producto. | Conserva el identificador para la acción y los registros, pero no lo presenta como nombre de producto. |

Ejemplo sintético de existencias:

> No hay existencias suficientes de «Tela de prueba». Cantidad solicitada: 5. Disponible: 2. Revisa la cantidad y el inventario antes de cobrar. Registra una entrada solo si recibiste mercancía.

Los valores describen la respuesta al intento; no son una consulta continua del inventario. La corrección del texto no modifica stock ni resuelve por sí sola una operación de caja pendiente.

## Archivos de esta intervención

Rutas relativas a `apps/fulltech_app/`:

| Archivo | Intervención propia |
| --- | --- |
| `lib/core/errors/operation_error_message.dart` | Nuevo traductor de conflictos conocidos y respuestas históricas. |
| `lib/core/errors/user_safe_error_text.dart` | Traducción de mensajes conocidos y filtro de códigos/identificadores técnicos. |
| `lib/core/api/api_error_mapper.dart` | Presentación del conflicto conservando código, tipo, respuesta y diagnóstico originales. Se mantienen las explicaciones específicas de autenticación/permisos. |
| `lib/core/offline/sync_status_menu_button.dart` | Presentación histórica, cantidades, etiquetas y estado de revisión sin truncar instrucciones. |
| `lib/core/offline/sync_queue_service.dart` | Mensaje guardado para el cliente; clasificación y ejecución de operaciones intactas. |
| `lib/core/offline/offline_emergency_policy.dart` | Solo textos de los bloqueos existentes. |
| `lib/core/offline/offline_store.dart` | Solo textos de fallos de almacenamiento y resultado de cobro por confirmar. |
| `lib/modules/cash/cash_repository.dart` | Mensajes de turno y filtrado de mensajes recibidos. |
| `lib/modules/cash/cash_dialogs.dart` | Protección adicional frente a contenido técnico. |
| `lib/modules/ventas/data/ventas_repository.dart` | Mapeo de error de venta con diagnósticos conservados y textos de comprobante/conexión. |
| `lib/modules/ventas/registrar_venta_screen.dart` | Cantidades/precios en español y resultado de cobro incierto. |
| `lib/modules/cotizaciones/cotizaciones_screen.dart` | Aviso del cobro de escritorio: filtro, registro técnico, lectura completa, ancho y duración. El widget se expone con `visibleForTesting` para comprobar su presentación real. |
| `test/core/errors/operation_error_message_test.dart` | Traducción, cantidades decimales, datos ausentes y diagnóstico conservado. |
| `test/core/offline/sync_status_menu_button_test.dart` | Conflictos históricos, códigos desconocidos y estado de atención. |
| `test/core/offline/offline_message_ux_test.dart` | Avisos reales en 1366×768 y 360×640, texto al 130 %, cierre del aviso y operación pendiente intacta en SQLite temporal. |
| `test/modules/ventas/sale_attempt_durability_test.dart` | Caso nuevo de rechazo por stock que conserva el intento original y su identificador. El archivo ya existía sin seguimiento de Git antes de esta intervención. |
| `test/modules/cash/cash_dialogs_test.dart` | Caso nuevo de excepción técnica histórica de cierre. |
| `test/features/ventas/ventas_offline_tax_ticket_test.dart` | Expectativa del nuevo texto de autorización, manteniendo la prueba de bloqueo. |

También se agregó este informe. El worktree ya contenía 164 archivos modificados/sin seguimiento de fases anteriores; no se atribuyen a esta intervención los cambios previos de estos archivos ni del resto del árbol.

## Validación

Desde `apps/fulltech_app`:

```text
flutter analyze --no-pub
PASS — No issues found! (4.2 s), revalidado después de la revisión final.

flutter test --no-pub test/core/errors/operation_error_message_test.dart test/core/offline/sync_status_menu_button_test.dart test/core/offline/offline_message_ux_test.dart test/modules/ventas/sale_attempt_durability_test.dart test/modules/cash/cash_dialogs_test.dart test/features/ventas/ventas_offline_tax_ticket_test.dart --dart-define=OFFLINE_UX_SCREENSHOTS=true --reporter expanded
PASS — 47 pruebas.

flutter test --no-pub --reporter expanded
PASS — 1.350 pruebas aprobadas, 6 omitidas por las condiciones existentes de esas pruebas. Cero fallos. Código terminado antes de iniciar esta ejecución final; duración 3 min 35 s.
```

Desde la raíz:

```text
git diff --check
PASS — sin errores de espacios; avisos de normalización CRLF en archivos acumulados.
```

Las pruebas compilan los módulos Flutter importados. La prueba de venta usa un adaptador HTTP falso y almacenamiento temporal; comprueba que el rechazo conserva el intento y no cambia la respuesta a éxito. No ejecuta cobros ni ajustes de inventario reales.

La primera ejecución focal detectó dos supuestos incorrectos del test: el separador decimal local es coma y el diagnóstico existente no es JSON serializado. Se corrigieron las expectativas y el uso del mensaje ya traducido para conservar el detalle de producto. El análisis inicial encontró una llave faltante en un test y se corrigió. Una ejecución visual simultánea con la suite general falló al copiar `sqlite3.dll`; se repitió secuencialmente y pasó. La primera suite general tuvo dos fallos en los textos de autorización/caja; ambos casos pasaron después en las 47 pruebas focales. Una ejecución general posterior pasó con 1.349 pruebas y 6 omitidas. Tras acotar la traducción genérica para conservar las explicaciones de acceso/permisos y agregar su regresión, la comprobación final pasó con 1.350 pruebas y 6 omitidas. No se atribuye cobertura a las pruebas omitidas.

Capturas sintéticas locales inspeccionadas mediante Vision:

- `.uat/evidence/offline-message-ux/checkout-1366.png`
- `.uat/evidence/offline-message-ux/checkout-360.png`
- `.uat/evidence/offline-message-ux/sync-1366.png`
- `.uat/evidence/offline-message-ux/sync-360.png`

Usan la fuente Manrope incluida en el repositorio. Texto completo legible, sin desbordamiento observado; las capturas son de widgets reales en un entorno de pruebas, no del POS del cliente. El banco de pruebas no carga los glifos de iconos Material y aparecen cuadrados en esas capturas; no se cambiaron los iconos de la aplicación.

Registros: `.uat/offline-message-ux-analyze.log`, `.uat/offline-message-ux-focal.log`, `.uat/offline-message-ux-flutter-test-final.log`. No se repiten pruebas del backend/updater porque no se modifican en esta intervención. No se reclama validación nativa de un instalador nuevo.

## Seguridad y límites

- No se accedió a producción en esta intervención ni se modificaron datos reales.
- No se borraron pendientes, ventas manuales ni la cotización histórica fallida.
- No se cambian contratos, migraciones, configuración, permisos, idempotencia ni asignación de turnos.
- Los mensajes técnicos originales siguen en los registros/diagnósticos; no se convierten errores en éxito.
- Una respuesta histórica sin nombre o cantidades no permite mostrar el producto faltante con certeza.
- La instalación distribuida seguirá mostrando sus textos anteriores hasta una actualización autorizada y validada. Este cambio no publica ni actualiza clientes.

## Estado

**GO para el alcance local de mensajes revisados:** análisis limpio, compilación mediante pruebas, regresión general aprobada y presentación de los avisos comprobada en los dos tamaños indicados. No se emite autorización ni GO de publicación del producto. La instalación del cliente todavía no contiene estos cambios.
