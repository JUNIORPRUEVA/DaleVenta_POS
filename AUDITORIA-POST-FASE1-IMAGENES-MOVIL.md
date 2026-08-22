# 🔍 AUDITORÍA POST-CORRECCIÓN — FASE 1 (pipeline móvil de imágenes de producto)

**Proyecto:** DaleVentas POS (FullPOS Cloud)
**Fecha:** 2026-08-22
**Tipo:** Solo lectura — NO se modificó código, NO commit, NO push.
**Base:** Verificación desde el código actual (no desde informes) + código fuente real de `image_picker 1.2.1` (`image_picker_ios 0.8.13+6`, `image_picker_android 0.8.13+14`) en el caché local de pub.

---

## 1. Estado del repositorio

**Rama:** `main` · **HEAD:** `359ef560`

**Archivos modificados por Fase 1 (verificados, coinciden con la implementación):**
- `lib/features/catalogo/application/catalog_controller.dart` (+51)
- `lib/features/catalogo/catalogo_screen.dart` (+79)
- `lib/features/catalogo/data/catalog_repository.dart` (+24)
- `lib/features/products/ui/inventory_module_pages.dart` (+99)
- `test/features/products/inventory_product_editor_test.dart` (+3, fake)

**Archivos nuevos de Fase 1 (sin trackear):**
- `lib/core/utils/mobile_product_image_picker.dart`
- `lib/core/utils/mobile_product_image_platform_io.dart`
- `lib/core/utils/mobile_product_image_platform_stub.dart`

**Archivos ya modificados antes de Fase 1 (NO tocados, verificados con diff):**
- `reports_page.dart`, `purchase_order_pdf_service.dart`, `cotizaciones_screen.dart`, `cotizacion_pdf_service.dart`, `ventas_repository.dart`

> Nota: entre sesiones hubo un formateo externo de `mobile_product_image_picker.dart`, `catalogo_screen.dart` e `inventory_module_pages.dart`. Contenido semánticamente idéntico; `flutter analyze` limpio.

---

## 2. Pipeline real implementado (trazado desde el código actual)

### Crear producto — Catálogo (`_ProductForm`, `catalogo_screen.dart`)
| Paso | Archivo · Clase · Método | Objeto | RAM | Disco |
|---|---|---|---|---|
| Usuario pulsa "Seleccionar archivo" | `catalogo_screen.dart` `_ProductFormState._pickImage` L3080 | — | — | — |
| Guard móvil | `isMobileImagePlatform()` (L3083) → `_pickMobileImage()` | — | — | — |
| Selector cámara/galería | `mobile_product_image_picker.dart` `showMobileProductImageSourceChooser` → bottom sheet | — | — | — |
| Picker nativo | `pickMobileProductImage` → `ImagePicker().pickImage(source, maxWidth:1600, maxHeight:1600, imageQuality:85, requestFullMetadata:false)` | `XFile` | **no original** | tmp del plugin (app) |
| Copia a ruta propia | `copyToUniqueAppPath` (`_platform_io.dart`) → `getTemporaryDirectory()/fulltech_product_images/product_<ts>_<rand>.jpg` | `File` | — | app tmp (nuestra copia) |
| Estado | `_pickedImagePath` (String) · `_imageBytes = null` | — | solo la ruta | la copia |
| Preview | `buildMobileProductImagePreview(path, 64×64, cacheWidth/Height 128)` → `Image.file` | bitmap ≤128px | ~0.07 MB | la copia |
| Guardar | `_submit` L3136 → `controller.create(imageBytes:null, imageFilePath:path, filename:…)` | — | — | — |
| Subida | `CatalogController.create` → `repo.uploadImage(bytes:null, filePath:path)` → `MultipartFile.fromFile` | `MultipartFile` | bytes leídos por dio al enviar (archivo optimizado) | la copia |
| Caché | `_seedImageCache` → `readLocalFileBytes(path)` (optimizado, pequeño) → `putImageBytes` | `Uint8List` pequeño transitorio | ~≤1 MB transitorio | caché (optimizado) |
| Backend | `POST /products/upload` (multipart `file`) | — | — | — |
| Cleanup | `dispose` → `deleteMobileProductImageTemp(_pickedImagePath)` | — | — | se borra la copia |

**Confirmado:** el formulario de catálogo usa el pipeline nuevo en móvil.

### Crear/editar producto — Inventario (`_InventoryProductEditorPageState`, `inventory_module_pages.dart`)
| Paso | Archivo · Clase · Método | Objeto | RAM | Disco |
|---|---|---|---|---|
| Pulsar imagen | `_pickImage` L7124 → móvil → `_pickMobileImage` | — | — | — |
| Selector | `showMobileProductImageSourceChooser` | — | — | — |
| Picker nativo | `pickMobileProductImage` (mismos params) | `XFile` | no original | tmp plugin |
| Copia a ruta propia | `copyToUniqueAppPath` | `File` | — | app tmp |
| Estado | `_pickedImagePath` · `_imageBytes = null` | — | ruta | copia |
| Subida inmediata | `_startSelectedImageUpload(filePath:path)` → `_uploadSelectedImageWithRetry` → `repo.uploadImage(filePath:path)` → `fromFile` | `MultipartFile` | — | la copia |
| Caché | `_seedOptimizedImageCache` (optimizado) | — | ≤1 MB transitorio | caché optimizado |
| Preview | `buildMobileProductImagePreview(path, cacheWidth/Height 720)` → `Image.file` | bitmap ≤720px | ≤ ~2 MB | la copia |
| Guardar | `_save` → `_resolveSelectedImageForSave` (espera `_imageUploadFuture`) → `create/update` con `fotoUrl` | — | — | — |
| Cleanup | `dispose` (tras `_imageUploadFuture.whenComplete`) | — | — | se borra la copia |

**Confirmado:** el editor de inventario usa el pipeline nuevo en móvil.

---

## 3. ¿El original ya no se carga en RAM en móvil? (patrones)

| Patrón | Dónde | ¿Alcanzable en Android/iOS? | ¿Windows? | Riesgo móvil |
|---|---|---|---|---|
| `withData: true` | `catalogo_screen.dart` L3100 (`_ProductForm`) | **NO** (early return móvil L3083) | SÍ | — |
| `withData: true` | `inventory_module_pages.dart` L7142 (editor producto) | **NO** (early return móvil L7132) | SÍ | — |
| `withData: true` | `inventory_module_pages.dart` L5350 (**`_CategoryEditorDialog`**, imagen de categoría) | **SÍ** ⚠️ | SÍ | **REMANENTE** (pre-Fase 1, fuera del alcance "foto de producto"; mismo riesgo OOM con imagen de categoría) |
| `withData: true` | `inventory_module_pages.dart` L1178 (import CSV) y `catalogo_screen.dart` L1033 (export/import CSV) | SÍ (archivos CSV pequeños) | SÍ | Bajo (no es foto) |
| `readAsBytes` | `_seedImageCache`/`_seedOptimizedImageCache` vía `readLocalFileBytes` | SÍ, **solo del archivo optimizado ≤1600px** | solo si filePath (no en Windows) | Bajo (bytes optimizados) |
| `readAsBytesSync` | `core/printing/ticket_builder.dart` L34 (impresión ESC/POS) | SÍ | SÍ | Fuera de alcance (impresión); posible bloqueo main-thread con logo grande |
| `Image.memory` | `catalogo_screen.dart` L3319 (preview producto) | **NO** (`_imageBytes` null en móvil) | SÍ | — |
| `Image.memory` | `inventory_module_pages.dart` L7714 (preview producto) | **NO** (`_imageBytes` null en móvil) | SÍ | — |
| `Image.memory` | `inventory_module_pages.dart` L5428 (preview categoría) | **SÍ** ⚠️ | SÍ | **REMANENTE** (categoría) |
| `MultipartFile.fromBytes` | `catalog_repository.dart` L324 (rama `else`) | **NO** (móvil siempre `filePath`) | SÍ | — |

**Conclusión:** para el flujo de **foto de producto**, Android/iOS ya no cargan el original a RAM. **Observación:** el editor de **categorías** (mismo archivo de inventario) sigue con `withData: true` + `Image.memory` alcanzable en móvil — preexistente, fuera del alcance de Fase 1, debe ir a Fase 2.

---

## 4. Revisión crítica de `image_picker` (parámetros exactos)

Invocación única en `mobile_product_image_picker.dart` `pickMobileProductImage`:
```dart
picker.pickImage(
  source: ImageSource.camera | ImageSource.gallery,
  maxWidth: 1600,
  maxHeight: 1600,
  imageQuality: 85,
  requestFullMetadata: false,
);
```
- **No se pasa `preferredCameraDevice`** → el plugin usa el default (`rear`). Correcto.
- La optimización (`maxWidth/maxHeight/imageQuality`) aplica **tanto a cámara como a galería** (los params van en la misma llamada, sin ramas por `source`).
- **No existe ningún camino** del flujo de producto que invoque `pickImage` sin esos tres parámetros.
- `requestFullMetadata: false`: en iOS reduce lectura de metadatos; **no** altera la conversión HEIC (ver §5). En Android **no** desactiva la copia de EXIF del resizer (ver §7).

---

## 5. HEIC / HEIF — verificación sobre el código fuente real del plugin (NO asumido)

Verificado en `image_picker_ios-0.8.13+6`:

**A. Galería iPhone (PHPicker, iOS 14+)** — `FLTPHPickerSaveImageToPathOperation.m` `processImage:`:
- Carga datos crudos del picker (HEIC para fotos de cámara en biblioteca).
- `[UIImage initWithData:]` decodifica HEIC → `UIImage`.
- Con `maxWidth/maxHeight` → `scaledImage`.
- `saveImageWithOriginalImageData:` → `getImageMIMETypeFromImageData:` (primer byte; HEIC empieza en `0x00` → **`FLTImagePickerMIMETypeOther`**) → `suffix = imageTypeSuffixFromType:Other` → **nil → cae a `.jpg`** (`kFLTImagePickerDefaultSuffix`).
- `convertImage:usingType:Other quality:0.85` → caso `default` → **"converts to JPEG by default" → `UIImageJPEGRepresentation(image, 0.85)`**.
- **Resultado: archivo JPEG con extensión `.jpg`.** ✅

**B. Cámara iPhone (`UIImagePickerController`, legacy)** — `FLTImagePickerPlugin.m`:
- `saveImageWithPickerInfo:image:imageQuality:` → `type = kFLTImagePickerMIMETypeDefault = JPEG`, `suffix = .jpg` → `UIImageJPEGRepresentation(image, 0.85)`.
- La cámara ya devuelve `UIImage` decodificado → **siempre JPEG `.jpg`.** ✅

**C. Con `maxWidth/maxHeight/imageQuality` definidos:** en iOS, el escalado activa el flujo que re-encodea a JPEG (HEIC y "Other" → JPEG por defecto; PNG → PNG).

**D. Extensión del `XFile.path`:** iOS → `image_picker_<guid>.jpg` (o `.png`/`.gif` para esos formatos). Android → `scaled_<nombre>.jpg|.png`.

**E. MIME que enviamos:** nuestra app copia SIEMPRE a `product_<ts>_<rand>.jpg` y `detectImageMime('.jpg')` → **`image/jpeg`** (ver §6 para la incoherencia PNG).

**F. ¿HEIC con nombre `.jpg` o JPEG con nombre `.heic`?**
- HEIC + `.jpg`: **sí puede ocurrir transitoriamente en iOS** mientras el plugin lo convierte, pero el archivo que finalmente devuelve ya es JPEG `.jpg`. Nuestra app copia el archivo ya-convertido.
- JPEG + `.heic`: **no** (el plugin nunca produce `.heic`).
- Riesgo real: en **Android** un HEIC de galería (raro) que `BitmapFactory` no pueda decodificar hace que `ImageResizer` devuelva la ruta original sin convertir; nuestra copia la renombraría a `.jpg` con contenido HEIC → el backend podría aceptarla por extensión `.jpg` y `sharp` (failOn:none) fallaría al optimizar → guardaría el original HEIC. Edge case de Android (poco probable).

**G. Detección backend:** el `fileFilter` valida por **MIME multipart** (`image/(png|jpe?g|webp)`) **o** (si `application/octet-stream`/vacío) por **extensión** `\.(png|jpe?g|webp)$`. No valida magic bytes en el filtro; `sharp` (failOn:none) sí auto-detecta el contenido para optimizar.

**Clasificación HEIC:**
- iPhone galería: **CONFIRMADO SOLUCIONADO POR CÓDIGO** (la ruta PHPicker convierte HEIC→JPEG garantizado).
- iPhone cámara: **CONFIRMADO SOLUCIONADO POR CÓDIGO** (siempre JPEG).
- **REQUIERE PRUEBA EN IPHONE REAL** para validar físicamente (no hay Mac/iPhone en este entorno).
- Android HEIC (raro): **REQUIERE PRUEBA** (edge case de decodificación).

---

## 6. MIME TYPE — trazado

- `MultipartFile.fromFile(filePath, filename: 'product_<ts>_<rand>.jpg', contentType: detectImageMime(filename) = image/jpeg)`.
- `detectImageMime` (`file_utils.dart`) solo devuelve `image/png`, `image/jpeg`, `image/webp`; para `.jpg` → `image/jpeg`. **Nunca `null` en móvil** porque nuestro nombre siempre es `.jpg`.
- **Coherente para:** JPEG (cámara iOS/Android), HEIC (convierte a JPEG en iOS).
- **INCOHERENTE para PNG:** si el usuario elige una **PNG** (iOS galería → plugin devuelve `.png`/PNG; Android galería con alpha → `.png`/PNG), nuestra copia la renombra a `.jpg` y enviamos `image/jpeg`, pero **el contenido es PNG**.
  - Impacto real: **funciona** porque el backend usa `sharp(buffer, {failOn:'none'})` + `.resize()` + `.jpeg()` → sharp detecta PNG y lo re-encodea a JPEG. No rompe, pero nombre/extensión/contenido/MIME **no son coherentes** y se depende de la tolerancia de sharp.
  - **Corrección mínima (Fase 2):** conservar la extensión/formato real que devuelve `image_picker` (usar `picked.name` o detectar el MIME real de los bytes) en lugar de forzar `.jpg`.
- **Backend** acepta `image/jpeg` en el `fileFilter` → OK.

**Resultado MIME:** Funciona en la práctica para todos los casos (el flujo mueve HEIC→JPEG y sharp tolera PNG/WebP), pero **hay una incoherencia nombre/MIME/contenido para fuentes PNG** → **OBSERVACIÓN** (baja severidad, no bloqueante).

---

## 7. ORIENTACIÓN / EXIF — verificación crítica

**iOS galería (PHPicker):** `scaledImage:isMetadataAvailable:YES` fija la orientación a `Up` y ajusta dimensiones para orientaciones left/right antes de dibujar; el bitmap escalado queda en orientación corregida y se re-encodea a JPEG. → **PROBABLE** (el código lo maneja explícitamente; requiere verificación física).

**iOS cámara:** mismo `scaledImage` + luego `saveImageWithMetaData` re-adjunta `info[UIImagePickerControllerMediaMetadata]` (EXIF original) al JPEG ya escalado. **Riesgo potencial de doble rotación** si el EXIF re-adjuntado conserva la etiqueta de orientación original sobre píxeles ya enderezados. No confirmado; depende de qué propiedades contenga el diccionario de metadatos en el dispositivo. → **REQUIERE PRUEBA EN IPHONE REAL** (foto vertical tomada con cámara).

**Android:** `ImageResizer.copyExif` se ejecuta **incondicionalmente** (independiente de `requestFullMetadata`) → el EXIF se copia al archivo escalado. Tanto Flutter (decode) como el backend (`sharp.rotate()`) respetan EXIF. → **PROBABLE** (requiere dispositivo).

**Conclusión orientación:** la implementación maneja orientación por código (iOS) y por EXIF (Android), pero **no puede garantizarse al 100 % sin dispositivo físico**. Clasificación: **PROBABLE — REQUIERE DEVICE REAL** (especialmente cámara iOS por el riesgo de doble rotación).

---

## 8. PREVIEW

- **Catálogo:** `buildMobileProductImagePreview(path, 64×64, cacheWidth:128, cacheHeight:128, fit:cover)` → bitmap máx 128×128×4 ≈ **0,065 MB**.
- **Inventario:** `cacheWidth:720, cacheHeight:720, fit:cover` → bitmap máx 720×720×4 ≈ **2,07 MB** (en la práctica ~720×540 para fotos 4:3 ≈ 1,5 MB).
- Se muestra el **archivo optimizado** (≤1600 px), no el original.
- **Confirmado:** ya no es posible decodificar 100–200 MB para una miniatura.

---

## 9. ARCHIVO TEMPORAL — ciclo de vida

- **Quién crea:** `image_picker` (tmp del plugin) + **nuestra copia** `copyToUniqueAppPath` → `getTemporaryDirectory()/fulltech_product_images/product_<ts>_<rand>.jpg`.
- **Quién conserva la ruta:** `_pickedImagePath` (State).
- **Cuándo se elimina:**
  - Usuario cambia de imagen → `deleteMobileProductImageTemp(previous)` inmediato (seguro: la anterior ya no se usa; en inventario el upload anterior queda invalidado por `_imageUploadToken`).
  - Usuario cancela/cierra el formulario → `dispose` → borrado.
  - Upload falla → no se borra hasta cerrar el formulario (dispose; en inventario `whenComplete` del future completado → borra).
  - Usuario vuelve atrás → `dispose` → borrado (en inventario espera el upload en vuelo para no romperlo).
  - Upload exitoso → se conserva mientras el formulario muestra la preview; se borra al cerrar.
- **Doble eliminación / inexistente durante upload:** protegido (`if (await file.exists())`, `catch (_)`). En inventario, el borrado en `dispose` espera `_imageUploadFuture.whenComplete` → no se borra antes de terminar el upload. ✅
- **Huérfanos detectados (menores, preexistentes o de bajo impacto):**
  1. El **tmp del propio `image_picker`** (`picked.path`) nunca se borra tras copiarlo → acumulación pequeña en tmp/cache de la app (iOS NSTemporaryDirectory se limpia con el SO; Android cache). **OBSERVACIÓN** — podría borrarse tras copiar (Fase 2).
  2. `_handleCompanyChanged` (inventario) pone `_pickedImagePath = null` **sin borrar** el temporal → huérfano en cambio de empresa (edge case). **OBSERVACIÓN** — Fase 2.
  3. Sustituciones múltiples en inventario → el **upload anterior** puede completar y dejar una imagen **huérfana en el servidor** (solo la última se referencia). Comportamiento **preexistente** (antes de Fase 1). Documentado.

---

## 10. ¿TEMPORAL PROPIO? ¿Podemos borrar la foto del usuario?

- **`image_picker` escribe en:** iOS `NSTemporaryDirectory()` (sandbox de la app) y Android `context.getCacheDir()` (caché de la app). **Nunca en la galería del usuario.** (Verificado en `FLTImagePickerPhotoAssetUtil.temporaryFilePath` y `ImageResizer.createImageOnExternalDirectory`.)
- Nosotros copiamos a `getTemporaryDirectory()/fulltech_product_images/` (también sandbox/caché de la app) y **borramos solo nuestra copia**.
- **Demostrado:** nuestro `deleteTemp` recibe únicamente la ruta de nuestra copia (`_pickedImagePath`). El `picked.path` del plugin (que es una copia, no la foto original) **no se borra**. La foto de la galería del usuario vive en `Photos`/MediaStore y **no se toca**.
- ✅ **Garantizado: el cleanup no puede borrar una fotografía real del usuario.**

---

## 11. Ciclo CREAR producto

- **Sin imagen:** catálogo lo **bloquea** (validación: "Selecciona una imagen para el producto") — comportamiento preexistente. Inventario **no requiere** imagen (permite crear sin foto). Ambos funcionan.
- **Con imagen (orden real):** `pickMobileProductImage` (procesa/optimiza) → `controller.create` → `repo.uploadImage(filePath)` (sube) → obtiene URL → `repo.createProduct(fotoUrl)`. **Orden: subir → guardar.** ✅
- **Upload OK + guardar falla:** la imagen queda **huérfana en el servidor** (subida sin producto que la referencie). El formulario muestra error y sigue abierto; un reintento sube de nuevo. **Preexistente** (mismo patrón antes de Fase 1). No se corrige aquí.
- **Upload falla:** `_canContinueWithoutUploadedImage` → si error 5xx/código null, **crea producto sin imagen** (por diseño); si 4xx, lanza error visible. **Preexistente.**

---

## 12. Ciclo EDITAR producto

- Producto con foto, usuario **no cambia** → `_pickedImagePath` null → `controller.update` sin `newImageBytes`/`newImageFilePath` → `updateProduct(fotoUrl: null)` → `_productPayload` **omite `fotoUrl`** (solo lo envía si no vacío) → **el backend conserva la imagen**. ✅ (Verificado en `_productPayload` L656-688.)
- Usuario **cambia** foto → sube nueva + `updateProduct(fotoUrl: nueva)`. ✅
- Selecciona nueva y **cancela** → `pickMobileProductImage` devuelve null → sin cambios de estado. ✅
- **Sustituye varias veces antes de guardar** (inventario): cada vez borra el temporal anterior y lanza upload nuevo con token; al guardar espera el último. Posible huérfano en servidor de uploads intermedios (preexistente). Documentado.

---

## 13. DOBLE TOQUE / CONCURRENCIA

- **Abrir cámara dos veces / cámara+galería simultáneas:** bloqueado por `_isPickingImage` (catálogo L3081, inventario L7124) + botón deshabilitado. ✅
- **Guardar dos veces:** `_saving` (catálogo botón `onPressed: _saving ? null : _submit` L3382; inventario `_isSaving`). ✅
- **Dos uploads simultáneos:** solo un pick a la vez; `_imageUploadToken` invalida respuestas de uploads anteriores. ✅
- **Condiciones de carrera:** el único caso es "borrar temporal anterior mientras el upload anterior aún lee el archivo" → el upload anterior falla limpiamente (no hay crash ni error visible; el token lo descarta). Aceptable.

---

## 14. `mounted`

Revisados todos los `await` añadidos en Fase 1:
- Catálogo `_pickMobileImage`: `mounted` tras el chooser y tras el pick; `finally` con `mounted`. ✅
- Catálogo `_submit`: `mounted` tras cada `await` y en `catch/finally`. ✅
- Inventario `_pickMobileImage`: `mounted` tras chooser y pick. ✅
- Inventario `_uploadSelectedImageWithRetry.then`: `mounted` + token. ✅
- Inventario `_resolveSelectedImageForSave`: `mounted` antes de `setState`. ✅
- `dispose` de ambos: usa `unawaited`, sin `setState`. ✅
- `_seedImageCache`/`_seedOptimizedImageCache`: no tocan UI. ✅
- **No se detectó `setState` después de `dispose` en el flujo nuevo.**

---

## 15. WINDOWS

- `catalogo_screen.dart` L3087-3100: la ruta desktop es **exactamente la anterior** (`FilePicker` + `withData:true` → `_imageBytes` → `Image.memory`).
- `inventory_module_pages.dart` L7135-7155: igual (desktop intacto).
- `catalog_repository.uploadImage`: la rama `else` usa `MultipartFile.fromBytes` (sin `filePath` en Windows).
- `catalog_controller`: conserva `imageBytes` para el flujo por bytes; los nuevos params son opcionales.
- **Diff verificado:** Windows no cambió. **Build:** `flutter build windows --debug` → `Built ...\Debug\fullpos_cloud.exe` (sesión anterior; sin cambios semánticos desde entonces).

---

## 16. TESTS — cobertura real

- Las **24 pruebas** de `inventory_product_editor_test.dart` usan `_FakeFilePicker` → **ejercitan la ruta DESKTOP** (FilePicker + bytes), **no la ruta móvil nueva**.
- El fake `uploadImage` se actualizó solo por firma (para que compile).
- **NO existe ningún test** para: `mobile_product_image_picker`, el selector cámara/galería, `pickImage` con parámetros, HEIC, temp files, cleanup, doble toque, errores de la ruta móvil.
- Clasificación:
  - Lógica antigua (desktop): cubierta (24 tests).
  - Nueva ruta móvil: **SIN COBERTURA**.
  - Upload: cubierto vía fake (bytes).
  - Selector / errores / doble toque / temporales de la ruta móvil: **SIN COBERTURA**.
- **Cobertura faltante:** unit tests de `pickMobileProductImage` (con `image_picker` mockeado vía `ImagePickerPlatform`), del chooser, del naming/MIME, del cleanup, y del comportamiento con PNG/HEIC.

---

## 17. BUILD ANDROID

- `flutter build apk --debug` → **OK** (`Built build\app\outputs\flutter-apk\app-debug.apk`) — sesión anterior. No hubo cambios semánticos desde entonces; `flutter analyze` limpio hoy.
- ⚠️ **Compilar ≠ funcionar en teléfono real.** El APK compila, pero la ruta móvil requiere validación en dispositivo (cámara real, permisos, HEIC real, RAM).

---

## 18. IPHONE

Entorno Windows → **NO se puede compilar iOS, NO hay simulador/iPhone**.
- **No se declara iOS validado.**
- **No se declara HEIC validado físicamente.**
- **No se declara cámara iPhone validada.**
- Requiere: **Mac + Xcode + CocoaPods** para compilar; **simulador** para galería (no cámara); **iPhone real** para cámara, HEIC, orientación de cámara, Jetsam y permisos.

---

## 19. RESULTADO OBLIGATORIO

### A. Veredicto Fase 1
**CORRECTA CON OBSERVACIONES.** El flujo de foto de producto en móvil ya no carga el original a RAM, optimiza nativamente, preview acotada, subida por archivo, caché con optimizado, selector cámara/galería, guards y `mounted`. Windows intacto. Las observaciones son de baja/media severidad y ninguna rompe el objetivo.

### B. Problemas críticos restantes (relacionados con Fase 1)
1. **Ninguno crítico** en el flujo de foto de producto.
2. **Media — MIME PNG incoherente:** fuentes PNG se renombran a `.jpg` y se envían como `image/jpeg` (contenido PNG). Funciona por tolerancia de `sharp`. Corrección: conservar formato real.
3. **Media — cobertura de tests nula** de la ruta móvil nueva.
4. **Baja — huérfanos:** tmp del plugin nunca se borra; `_handleCompanyChanged` no borra temporal; uploads intermedios pueden quedar huérfanos en servidor (preexistente).
5. **Preexistente (fuera de Fase 1):** editor de **categorías** sigue con `withData:true` + `Image.memory` en móvil.

### C. Pipeline Android actual
Cámara/Galería → `image_picker` (1600px, q85, EXIF copiada) → `scaled_*.jpg|png` en cache → copia `product_*.jpg` en tmp → preview `Image.file` (720px) → `MultipartFile.fromFile` → `POST /products/upload` → caché con optimizado → cleanup en dispose.

### D. Pipeline iOS actual
Cámara/Galería → `image_picker` (1600px, q85, `requestFullMetadata:false`; HEIC→JPEG nativo, orientación aplicada al escalar) → `image_picker_*.jpg` en `NSTemporaryDirectory` → copia `product_*.jpg` en tmp → preview `Image.file` → `fromFile` → upload → caché optimizada → cleanup.

### E. Pipeline Windows actual
`FilePicker` (`withData:true`) → `_imageBytes` → preview `Image.memory` → `MultipartFile.fromBytes` → upload. **Sin cambios.**

### F. Memoria
Eliminadas: original en RAM (withData), `Uint8List` del original en State, bitmap gigante de preview, original en caché. **Permanece:** bytes optimizados (≤1 MB) transitorios para sembrar caché; bitmap de preview ≤2 MB (acotado por cacheWidth/Height). Categorías aún con patrón viejo (preexistente).

### G. HEIC
**CONFIRMADO SOLUCIONADO POR CÓDIGO** (galería y cámara iPhone → JPEG). **REQUIERE PRUEBA EN IPHONE REAL.** Android HEIC raro → requiere prueba.

### H. MIME
Funciona (JPEG/HEIC correctos; PNG tolerado por sharp). **Incoherencia nombre/MIME/contenido para PNG** → observación de baja severidad.

### I. EXIF / orientación
**PROBABLE — REQUIERE DEVICE REAL.** iOS galería/cámara manejan orientación al escalar (con riesgo de doble rotación en cámara iOS sin confirmar); Android copia EXIF y Flutter+sharp lo respetan.

### J. Temporales
Ciclo correcto, sin borrado prematuro, cleanup seguro (nunca toca galería del usuario). Huérfanos menores (tmp del plugin, cambio de empresa).

### K. Concurrencia
Protegida (guards `_isPickingImage`, `_saving`, token de upload). Sin carrera crítica.

### L. Tests
Cubren solo la ruta desktop (24). **Ruta móvil nueva: sin cobertura** (selector, picker, HEIC, temporales, doble toque, errores).

### M. Pruebas físicas necesarias
**Android:** cámara (permiso concedido/denegado), galería (pequeña/grande/>10MB), PNG con alpha, vertical EXIF, sustitución de foto, cancelar, red lenta (reintento), doble toque, RAM con `dumpsys meminfo` y caché (`/data/data/com.daleventa.pos/cache`).
**iPhone (requiere Mac+Xcode+dispositivo):** cámara (HEIC + orientación vertical, doble rotación), galería HEIC, permiso cámara denegado, Jetsam tras ciclos repetidos, background durante picker.

### N. Correcciones mínimas necesarias (NO implementadas)
1. **Conservar el formato real** de `image_picker` para el nombre/MIME (usar `picked.name` o detectar MIME por bytes) en vez de forzar `.jpg` — elimina la incoherencia PNG.
2. Borrar el **tmp del plugin** (`picked.path`) tras copiar a nuestra ruta (reduce huérfanos).
3. Añadir **tests unitarios de la ruta móvil** (mockeando `ImagePickerPlatform`) para selector, params, naming/MIME y cleanup.
4. (Fase 2, preexistente) Migrar el **editor de categorías** fuera de `withData:true`/`Image.memory` en móvil.
5. (Fase 2) Limpieza de temporal en `_handleCompanyChanged`.

> Nada de lo anterior se implementó en esta auditoría.

---

## REGLAS RESPETADAS
Sin modificaciones de código · sin commit · sin push · sin despliegues · sin cambios de dependencias · sin cambios de backend · sin cambios de Windows · sin continuar a Fase 2.
