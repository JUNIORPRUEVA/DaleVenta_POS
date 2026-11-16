# Portada fiscal y salida web — auditoría y corrección local

## Evidencia antes del cambio

Las capturas del propietario muestran una felicitación a pantalla completa en
cada entrada, un menú inferior de Gestión fiscal con acciones duplicadas y ayuda
en el appbar. El código confirma que el estado autorizado renderizaba siempre
EcfCompletedView y que el shell añadía el menú sin consultar la etapa fiscal.
La ayuda se registraba como acción de barra desde la página de habilitación.

Al salir, el router seleccionaba `/` mediante navegación interna de Flutter,
que construía el antiguo LandingScreen. Una recarga pedía `/` al servidor y
obtenía la página Astro nueva. Esto explica la diferencia sin atribuirla a caché.

## Plan y alcance

Worktree exclusivo C:/src/fullpos-fiscal-home-logout-20261115; rama
agent/fiscal-home-logout-20261115; base a495c356 (PR48 desplegado).
Auditar las capturas y el flujo real; retirar menú/ayuda de la barra; mostrar
accesos directos solo con capacidad real; limitar confirmación por empresa/usuario;
corregir el límite de navegación Flutter/Astro; pruebas y vista previa local.
Sin despliegue, migraciones ni cambios de backend/datos fiscales.

## Comportamiento

- Certificación autorizada y `posReady=true`: portada operativa compacta con
  facturas, numeración (si tiene permiso) y ventas. Sin felicitación permanente.
- Confirmación discreta una vez por empresa/usuario/dispositivo, guardada en
  SharedPreferences. No es una autorización fiscal y no concede capacidades.
  Al borrar datos del navegador puede volver a mostrarse una vez.
- Certificación autorizada pero emisión incompleta: conserva habilitación y
  numeración pendientes. La asistencia está dentro de esa sección, no en la barra.
- Empresa en proceso: conserva el asistente y la etapa resuelta por el backend.
- El shell no agrega el menú emergente Gestión fiscal ni accesos duplicados.
- En web, la ruta pública solicita navegación de documento con replace('/') y
  limpia la sesión temporal de Astro. La salida de Flutter sigue revocando/limpiando
  su sesión existente. Plataformas nativas conservan su ruta y portada anterior.

## Validación y evidencia

## Archivos

- apps/fulltech_app/lib/features/ecf/ui/ecf_fiscal_overview.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_config_page.dart
- apps/fulltech_app/test/features/ecf/ecf_fiscal_overview_test.dart
- apps/fulltech_app/test/features/ecf/ecf_config_numbering_test.dart
- apps/fulltech_app/lib/core/routing/app_router.dart
- apps/fulltech_app/lib/core/widgets/responsive_shell.dart
- apps/fulltech_app/lib/core/auth/public_website_entry.dart
- apps/fulltech_app/lib/core/auth/public_website_navigation.dart
- apps/fulltech_app/lib/core/auth/public_website_navigation_stub.dart
- apps/fulltech_app/lib/core/auth/public_website_navigation_web.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_dgii_habilitation_page.dart
- apps/fulltech_app/lib/features/ecf/ui/ecf_ready_home.dart
- apps/fulltech_app/test/core/auth/public_website_entry_test.dart
- apps/fulltech_app/test/features/ecf/ecf_dgii_habilitation_page_test.dart
- apps/fulltech_app/test/features/ecf/ecf_ready_home_test.dart
- docs/EXECUTION_STATE.md
- docs/AUDITORIA_PORTADA_FISCAL_SALIDA_20261115.md

## Resultados de las comprobaciones

- `flutter pub get`: PASS.
- `flutter analyze --no-pub`: PASS,91.9s.
- Regresión de e-CF, autenticación, rutas y arranque:544 PASS,117s.
- Grupo inicial específico:54 PASS, incluida preservación de caché al salir.
- `flutter build web --release --no-pub --no-wasm-dry-run` con destino UAT
  local: PASS,72.2s. Galería privada compilada aparte: PASS,31.4s.
- Playwright1440/390: PASS; aviso inicial, no repetición, aislamiento de empresa,
  pendiente conservado, navegación de documento y eliminación de sesión Astro.
  La página pública se sirvió desde un fixture real del build Astro local; no
  se inició/cerró ninguna sesión productiva ni se emitieron documentos reales.
- Se inspeccionaron capturas de empresa lista, primera confirmación y estado
  pendiente. Los primeros selectores del harness no contemplaban textos
  combinados de ListTile; se corrigió el selector privado, no el producto.
- Vista local: http://127.0.0.1:53900/. Los botones superiores son exclusivos
  de la galería ficticia y no se incorporan al appbar del producto.
- Sin cambios de API, schema, migraciones, contadores, numeración ni credenciales.

Evidencia privada: C:/Users/pc/.codex/backups/fullpos-fiscal-home-logout-20261115/.
Las comprobaciones iniciales de análisis y tests están junto a esa carpeta con
el prefijo fullpos-fiscal-home-logout-20261115-. No incluir backups en Git.

GO para revisión local. No se hizo commit, push, merge, deploy ni acceso SSH.
La confirmación es local al dispositivo/usuario/empresa; otro dispositivo puede
mostrarla una vez, y borrar el almacenamiento permite que aparezca nuevamente.

## Ajuste solicitado: portada con información fiscal

La portada de empresa lista ahora incluye tipos de comprobante y rangos del
backend de la sesión autenticada, con consumo, saldo, estado activo/inactivo y
vencimiento cuando existe. No calcula ni concede habilitaciones: E31/E32 usan
`posAvailableTypes`; E34 distingue la habilitación del tipo de los requisitos
de factura original y numeración. La consulta de rangos conserva estados de
carga, error con reintento y lista vacía diferentes. No se suman rangos históricos
como disponibilidad para emitir.

Se eliminó la aparición duplicada de `EcfSalesWithoutDocumentSection` en la
configuración fiscal; el componente y su uso en Configuración → Empresa siguen
intactos, con su confirmación y guardado existentes.

Validaciones repetidas sobre el ajuste: análisis completo sin incidencias
(83.1s), 546 pruebas de e-CF/autenticación/rutas/arranque PASS (119s), compilación
web UAT local PASS (81.4s). La primera ejecución específica detectó una prueba
antigua que exigía el switch duplicado; se actualizó para exigir su ausencia,
conforme al nuevo requisito. No se modificó la lógica de ventas sin comprobante.

Galería actualizada compilada PASS (46.6s). Playwright PASS a 1440 y 390 px:
tipos y tres rangos sintéticos visibles, switch ausente, aviso no repetido,
empresa pendiente conservada y salida al fixture Astro local. Se inspeccionaron
las capturas `ready-repeat-1440.png` y `ready-repeat-390.png`. En móvil el
contenido se desplaza verticalmente; no se comprimieron textos ni controles
para forzar su entrada en una sola pantalla. Sin comprobaciones productivas.

## Reducción de ruido y preparación de PR — 2026-11-16

Se retiraron subtítulos repetidos y estados positivos redundantes. E34 conserva
su explicación en una ayuda contextual; los tipos no disponibles, rangos
inactivos y errores de consulta siguen visibles. La galería privada concentra
sus escenarios en un menú; esos controles no forman parte del producto.

Análisis completo PASS (51.9s), grupo de 54 pruebas PASS, galería compilada PASS
(29.0s) y Playwright 1440/390 PASS sobre el diseño simplificado. Se revisó la
captura de escritorio final. No hubo acceso productivo para esta revisión.

El usuario pidió preparar el proceso de publicación. El alcance es PWA; no hay
cambios API/Prisma, migraciones ni permisos productivos. Se preparan commit/PR
y controles de GitHub. La regla previa de no hacer merge automáticamente se
conserva; el despliegue requiere el commit integrado y sus controles aprobados.
