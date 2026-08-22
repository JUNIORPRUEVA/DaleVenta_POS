# 📱 FASE 1 — PIPELINE MÓVIL DE IMÁGENES DE PRODUCTO (Android/iOS)

**Proyecto:** DaleVentas POS (FullPOS Cloud)
**Fecha:** 2026-08-22
**Estado:** Implementada y validada (analyze ✔, Android debug ✔, Windows debug ✔, tests ✔). **Sin commit/push.**

---

## A. Causa corregida

El flujo móvil cargaba la **fotografía original completa** en memoria (`FilePicker` con `withData: true`), la mantenía como `Uint8List` en el State, la **decodificaba entera** para la preview (`Image.memory` sin `cacheWidth`/`cacheHeight`) y la **subía sin comprimir** (`MultipartFile.fromBytes` con el original). Ese triple uso simultáneo de memoria disparaba OOM (Jetsam/LMK) y los HEIC de iPhone eran rechazados por el backend.

**Fase 1 corrige (solo Android/iOS):**
1. Ya no se usa `withData: true` en móvil → el original no se carga a RAM.
2. `image_picker` procesa de forma **nativa** (redimensiona, comprime, orienta y convierte HEIC→JPEG) y devuelve una ruta temporal.
3. La preview usa `Image.file` con `cacheWidth`/`cacheHeight` → no decodifica la imagen gigante.
4. La subida usa `MultipartFile.fromFile` (ruta del archivo optimizado) → sin copia completa en memoria.
5. La caché se siembra **solo con la versión optimizada**, nunca con el original.
6. Selector explícito **"Tomar foto / Elegir de galería"** en móvil.
7. Guardas anti doble-operación, `mounted` en todos los `await` y limpieza de temporales.

---

## B. Arquitectura final

```
Android/iOS:
Cámara / Galería (selector bottom-sheet)
   → image_picker.pickImage(maxWidth/maxHeight 1600, imageQuality 85, requestFullMetadata:false)
   → XFile (ruta temporal, JPEG, orientación aplicada, HEIC convertido)
   → copia a ruta única de la app (getTemporaryDirectory()/fulltech_product_images/)
   → preview optimizada (Image.file + cacheWidth/cacheHeight)
   → MultipartFile.fromFile(optimizado) → POST /products/upload
   → limpieza del temporal al terminar (dispose/upload completo)

Windows / escritorio:
   → flujo existente intacto (FilePicker con withData:true → bytes → fromBytes)
```

Detección de plataforma centralizada en `isMobileImagePlatform()` (solo Android/iOS; devuelve `false` en tests para no cambiar las pruebas existentes).

---

## C. Archivos modificados / creados

| Archivo | Motivo | Modificación | Plataforma |
|---|---|---|---|
| `lib/core/utils/mobile_product_image_picker.dart` **(nuevo)** | Pipeline móvil | `isMobileImagePlatform()`, `pickMobileProductImage()`, selector cámara/galería, `deleteMobileProductImageTemp()`, `buildMobileProductImagePreview()`, `mobileProductImageErrorMessage()` | Android/iOS |
| `lib/core/utils/mobile_product_image_platform_io.dart` **(nuevo)** | Impl. io (import condicional) | copia a ruta única, `Image.file` con caché, delete | Android/iOS (y stub web) |
| `lib/core/utils/mobile_product_image_platform_stub.dart` **(nuevo)** | Stub web-safe | no-op para web/otros | web (no usado) |
| `lib/features/catalogo/catalogo_screen.dart` | `_ProductForm` | móvil: selector + picker nativo + preview optimizada + `imageFilePath`; guard `_isPickingImage` + `mounted`; limpieza temporal en dispose | Android/iOS (Windows intacto) |
| `lib/features/products/ui/inventory_module_pages.dart` | Editor de producto | móvil: selector + picker nativo + preview optimizada + subida por ruta + caché optimizada + fix `_resolveSelectedImageForSave` + limpieza temporal | Android/iOS (Windows intacto) |
| `lib/features/catalogo/data/catalog_repository.dart` | `uploadImage` | nuevo parámetro `filePath` → `MultipartFile.fromFile` (mantiene `bytes` para escritorio/web) | Ambas (contract igual) |
| `lib/features/catalogo/application/catalog_controller.dart` | `create`/`update` | nuevo `imageFilePath`/`newImageFilePath`; siembra de caché **solo con versión optimizada** (`_seedImageCache`) | Ambas (params opcionales) |
| `test/features/products/inventory_product_editor_test.dart` | Fake del repo | firma de `uploadImage` actualizada al nuevo método | test |

---

## D. Dependencias

**No se agregó ninguna dependencia nueva.** Se utilizó `image_picker` (ya declarado en `pubspec.yaml`, resuelto en `pubspec.lock` **1.2.1** con `image_picker_android 0.8.13+14` e `image_picker_ios 0.8.13+6`), que estaba declarado y registrado como plugin pero sin uso.

**Por qué `image_picker` (nativo) y no el paquete `image` + `compute`:**
1. El paquete `image` (Dart puro) **decodifica la imagen completa a RAM** (48 MP ≈ 192 MB) antes de redimensionar → reintroduce el problema de memoria que buscamos eliminar.
2. `image_picker` con `maxWidth/maxHeight/imageQuality` procesa **en plataforma nativa** (no bloquea el isolate de Dart) y **aplica la orientación EXIF** automáticamente.
3. `image_picker` **convierte HEIC/HEIF→JPEG en iOS** durante el escalado, resolviendo el hallazgo HEIC sin código extra.
4. Compatibilidad: Android ✔ (photo picker + cámara; CAMERA ya declarado en el manifest), iOS ✔ (Info.plist ya tiene `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSMicrophoneUsageDescription`; deployment target 15.5 ≥ requerido 12).
5. Impacto en Windows: `image_picker` no es invocado en Windows (el branch `isMobileImagePlatform()` es false); se conserva `FilePicker`. La dependencia ya estaba presente en el proyecto, así que no cambia el build.

No se requirió `flutter_image_compress` ni `camera`.

---

## E. HEIC/HEIF (iPhone)

Una foto tomada con la cámara del iPhone llega como HEIC. El flujo nuevo usa `image_picker.pickImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, requestFullMetadata: false)`:

- En iOS, `image_picker` lee la imagen y, al solicitarse escalado/calidad, **re-codifica a JPEG** (la documentación del plugin indica que la imagen escalada en iOS siempre es JPEG). Esto convierte HEIC→JPEG de forma transparente.
- El resultado es un archivo `.jpg` ≤1600 px que el backend **acepta** (solo PNG/JPG/WEBP) y muy por debajo del límite de 15 MB.
- La orientación se aplica durante el escalado (`image_picker` usa la orientación EXIF al dibujar el bitmap), de modo que una foto vertical se conserva vertical.
- `requestFullMetadata: false` evita cargar metadatos EXIF/GPS completos (menos memoria).

No se muestra "Formato no soportado": el HEIC se normaliza antes del upload.

---

## F. Memoria — copias eliminadas

Antes (móvil): original en RAM (`withData:true`) + bitmap completo de preview + buffer `MultipartFile.fromBytes` + original en caché.

Ahora (móvil):
- ❌ Original completo en RAM — **eliminado** (`withData: true` ya no se usa).
- ❌ `Uint8List` del original en el State — **eliminado** (se usa `_pickedImagePath`; `_imageBytes` queda `null` en móvil).
- ❌ Bitmap gigante de preview — **eliminado** (`Image.file` + `cacheWidth`/`cacheHeight` 128/720).
- ❌ Original en la caché — **eliminado** (se siembra solo la versión optimizada, ≤1600 px).
- ✔ Única copia temporal: los bytes optimizados leídos para sembrar la caché (≤ ~1 MB, transitorio) cuando se usa `filePath`; el upload lee directo del archivo.

---

## G. Preview

- Catálogo (`_ProductForm`): `buildMobileProductImagePreview(path, width: 64, height: 64, cacheWidth: 128, cacheHeight: 128)` → decodifica a lo sumo 128 px.
- Inventario: `cacheWidth: 720, cacheHeight: 720`.
- Windows conserva `Image.memory` original (sin cambios).

---

## H. Upload

- **Móvil:** `MultipartFile.fromFile(filePath)` — lee el archivo optimizado directamente del disco, sin copia completa en memoria (`catalog_repository.uploadImage` con `filePath`).
- **Windows/escritorio:** `MultipartFile.fromBytes` (comportamiento previo intacto).
- El **contract del endpoint no cambia**: mismo campo multipart `file`, mismo `POST /products/upload`. No se tocó `multer` ni `memoryStorage` ni el límite de 15 MB.

---

## I. Windows — ruta intacta (evidencia)

Los diffs de `catalogo_screen.dart` e `inventory_module_pages.dart` muestran que el flujo desktop se conserva literal:

- En `_pickImage` el branch desktop es el código original:
  ```dart
  if (isMobileImagePlatform()) { await _pickMobileImage(); return; }
  // Windows / escritorio: comportamiento actual intacto (bytes con data).
  final result = await FilePicker.platform.pickFiles(... withData: true ...);
  _imageBytes = result.files.single.bytes; ...
  ```
- La preview desktop (`Image.memory(_imageBytes!, ...)`) queda sin cambios.
- `catalog_repository.uploadImage` mantiene `MultipartFile.fromBytes` cuando no hay `filePath`.
- `catalog_controller` mantiene `imageBytes` para el flujo por bytes.
- **Validación:** `flutter build windows --debug` → ✔ `Built build\windows\x64\runner\Debug\fullpos_cloud.exe`.

---

## J. Validaciones realizadas (resultados reales)

| Comando | Resultado |
|---|---|
| `dart format` (solo archivos de Fase 1) | ✔ 7 archivos formateados |
| `flutter analyze` | ✔ **No issues found!** |
| `flutter test test/features/products/inventory_product_editor_test.dart` | ✔ **24 passed** |
| `flutter test` catálogo (import + tax persistence) + product_image_url | ✔ passed |
| `flutter build apk --debug` | ✔ `Built build\app\outputs\flutter-apk\app-debug.apk` |
| `flutter build windows --debug` | ✔ `Built ...\Debug\fullpos_cloud.exe` |
| `flutter build web --release` | ❌ FALLA **preexistente**: `dart:ffi` en `lib/core/printing/windows_raw_printer_transport.dart` (sin cambios desde HEAD `33586a0f`; módulo de impresión, fuera de alcance de Fase 1). No aparece ningún archivo de Fase 1 en los errores. |

**Test preexistente fallido (ajeno a Fase 1):** `catalog_repository_stale_test.dart` → "concurrent refreshes use one GET /products" falla porque `fetchProducts(forceRefresh: true)` no reutiliza el future en vuelo (2 llamadas → 2 GET). Es lógica de `fetchProducts` que no fue tocada; se documenta para Fase 2.

---

## K. Pruebas todavía necesarias en teléfonos físicos

### Android
- Tomar foto con cámara (permiso concedido y denegado).
- Elegir de galería (imagen pequeña, grande, >10 MB).
- Foto vertical con orientación EXIF.
- Sustituir fotografía en edición.
- Crear producto sin foto / cancelar selección.
- Red 3G/4G lenta (reintento de subida).
- Doble toque en "Tomar foto"/"Galería"/"Guardar".
- Repetir 10+ ciclos y medir RAM (`adb shell dumpsys meminfo`) y caché (`/data/data/com.daleventa.pos/cache`).

### iPhone
- Foto con cámara (HEIC) → debe convertirse a JPEG y subir.
- Foto HEIC desde galería.
- Foto vertical con orientación EXIF.
- Permiso de cámara denegado → mensaje claro.
- Poca RAM / cierre previo → verificar que ya no hay Jetsam.
- Background durante el picker → estado del formulario.
- Repetir ciclos y observar `JetsamEvent` en logs.

> No se declara iOS validado: no hay iPhone/compilación iOS en este entorno Windows. Solo revisión estática (Info.plist ✔, deployment target 15.5 ✔).

---

## L. Pendientes para Fase 2 (deliberadamente no resueltos)

- Crashlytics/Sentry y observabilidad móvil (hallazgo C11).
- Reestructuración global de caché (límite por bytes; `putImageBytes` aún escribe en 2 claves; no se tocó en Fase 1 salvo que ahora recibe solo la versión optimizada).
- Timeouts globales de Dio (15 s) y manejo del dead-end de retry de 20 s en inventario (C7) — el flujo nuevo hereda el retry x3 existente, sin cambio de timeouts.
- Reintentos globales.
- Permisos explícitos de cámara/fotos con guía (C9) — se delega al picker nativo; la mejora de UX de permisos queda para Fase 2.
- Persistencia del formulario al volver de la cámara si el proceso se recrea (C6).
- `file_picker.clearTemporaryFiles()` (C10) — el flujo nuevo ya no usa temporales de file_picker en móvil, pero otros flujos sí.
- Fix `fetchProducts(forceRefresh: true)` dedup (test preexistente).
- Fix web: `windows_raw_printer_transport.dart` (dart:ffi) — fuera de alcance (impresión).
- No se tocaron: ventas, reportes, cotizaciones, compras, impresión, backend, límites.

---

## M. Estado Git final

```
Rama: main · HEAD: 359ef560
Modificados por Fase 1:
  lib/features/catalogo/application/catalog_controller.dart  (+51)
  lib/features/catalogo/catalogo_screen.dart                 (+79)
  lib/features/catalogo/data/catalog_repository.dart         (+24)
  lib/features/products/ui/inventory_module_pages.dart       (+99)
  test/features/products/inventory_product_editor_test.dart  (+3)
Nuevos (sin trackear):
  lib/core/utils/mobile_product_image_picker.dart
  lib/core/utils/mobile_product_image_platform_io.dart
  lib/core/utils/mobile_product_image_platform_stub.dart

Preexistentes sin tocar: reports_page.dart, purchase_order_pdf_service.dart,
cotizaciones_screen.dart, cotizacion_pdf_service.dart, ventas_repository.dart
```

**NO se hizo commit ni push. NO se ejecutó `git reset --hard` ni `git checkout --`.**
