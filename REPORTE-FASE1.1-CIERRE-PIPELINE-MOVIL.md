# ✅ FASE 1.1 — CIERRE TÉCNICO DEL PIPELINE MÓVIL (Android/iOS)

**Proyecto:** DaleVentas POS (FullPOS Cloud)
**Fecha:** 2026-08-22
**Estado:** Implementada y validada (analyze ✔, tests ✔, APK debug ✔, Windows debug ✔). **Sin commit/push.**

---

## A. Problemas corregidos

1. **Coherencia formato real / extensión / MIME:** se detecta el **contenido real** del archivo devuelto por `image_picker` leyendo sus **magic bytes** (JPEG `FF D8 FF`, PNG `89 50 4E 47`, WebP `RIFF..WEBP`). La copia propia y el `filename` usan la extensión real y `detectImageMime(filename)` deriva el MIME coherente. Ya no se fuerza `.jpg`/`image/jpeg` sobre contenido PNG.
2. **Limpieza segura del temporal del plugin:** tras copiar a nuestra ruta propia (verificando que existe, no está vacía y no es la misma ruta), se elimina el temporal de `image_picker` (`NSTemporaryDirectory`/cache de la app). Nunca toca la galería del usuario.
3. **Pruebas específicas del pipeline móvil:** se añadieron 14 tests unitarios del pipeline + 1 test de subida por archivo + 2 tests de widget del flujo móvil del formulario.

---

## B. Formatos soportados

| Entrada (contenido real) | Salida (tras pipeline) | Extensión | MIME |
|---|---|---|---|
| JPEG/JPG | JPEG (sin recodificar; el picker ya lo optimizó) | `.jpg` | `image/jpeg` |
| PNG | PNG | `.png` | `image/png` |
| WebP | WebP | `.webp` | `image/webp` |
| HEIC/HEIF (iPhone) | JPEG (conversión nativa del picker ya auditada) | `.jpg` | `image/jpeg` |
| HEIC Android (raro, no normalizado) | No se etiqueta falsamente como JPEG; se conserva `.heic` → backend lo rechaza con mensaje claro | `.heic` | `null` (octet-stream) |
| Desconocido / sin detección | Se conserva la extensión del nombre del picker | según nombre | según `detectImageMime` |

> La señal usada es la más confiable: los **bytes reales del archivo** (magic bytes), no el nombre original (el picker pudo transformar el formato, p. ej. HEIC→JPEG).

---

## C. Temporales

- **Temporal del plugin (`image_picker`):** `NSTemporaryDirectory()` en iOS / `getCacheDir()` en Android (app-owned, verificado en el código del plugin). Se elimina **después** de que nuestra copia propia existe y no está vacía (`deletePluginTempSafely`). Si la copia falla, **no se borra**.
- **Temporal propio:** `getTemporaryDirectory()/fulltech_product_images/product_<ts>_<rand>.<ext>`. Es la fuente de verdad; se conserva durante el formulario y se limpia al cerrar (dispose) o al sustituir la imagen.
- **Protección del original del usuario:** ambas rutas son de la app (sandbox/cache); la foto de la galería del usuario nunca se toca. `deletePluginTempSafely` solo borra si la copia propia existe, es >0 y distinta.

---

## D. Tests nuevos

| Archivo | Test | Qué demuestra |
|---|---|---|
| `test/core/utils/mobile_product_image_picker_test.dart` (14) | JPEG | extensión `.jpg`, MIME `image/jpeg`, copia no vacía, temporal del plugin limpiado |
| 〃 | PNG | `.png`, `image/png`, **no** etiquetado como jpeg, temporal limpiado |
| 〃 | WebP | `.webp`, `image/webp` |
| 〃 | HEIC | contenido HEIC **no** se etiqueta falsamente como jpeg |
| 〃 | Origen inexistente | error controlado (copia falla) |
| 〃 | Params del picker | `maxWidth/maxHeight 1600`, `imageQuality 85`, `requestFullMetadata false` |
| 〃 | Cancelar | null, sin error, sin archivo propio |
| 〃 | Error del picker | `PlatformException` se propaga de forma controlada |
| 〃 | `deletePluginTempSafely` (4 casos) | elimina solo si copia existe, no vacía y distinta; no borra en misma ruta / copia faltante / vacía |
| 〃 | `isMobileImagePlatform` | false sin override; true con override iOS/Android |
| `test/features/catalogo/catalog_repository_upload_test.dart` (1) | `uploadImage(filePath:)` | `MultipartFile.fromFile` con `filename` y MIME correctos (JPEG y PNG) |
| `test/features/products/inventory_product_editor_mobile_image_test.dart` (2) | Flujo móvil del formulario | elegir de galería → nueva ruta → subida por archivo; y **doble selección** no abre el selector dos veces ni lanza dos uploads |

**Nota técnica:** los tests de widget requieren que los archivos se creen en `setUp` (zona normal) porque el cuerpo de `testWidgets` corre en `FakeAsync` (el IO real no completa ahí); el IO del pipeline se deja completar con `tester.runAsync`+`pump` alternados, y `debugDefaultTargetPlatformOverride` se restablece con `try/finally` (la invariante de Flutter se verifica antes que los `addTearDown`).

---

## E. HEIC

- **Demostrado por código (Fase 1.1 confirma):** `image_picker_ios` convierte HEIC→JPEG (galería PHPicker y cámara) — verificado en el código fuente del plugin.
- **Cubierto por test:** el pipeline móvil **no etiqueta falsamente** un contenido no-JPEG como `image/jpeg` (test HEIC), y el flujo JPEG produce `.jpg`/`image/jpeg`.
- **Sigue requiriendo iPhone real:** la conversión física HEIC→JPEG ocurre en código nativo que no se ejecuta en tests de Windows. Pendiente validación en iPhone.

---

## F. Android

`flutter build apk --debug` → **OK** (`Built build\app\outputs\flutter-apk\app-debug.apk`). Compila con `image_picker` y el pipeline nuevo. **Compilar ≠ validar en teléfono real.**

---

## G. iPhone

Entorno Windows → **no** se compila iOS, **no** hay simulador/iPhone. La validación física de HEIC, cámara y orientación queda pendiente (requiere Mac + Xcode + iPhone real).

---

## H. Windows

- La ruta desktop no se tocó: `FilePicker` (`withData:true`) → `_imageBytes` → `Image.memory` → `MultipartFile.fromBytes` (en `catalogo_screen.dart` e `inventory_module_pages.dart`, sin cambios en Fase 1.1).
- El cambio de Fase 1.1 es **solo** en `lib/core/utils/mobile_product_image_*` (solo móvil) y tests; los archivos trackeados de Fase 1 **no se modificaron** en Fase 1.1.
- `flutter build windows --debug` → **OK** (`Built ...\Debug\fullpos_cloud.exe`).

---

## I. Comandos ejecutados (resultados reales)

| Comando | Resultado |
|---|---|
| `dart format` (solo archivos de Fase 1.1) | ✔ formateados |
| `flutter analyze` | ✔ **No issues found!** |
| `flutter test` pipeline (14) + repositorio (1) + widget móvil (2) + inventario (24) | ✔ **40 passed / 0 failed** |
| `flutter build apk --debug` | ✔ APK generado |
| `flutter build windows --debug` | ✔ fullpos_cloud.exe |
| `git diff --check` | ✔ sin errores de whitespace (solo warnings de CRLF) |

---

## J. Fallos preexistentes (ajenos a Fase 1.1)

- `flutter build web` falla por `dart:ffi` en `lib/core/printing/windows_raw_printer_transport.dart` (módulo de impresión; **no introducido por Fase 1/1.1**). No se insistió en web según lo indicado.
- Test `catalog_repository_stale_test` "concurrent refreshes use one GET" falla (dedup de `fetchProducts(forceRefresh:true)`) — preexistente, fuera de alcance.
- Editor de **categorías** (`_CategoryEditorDialog`) aún usa `withData:true`/`Image.memory` en móvil — **reservado para Fase 2** (NO tocado).

---

## K. Estado Git

```
Rama: main · HEAD: 359ef560
Archivos Fase 1.1 (nuevos/sin trackear):
  lib/core/utils/mobile_product_image_picker.dart            (modificado en 1.1)
  lib/core/utils/mobile_product_image_platform_io.dart        (modificado en 1.1)
  lib/core/utils/mobile_product_image_platform_stub.dart      (modificado en 1.1)
  test/core/utils/mobile_product_image_picker_test.dart       (nuevo)
  test/features/catalogo/catalog_repository_upload_test.dart  (nuevo)
  test/features/products/inventory_product_editor_mobile_image_test.dart (nuevo)

Trackeados de Fase 1 (NO modificados en 1.1): catalog_controller, catalogo_screen,
catalog_repository, inventory_module_pages, inventory_product_editor_test.

Preexistentes sin tocar: reports_page, purchase_order_pdf_service, cotizaciones_screen,
cotizacion_pdf_service, ventas_repository.
```

**NO commit · NO push · NO deploy · NO dependencias nuevas · NO backend · NO Windows · NO categorías · NO `_handleCompanyChanged` · NO timeouts/retries globales.**

---

## L. Veredicto

**FASE 1 CERRADA CON PRUEBA FÍSICA PENDIENTE.**

El cierre técnico del pipeline móvil está completo y consistente (formato/extensión/MIME, temporales, tests). Queda pendiente únicamente la validación en dispositivos físicos (cámara, HEIC, orientación, RAM) — requerida en Android e iPhone, y la Fase 2.
