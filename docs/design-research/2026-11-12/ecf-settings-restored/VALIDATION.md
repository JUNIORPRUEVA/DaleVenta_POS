# Restauración y simplificación de facturación electrónica

## Resultado

HECHO: implementado en el worktree `finalesdaleventas`, rama
`ultimos-trabajos`, sobre `b80ef90e`. No se hizo commit, push ni despliegue.

La desaparición del acceso se rastreó al commit `e2f9231e`, que retiró del drawer
el grupo de opciones restantes. La entrada e-CF seguía existiendo en la
navegación general, pero ningún grupo del drawer la recogía.

## Qué cambió

- El drawer incorpora una entrada explícita de facturación electrónica en móvil
  y escritorio, respetando el estado de la empresa y los permisos existentes.
  No se restableció «Más módulos» ni sus demás opciones.
- Empresa muestra un interruptor principal. Al activarlo aparecen el modo de
  precio (ITBIS incluido / Precio + ITBIS) y «Vender sin comprobante».
- La activación habilita impuestos y utiliza `TaxService` para vincular el
  impuesto predeterminado, dentro de la misma transacción. Se verificaron la
  conservación de un impuesto configurado y el rollback sin impuestos huérfanos.
- Desactivar el módulo conserva los impuestos y los datos históricos.
- La excepción se confirma en un diálogo que explica la selección por defecto
  en nuevas ventas y la responsabilidad de la empresa. Se conserva el aviso
  enviado por el servidor y las reglas de motivo y auditoría.
- El servidor añade `posReady` y `posAvailableTypes`. La preparación exige el
  módulo activo, estado `AUTHORIZED_SANDBOX` o `PRODUCTION_READY`, y numeración
  E31/E32 permitida, activa, no vencida y con saldo. No habilita emisión real.
- El selector de detalle permanece oculto antes de esa preparación. Las opciones
  electrónicas de cobro se limitan a los tipos disponibles. Ocultar el selector
  no elimina los bloqueos de cobro ni habilita ventas sin comprobante por defecto.
- La guía de activación y la vista previa de facturación reflejan el flujo nuevo.

El modo de precio conserva el guardado habitual mediante «Guardar empresa».
El interruptor del módulo y la excepción se guardan por sus acciones específicas.

## Validaciones realizadas

Todos los resultados siguientes proceden de comandos ejecutados localmente.
La API se compiló y probó en una copia temporal sin archivos `.env`, porque un
proceso local existente mantenía ocupada la DLL de Prisma en el worktree
(`EPERM` al generar el cliente). No se cerró ese proceso. Se verificó igualdad
binaria de los seis archivos e-CF modificados/nuevos entre el worktree y la copia.

| Comando | Resultado final |
| --- | --- |
| `npm ci` (copia aislada) | Código 0; 18 vulnerabilidades reportadas por npm |
| `npm run api:build` (copia aislada) | Código 0 |
| `npx prisma migrate deploy` (PostgreSQL local dedicado) | Código 0; 80 migraciones aplicadas |
| `npx prisma validate` | Código 0; esquema válido |
| `npm --workspace apps/api test` con pruebas PostgreSQL e-CF activadas | Código 0; 266 suites y 3206 pruebas aprobadas; 13 suites y 101 pruebas omitidas |
| `npm --workspace apps/api run test:e2e -- --runTestsByPath src/ecf/ecf-documents-http.e2e-spec.ts` | Código 0; 4 pruebas aprobadas |
| `npm --workspace apps/api test -- --testPathPatterns='ecf.service.spec\|ecf.module.spec\|ecf-pos-readiness'` | Código 0; 4 suites y 23 pruebas aprobadas |
| `flutter test --concurrency=1` | Código 0; 2178 aprobadas, 9 omitidas |
| `flutter analyze` (última ejecución) | Código 0; sin issues |
| `flutter test test/features/account/ecf_company_toggle_drawer_test.dart test/modules/ventas/ecf_pos_fiscal_test.dart test/modules/cotizaciones/billing_ecf_selector_visible_test.dart --concurrency=1` (última ejecución) | Código 0; 46 pruebas aprobadas |
| `git diff --check` | Código 0 |

La batería Flutter completa fue seguida únicamente por un ajuste de subtítulo
y del ayudante de capturas. Después se repitieron el análisis y las 46 pruebas
afectadas, con éxito. No se usaron exclusiones ni se relajaron validaciones.

Entorno de las pruebas de backend: PostgreSQL dedicado en loopback, puerto
55500, base `fullpos_ecf_ephemeral_test`; `ECF_POSTGRES_UAT=true`, `APP_ENV=uat`,
`UAT_LOCAL_ONLY=true`, `FINANCIAL_LEGACY_COMPAT=true`,
`ALANUBE_ENABLE_REAL_CALLS=false`, `ECF_EMISSION_ENABLED=false`.
Las pruebas de transporte simulado conservan sus guardas y adaptadores falsos.
El contenedor local `fullpos_ecf_finish_20261112` quedó detenido al terminar;
no se eliminaron sus datos de prueba.

En este Windows, Dart necesitó `TZ=AST4` para UTC−4. Para Node se usó
`TZ=America/Santo_Domingo`: una prueba mínima de Cron reprodujo el error de fecha
con `AST4` y su ausencia con el nombre IANA. No se cambió la zona del equipo.

### Evidencia funcional

- Pantalla real de Empresa y drawer real con repositorios simulados: activar,
  navegar pulsando el acceso, desactivar/cancelar, fallo al guardar, permisos,
  cambio de empresa y confirmación de la excepción.
- Pantalla real de facturación: selector visible con preparación confirmada y
  oculto para empresa nueva; una respuesta antigua no presupone preparación.
- PostgreSQL real: activación fiscal atómica, impuesto predeterminado válido,
  rollback, impuesto configurado conservado, rangos de otro tenant ignorados,
  rango agotado y rango vencido.
- HTTP real y PostgreSQL: login, E31, E32, E34 parcial/total, exceso de crédito,
  idempotencia y despacho simulado. Las aceptaciones usadas como precondición
  son sintéticas; no representan aceptación oficial.
- Regresión completa de backend y Flutter, incluyendo caja, inventario,
  almacenes, ventas, licencias y aislamiento cubiertos por sus suites.

### Incidencias registradas y corregidas

- Se actualizaron expectativas de pruebas que buscaban controles retirados o
  exigían ocultar e-CF del drawer aun estando activado.
- Hubo una colisión de invocaciones Flutter con la DLL de SQLite; la pasada
  final se ejecutó secuencialmente.
- Una pasada quedó invalidada al cambiar una función mientras el compilador
  conservaba la versión anterior. La ejecución limpia posterior pasó.
- Se corrigieron una importación innecesaria y el uso de una API protegida en
  el ayudante de capturas. El análisis final quedó limpio, sin ignorar reglas.
- Jest emitió un aviso de cierre tardío en pruebas de aplicación completa.
  La misma prueba HTTP se repitió sobre el código original de `b80ef90e`, cuyo
  árbol coincidía con producción al inicio: las 4 aserciones pasaron y apareció
  el mismo aviso. Ambas ejecuciones terminaron con código 0.

## Evidencia visual

Capturas de widgets reales renderizados por Flutter, con datos y backend
simulados; no son una sesión de navegador ni una conexión a producción.
Se inspeccionó el bloque fiscal en 390×844, 834×1112 y 1264×681, sin overflow
detectado en las pruebas. Se verificaron los estados apagado, activado,
confirmación y drawer. Las capturas de panel aíslan el área modificada; algunas
etiquetas de botones compartidos fuera de ella usan la fuente de prueba del
motor y no se presentan como evidencia de su tipografía en producción.

| Ancho | Panel activo | Confirmación | Drawer |
| --- | --- | --- | --- |
| 390 | [Panel](empresa-390-activo-panel.png) | [Diálogo](empresa-390-confirmacion.png) | [Menú](drawer-390.png) |
| 834 | [Panel](empresa-834-activo-panel.png) | [Diálogo](empresa-834-confirmacion.png) | [Menú](drawer-834.png) |
| 1264 | [Panel](empresa-1264-activo-panel.png) | [Diálogo](empresa-1264-confirmacion.png) | [Menú](drawer-1264.png) |

Contraste calculado con los colores del bloque fiscal: texto de cuerpo sobre
blanco 5.91:1; título sobre blanco 16.13:1; texto del aviso sobre su fondo 7.24:1.
Esta comprobación no certifica todas las demás áreas de la aplicación.

Para regenerar las capturas, definir `FULLPOS_QA_OUTPUT` apuntando a esta carpeta
y ejecutar `flutter test test/features/account/ecf_company_toggle_drawer_test.dart`.
Los registros completos de esta sesión permanecen en `%TEMP%`, bajo los prefijos
`fullpos-ecf-fix-*` y `fullpos-ecf-final-*`; no se copiaron secretos al repositorio.

## Archivos modificados

```text
apps/api/src/ecf/ecf.module.ts
apps/api/src/ecf/ecf.service.ts
apps/api/src/ecf/ecf.service.spec.ts
apps/api/src/ecf/documents/ecf-document-query.service.ts
apps/api/src/ecf/documents/ecf-pos-readiness.spec.ts
apps/api/src/ecf/documents/ecf-pos-readiness-postgres.integration-spec.ts
apps/fulltech_app/lib/core/widgets/app_drawer.dart
apps/fulltech_app/lib/features/account/account_menu_screens.dart
apps/fulltech_app/lib/features/ecf/ecf_models.dart
apps/fulltech_app/lib/features/ecf/ui/ecf_config_page.dart
apps/fulltech_app/lib/features/onboarding/presentation/widgets/activation_guide_column.dart
apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart
apps/fulltech_app/lib/modules/ventas/ecf_pos_fiscal.dart
apps/fulltech_app/lib/modules/ventas/preview/cotizaciones_screen_entry.dart
apps/fulltech_app/test/core/widgets/app_drawer_all_options_reachable_test.dart
apps/fulltech_app/test/features/account/account_settings_navigation_test.dart
apps/fulltech_app/test/features/account/ecf_company_toggle_drawer_test.dart
apps/fulltech_app/test/features/ecf/ecf_sales_without_document_section_test.dart
apps/fulltech_app/test/modules/cotizaciones/billing_ecf_selector_visible_test.dart
apps/fulltech_app/test/modules/ventas/ecf_pos_fiscal_test.dart
docs/PRODUCT_SPEC.md
docs/design-research/2026-11-12/ecf-settings-restored/VALIDATION.md
```

También se añadieron 18 PNG en esta carpeta: para cada ancho, drawer, Empresa
apagada/activa, confirmación y recortes de los paneles apagado/activo.
Se restauró la imagen ajena al alcance que una prueba de notificaciones regeneró.
Los cinco elementos sin seguimiento preexistentes se conservaron intactos.

## Riesgos y pendientes

- Falta confirmar empresa de certificación y destino sandbox para un ensayo
  externo de DOSA. Las pruebas realizadas no acreditan emisión fiscal real.
- El cliente nuevo requiere los campos de preparación de la API nueva. Una API
  antigua produce un estado conservador sin selector; la publicación debe
  coordinar ambas versiones.
- No se verificaron migraciones, contenedores ni despliegue en producción.
  No se modificó producción ni ninguna base compartida.
- Las vulnerabilidades reportadas por npm no se actualizaron fuera de alcance.

## Estado

Correcciones y validación local: aprobadas.

NO-GO para declarar cerrado el módulo fiscal completo o autorizar emisión real:
queda pendiente el ensayo externo en un entorno de certificación confirmado.

## Continuación: FULLTECH y preflight externo TEST

La empresa se confirmó posteriormente como FULLTECH, SRL. Las consultas de
solo lectura comprobaron su postulación vinculada, cierre DOSA autenticado,
credenciales TEST/PRODUCCIÓN activas, autorización administrativa y rangos
declarados E31/E32/E34. No es necesario repetir su certificación.

Las comprobaciones externas sin documento fiscal detectaron una diferencia
real en el envoltorio de líneas enviado a DOSA. Se corrigió localmente y se
documentaron los resultados, la regresión y los pendientes del contrato en
[DOSA TEST preflight](../../../ecf/DOSA_TEST_PREFLIGHT_2026-11-12.md).
La aceptación de una factura completa y la confirmación del rango TEST siguen
pendientes. Esto actualiza la referencia anterior a empresa/destino sin
confirmar; no convierte las simulaciones locales en aceptación fiscal.
