# 🛡️ FASE 2 — BLINDAJE DE ESTABILIDAD MÓVIL (Android/iOS)

**Proyecto:** DaleVentas POS (FullPOS Cloud)
**Fecha:** 2026-08-22
**Estado:** Implementada y validada (analyze ✔ · 50/50 tests ✔ · APK debug ✔ · Windows debug ✔). **Sin commit/push.**
**Pipeline de Fase 1/1.1:** intacto (no se rehizo).

---

## A. Veredicto

**BLINDADO POR CÓDIGO CON VALIDACIÓN FÍSICA PENDIENTE.**

El código queda blindado (lost-data, permisos, temporales, categorías, observabilidad, estados liberados) y todas las pruebas automáticas pasan. La validación física en Android/iPhone reales sigue pendiente (no hay dispositivos/Mac en este entorno).

---

## B. Lifecycle Android (Subfase A)

**Problema:** Android puede destruir la MainActivity durante la captura (cámara/galería) y el resultado se pierde. El pipeline no lo recuperaba.

**Implementado (aislado a móvil):**
- `recoverLostMobileImage()` en `mobile_product_image_picker.dart`: usa `ImagePicker().retrieveLostData()` (solo Android/iOS; en iOS/Windows no hace nada). Best-effort: captura amplia (incluye `UnimplementedError` de plataformas/mocks sin `getLostData`), maneja `LostDataResponse.exception` (permiso previo) y nunca lanza.
- Conectado en `initState` de ambos formularios de producto (catálogo e inventario) vía `_maybeRecoverLostImage()`: si hay una imagen perdida, la restaura en el formulario (en inventario además inicia la subida como si se hubiera seleccionado). Con `mounted` para evitar `setState` tras dispose.
- Si el formulario ya no existe, la recuperación se ignora sin crash.
- **No se implementó un sistema de drafts completo** (no es necesario según el alcance); los campos escritos se pierden si el sistema mata la Activity (limitación documentada).

---

## C. Permisos (Subfase B)

### Android
- `AndroidManifest.xml`: conserva `CAMERA` (requerida por `image_picker` para `ImageSource.camera`). **No** se agregan `READ_MEDIA_IMAGES` ni `READ_EXTERNAL_STORAGE` (el photo picker de Android 13+ y `ACTION_GET_CONTENT`/`OPEN_DOCUMENT` no los requieren). No se añaden permisos innecesarios.
- `image_picker` maneja internamente la captura; la app no solicita permisos de forma manual en el flujo.

### iOS
- `Info.plist`: ya contiene `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription` (textos en español comprensibles). No se agregan permisos nuevos.
- Acceso limitado/denegado/restricted: el picker nativo lo maneja; la app muestra mensaje claro.

### Denegado / No volver a preguntar
- `mobileProductImageErrorMessage` traduce `camera_access_denied`/`photo_access_denied` a mensajes claros ("No se pudo acceder a la cámara. Revisa los permisos...").
- `isMobilePermissionError()` detecta errores de permiso.
- En catálogo, inventario y editor de categorías, si es un error de permiso se muestra una acción **"Configuración"** (`openAppSettings()` de `permission_handler`, ya presente) — **solo se ofrece, no se fuerza**; sin loops ni apertura automática.
- **Cancelar voluntariamente** → `null` → NO es error, NO se muestra snackbar.

---

## D. Temporales (Subfase C + auditoría completa)

| Evento | Archivo | Debe conservarse | Debe borrarse | Quién lo limpia |
|---|---|---|---|---|
| Seleccionar foto | temporal del plugin (`image_picker`) | no | sí (tras copia propia) | `deletePluginTempSafely` (Fase 1.1) |
| Seleccionar foto | copia propia (`fulltech_product_images/…`) | sí (durante formulario) | al cerrar/reemplazar | `dispose` / reemplazo |
| Reemplazar foto (A→B→C) | temporales previos | no | sí (A y B) | formulario al reemplazar (`deleteMobileProductImageTemp(previous)`) |
| Cancelar formulario | copia propia | no | sí | `dispose` (catálogo e inventario) |
| Guardar OK | copia propia | no (upload ya terminó) | sí | `dispose` al cerrar el formulario (post-upload) |
| Upload falla | copia propia | sí (para reintentar) | al cerrar | `dispose` |
| Cambiar empresa (`_handleCompanyChanged`) | copia propia | no | **sí** (FIX de Fase 2) | `_handleCompanyChanged` |
| App mata proceso | copia propia | — | huérfano hasta limpieza del SO | OS (tmp) |
| Foto original del usuario | galería del usuario | **siempre** | **nunca** | — |

**Fix Fase 2 (Subfase C):** `_handleCompanyChanged` (inventario) ahora borra el temporal propio antes de descartar `_pickedImagePath`. Confirmado: no es una foto del usuario (es la copia de la app).

---

## E. Categorías (Subfase D)

**Remanente auditado y corregido** — `_CategoryEditorDialog` usaba `withData: true` + `Image.memory` con el original en móvil. Ahora:
- Móvil (Android/iOS): selector cámara/galería → pipeline seguro → `_pickedImagePath` (ruta del optimizado) → preview `Image.file` con `cacheWidth/Height 512` → al guardar se leen los **bytes optimizados** (≤1600 px) y se `base64Encode` para conservar el flujo existente (nunca el original gigante como `Uint8List`/base64).
- Limpieza del temporal en `dispose`, al reemplazar y al quitar la foto.
- Error de permiso → mensaje claro + acción "Configuración".
- **Windows/escritorio: comportamiento intacto** (FilePicker + base64).

---

## F. Memoria

- Reconfirmado (sin regresión tras Fase 1/1.1): móvil no usa `withData:true`, no hay `Image.memory` con original móvil en producto/categoría, previews limitadas (`cacheWidth/Height`), listas usan thumbnails, no se guardan originales en providers globales, no hay decodificación en `build`.
- Categorías ya no mantienen el original como `Uint8List` en móvil.
- Previews de categoría limitadas a 512 px (también en el `Image.memory` compartido — optimización de memoria, sin cambio visual en Windows).

---

## G. Red (Subfase E)

- Timeout global Dio: 15 s. Imagen optimizada móvil: ≤1600 px JPEG q85 → normalmente < 1 MB. **No se cambió** el timeout global (sin evidencia de que 15 s sea insuficiente para < 1 MB). Se documenta como propuesta para Fase 2.1 si la prueba física en red 3G lenta lo justifica.
- **Retries:** `ApiRetryInterceptor` solo reintenta métodos seguros (GET/HEAD/OPTIONS) salvo `retryUnsafeMethods` explícito → **no** reintenta automáticamente el POST de upload ni create/update (no hay riesgo de duplicar productos por reintento).
- Inventario: `_uploadSelectedImageWithRetry` hace hasta 3 intentos del **upload de imagen** (idempotente a nivel de producto; a lo sumo deja archivos huérfanos en el servidor, no duplica productos). `_resolveSelectedImageForSave` libera estado con timeout de 20 s.
- **Estados liberados:** en catálogo `_submit` (catch → `_saving=false`) y en inventario `_save` (catch → `_isSaving=false` + `_formError`). Nunca queda cargando para siempre.

---

## H. Respuestas inválidas (Subfase F)

- `uploadImage` lanza `ApiException` si la respuesta no trae `url`/`path`/`key`/`objectKey` (vacía o JSON inválido) → el formulario la muestra y libera estado. Sin crash de UI.
- `LocalJsonCache.readMap` ya captura **cualquier** error (incluido `FormatException: Unexpected end of input`) y devuelve `null` → la caché corrupta no rompe. No se requirió cambio.
- `getFreshCachedProducts`/`readCacheEntry` protegidos por el mismo `try/catch`.

---

## I. Caché (Subfase F)

- `FulltechImageCacheManager.putImageBytes`: desde Fase 1.1 solo recibe la **versión optimizada** (nunca el original móvil gigante). Config: `maxNrOfCacheObjects: 1200`, `stalePeriod: 30 días`. No se hizo refactorización (documentado).
- `flutter_cache_manager`'s índice corrupto ya se repara (`cache_repair.dart` / `buildCacheInfoRepositoryForPlatform`) — preexistente, sin cambios.

---

## J. Observabilidad (Subfase G)

Añadido en el pipeline móvil (`mobile_product_image_picker.dart`) y el upload (`catalog_repository.dart`) vía `TraceLog` (solo debug):
- `mobile_image.pick.start` (source, platform)
- `mobile_image.pick.cancel` (source) — cancelación NO es error
- `mobile_image.pick.error` (source)
- `mobile_image.process.start` / `mobile_image.process.done` (ext, mime, bytes)
- `mobile_image.cleanup` (pluginTemp)
- `mobile_image.recover.start` / `mobile_image.recover.error`
- `mobile_image.upload.start` (filename, fromFile) / `upload.done` (duration) / `upload.error` (status, duration)

**No se registran** bytes, Base64, credenciales, tokens ni datos sensibles. `FlutterError.onError`/`PlatformDispatcher.onError` ya registran en `AppErrorReporter` (no se cambió; no se ocultan errores con `catch (_) {}` en el pipeline — el único `catch` amplio es en la recuperación best-effort, que registra antes de devolver null).

---

## K. Tests (Subfase H)

| Suite | Resultado |
|---|---|
| `test/core/utils/mobile_product_image_picker_test.dart` (21) | ✔ |
| `test/features/catalogo/catalog_repository_upload_test.dart` (1) | ✔ |
| `test/features/products/inventory_product_editor_mobile_image_test.dart` (2) | ✔ |
| `test/features/products/inventory_product_editor_test.dart` (24) | ✔ |
| **Total** | **50 passed / 0 failed** |

**Nuevos en Fase 2 (dentro del test del pipeline):**
- `recoverLostMobileImage`: recupera imagen perdida (mock `getLostData`), respuesta vacía → null, `UnimplementedError` → null sin crash, excepción de permiso previa → null.
- Mensajes/permisos: `camera_access_denied`/`photo_access_denied` → mensaje claro + `isMobilePermissionError`, `FileSystemException` ENOSPC → mensaje de almacenamiento, formato no mapea a permiso.
- Limpieza por reemplazo: 3 reemplazos → solo queda el temporal actual; nunca borra la fuente.

> Los tests automáticos **no** demuestran cámara física, HEIC real, memory pressure, storage lleno, Activity kill real ni Jetsam — eso queda en las matrices físicas.

---

## L. Builds

- `flutter build apk --debug` → **OK** (`Built build\app\outputs\flutter-apk\app-debug.apk`).
- `flutter build windows --debug` → **OK** (`Built ...\Debug\fullpos_cloud.exe`).
- `flutter analyze` → **No issues found!**

---

## M. iPhone — pendiente de validación física

Checklist (requiere Mac + Xcode + iPhone real):
1. cámara · 2. galería · 3. HEIC · 4. JPEG · 5. screenshot PNG · 6. vertical · 7. horizontal · 8. permiso fotos limitado · 9. permiso denegado · 10. permiso cámara denegado · 11. 10 productos seguidos · 12. background · 13. bloquear pantalla · 14. conexión lenta · 15. pérdida de red · 16. sustituir foto · 17. cancelar formulario · 18. editar producto existente. Observar Jetsam y orientación.

---

## N. Android físico — pendiente

Checklist:
1. instalar APK · 2. iniciar sesión · 3. crear producto sin foto · 4. cámara · 5. galería · 6. cancelar cámara · 7. cancelar galería · 8. permiso denegado · 9. permiso denegado permanentemente · 10. foto 48MP · 11. PNG grande · 12. 10 productos seguidos · 13. cambiar foto 3 veces · 14. background durante cámara · 15. background durante upload · 16. modo ahorro · 17. poco espacio · 18. conexión lenta · 19. cortar internet durante upload · 20. reintentar · 21. editar producto · 22. categoría con imagen · 23. cerrar formulario sin guardar. Para cada paso: resultado esperado, qué observar, qué log buscar (`mobile_image.*`).

---

## O. Archivos modificados (Fase 2)

| Archivo | Motivo |
|---|---|
| `lib/core/utils/mobile_product_image_picker.dart` | `recoverLostMobileImage`, `isMobilePermissionError`, logs observabilidad, captura amplia best-effort |
| `lib/core/utils/mobile_product_image_platform_io.dart` | `fileSizeBytes` para logs |
| `lib/core/utils/mobile_product_image_platform_stub.dart` | stub de `fileSizeBytes` (web) |
| `lib/features/catalogo/catalogo_screen.dart` | `_maybeRecoverLostImage` + error de permiso con "Configuración" |
| `lib/features/products/ui/inventory_module_pages.dart` | `_maybeRecoverLostImage` + upload, error de permiso, `_handleCompanyChanged` limpia temporal, editor de **categorías** migrado a móvil |
| `lib/features/catalogo/data/catalog_repository.dart` | logs de upload (start/done/error) |
| `test/core/utils/mobile_product_image_picker_test.dart` | 7 tests nuevos de Fase 2 |

---

## P. Diff (resumen)

`git diff --check` limpio (solo warnings CRLF). Trackeados Fase 2: `catalogo_screen.dart` (+112), `catalog_repository.dart` (+47), `inventory_module_pages.dart` (+233) — acumulan Fase 1+Fase 2. El pipeline y sus tests siguen sin trackear (Fase 1/1.1/2). Sin commits.

---

## Q. Riesgos restantes (sin ocultar)

1. **Los campos del formulario se pierden** si Android mata la Activity (solo se recupera la foto; no hay drafts). Limitación documentada, no resuelta por alcance.
2. **Timeout de upload (15 s)** no se ajustó (sin evidencia para <1 MB); si la prueba física en 3G lenta lo muestra, aplicar timeout local en Fase 2.1.
3. **Huérfanos en servidor** por uploads de imagen reintentados (3 intentos) o sustituciones múltiples — no duplican productos, pero generan archivos huérfanos.
4. **Web build** sigue roto por `dart:ffi` en impresión (preexistente, fuera de alcance).
5. **Test de dedup `fetchProducts`** sigue fallando (preexistente).
6. **Validación física** Android/iPhone pendiente (cámara, HEIC, Jetsam, storage, Activity kill).

---

## R. Checklist Android (completa, pendiente físico)

Cámara / galería / cancelaciones / permiso denegado y permanente / 48MP / PNG grande / 10 productos / sustituir foto / background / ahorro / espacio / red lenta / pérdida de red / reintento / editar / categoría / cerrar sin guardar — con logs `mobile_image.*` y `dumpsys meminfo`.

## S. Checklist iPhone (completa, pendiente físico)

Cámara / galería / HEIC / JPEG / PNG / orientación / permisos (limited/denied) / 10 productos / background / bloqueo / red / sustituir / cancelar / editar — observando Jetsam.

---

## T. Estado Git

```
Rama: main · HEAD: 359ef560
git status: preexistentes (reports, compras, cotizaciones, ventas) + Fase 1 (catalog_controller,
catalogo_screen, catalog_repository, inventory_module_pages, inventory_product_editor_test)
+ Fase 1.1/2 sin trackear (pipeline + 3 tests) — sin commits.
git diff --check: limpio.
```

---

**NO commit · NO push · NO deploy · NO backend · NO Windows funcional · NO dependencias nuevas · NO Pub Cache · NO borrar fotos del usuario.**
