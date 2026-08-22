# 🔍 AUDITORÍA TÉCNICA — FLUJO MÓVIL DE PRODUCTOS E IMÁGENES (Android / iOS)

**Proyecto:** DaleVentas POS (FullPOS Cloud / `daleventa_pos`)
**Alcance:** Solo móvil (Android/iOS) — flujo crear/editar productos, cámara, galería, selección, procesamiento, compresión, preview, almacenamiento temporal, subida, caché, permisos, memoria y errores.
**Restricción:** Sin modificar código, sin commits, sin despliegues, sin tocar Windows/escritorio/web.
**Fecha:** 2026-08-22
**Tipo de auditoría:** Solo lectura (evidencia citada con archivo/clase/método/línea).

---

## 1. Estado del repositorio (inspección obligatoria)

| Ítem | Valor |
|---|---|
| Rama actual | `main` (sincronizada con `origin/main`) |
| Commit actual | `359ef560` "sasasasas" |
| HEAD alterno | `5b01611a FSDFSDFSD`, `236ef122 fdsfadsfdsfds` |
| Cambios sin commit (NO tocados) | `apps/fulltech_app/lib/features/reports/ui/reports_page.dart`, `apps/fulltech_app/lib/modules/cotizaciones/cotizaciones_screen.dart`, `apps/fulltech_app/lib/modules/ventas/data/ventas_repository.dart` |
| Sin trackear (NO tocados) | `AUDITORIA-MODULO-REPORTES.md`, `REPORTE-*` y tests nuevos de cotizaciones/ventas |
| Flutter / Dart | Flutter **3.41.6** stable · Dart **3.11.4** |
| SDK | `sdk: ^3.10.1`, versión app `1.0.3+7` |
| Backend | NestJS + Prisma en `apps/api` (no se modifica) |
| API base (app `.env`) | `https://daleventapos-backend.gcdndd.easypanel.host` |
| API timeout | `API_TIMEOUT_MS=15000` (15 s) |

### Dependencias relevantes (versiones resueltas en `pubspec.lock`)
| Paquete | Versión | Uso real en el flujo |
|---|---|---|
| `file_picker` | 8.3.7 | Selección de imagen (galería/archivo) — **el único picker usado** |
| `image_picker` | 1.1.2 | Declarada y registrada como plugin, **NO usada en ningún `.dart`** |
| `image` | 4.5.4 | Decodificación/redimensionado (solo logos/impresión ESC/POS, **no** en el flujo de producto) |
| `dio` | 5.9.1 | Red (subida multipart) |
| `cached_network_image` | 3.3.1 | Render de imágenes de producto (listas) |
| `flutter_cache_manager` | 3.4.1 | Caché en disco de imágenes |
| `path_provider` | 2.1.5 | Rutas de almacenamiento |
| `permission_handler` | 11.3.1 | Solo Bluetooth (impresión) y micrófono (dictado). **Nunca cámara/fotos** |
| `google_mlkit_text_recognition` | 0.15.0 | Lectura de documentos (fuera de alcance) |

> **No existen** `camera`, `image_cropper` ni `flutter_image_compress` en el proyecto.

---

## 2. Mapa del flujo móvil (B)

Hay **dos** formularios de producto con el mismo patrón de imagen:

### B1. Catálogo (`features/catalogo/catalogo_screen.dart`)
`CatalogoScreen` → `_openProductForm()` (L969) → **`showModalBottomSheet`** → `_ProductForm` (L2999) → `_ProductFormState` (L3039)

1. Usuario pulsa “Seleccionar archivo” (L3261) → `_pickImage()` (L3081).
2. `FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false, withData: true)` (L3082-3086).
3. El plugin lee **todo el archivo en RAM** → `_imageBytes = result.files.single.bytes` (L3089), `_imageName` (L3090).
4. Preview: `Image.memory(_imageBytes!, height: 64, width: 64)` **sin `cacheWidth`/`cacheHeight`** (L3274).
5. Guardar: `_submit()` (L3097) → `controller.create(imageBytes: _imageBytes!, filename: _imageName)` (L3139) o `controller.update(newImageBytes:...)` (L3155).
6. `CatalogController.create/update` → `repo.uploadImage(bytes, filename)` → `MultipartFile.fromBytes` sube los **bytes originales sin comprimir** (L409/654 → `catalog_repository.dart:307-334`).
7. Tras subir, `FulltechImageCacheManager.putImageBytes` escribe el **original completo** a disco (L417-425 / L662-670).
8. El producto se crea/actualiza y `onSaved()` cierra la bottom sheet.

### B2. Inventario (`features/products/ui/inventory_module_pages.dart`)
`showInventoryProductEditor()` (L6830) → **`showGeneralDialog`** → `InventoryProductEditorPage` (L6993) → `_InventoryProductEditorPageState`

1. `_pickImage()` (L7108): guard `_isPickingImage`, `FilePicker.pickFiles(withData: true)` (L7117).
2. `_imageBytes` en state (L7131); preview `Image.memory(_imageBytes!, width: double.infinity, height: double.infinity)` **sin cacheWidth** (L7634).
3. `_startSelectedImageUpload` (L7147) → **sube inmediatamente al seleccionar** la imagen.
4. `_uploadSelectedImageWithRetry` (L7164): hasta **3 intentos** de subida del mismo archivo + `putImageBytes` al caché (L7177-7183).
5. `_save()` (L7252) → `_resolveSelectedImageForSave()` (L7230) espera la subida con **timeout de 20 s** (L7238).
6. Crea/actualiza producto con `fotoUrl` (L7299-7355).

### B3. Resumen del recorrido (8 pasos obligatorios)
1. **Presiona cámara/galería** → solo hay galería/archivos vía `file_picker` (no hay captura con cámara propia; la opción "cámara" es la del picker del sistema).
2. **Se obtiene la fotografía** → `withData: true` carga **toda** la imagen a RAM.
3. **Se carga/decodifica** → solo al renderizar preview con `Image.memory` (decodifica a resolución nativa).
4. **Preview** → sin `cacheWidth`/`cacheHeight` → decodifica la imagen completa.
5. **Se comprime/transforma** → **NO existe compresión ni redimensionado en móvil.** (El backend sí redimensiona a 1600px server-side, pero el móvil sube el original.)
6. **Se guarda en estado** → `_imageBytes` (Uint8List) permanece vivo todo el formulario.
7. **Se envía** → `MultipartFile.fromBytes` con bytes originales; retry manual x3 (inventario) o en el save (catálogo).
8. **Se libera** → **nunca se libera explícitamente**; solo al cerrar el formulario se descarta el State. El caché conserva el original en disco.

---

## 3. Hallazgos confirmados (C)

> Criterio: solo problemas **demostrados por el código**, con evidencia concreta.

### C1. CRÍTICO — Carga completa de la imagen original a RAM (`withData: true`) — Android e iOS
- **Archivo/clase/método:** `catalogo_screen.dart` `_ProductFormState._pickImage` L3081-3092 · `inventory_module_pages.dart` `_InventoryProductEditorPageState._pickImage` L7108-7142.
- **Evidencia:**
  ```dart
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,   // <-- lee el archivo completo en memoria
  );
  ...
  _imageBytes = result.files.single.bytes;
  ```
- **Consecuencia:** una foto de cámara de 12 MP (≈4-8 MB) o 48 MP (≈10-25 MB) se mantiene como `Uint8List` en el State durante todo el formulario, **sin comprimir ni redimensionar**. En un móvil con poca RAM, este buffer + el bitmap de la preview + el buffer del multipart superan los umbrales de presión de memoria.
- **Reproducción:** crear producto → seleccionar foto grande desde la galería → observar `Memory`/pico de RAM (o cierre del proceso).
- **Solución recomendada (no implementada):** no usar `withData: true`; pedir la ruta (`path`) y procesar/redimensionar a máx. 1600px en un aislado antes de subir; o usar `image_picker` con `maxWidth/maxHeight/imageQuality` (que ya está declarado y sin usar).

### C2. CRÍTICO — Preview `Image.memory` sin `cacheWidth`/`cacheHeight` decodifica la imagen completa — Android e iOS
- **Evidencia:** `catalogo_screen.dart:3274` `Image.memory(_imageBytes!, height: 64, width: 64, fit: BoxFit.cover)` · `inventory_module_pages.dart:7634` `Image.memory(_imageBytes!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)`.
- **Consecuencia:** Flutter decodifica el bitmap a resolución nativa antes de escalar: 12 MP → **≈48 MB** de RGBA; 48 MP → **≈192 MB**. Ese pico, sobre el buffer de bytes ya en RAM, es el disparador típico de **Jetsam (iOS)** y **Low Memory Killer / ANR (Android)** → la app "se cierra sola" justo al trabajar con fotografías.
- **Solución recomendada:** añadir `cacheWidth`/`cacheHeight` (~600-1024) a toda preview y redimensionar el archivo antes de guardarlo en el State.

### C3. CRÍTICO — iPhone: imágenes HEIC/HEIF rechazadas por el cliente y el backend — iOS
- **Evidencia cliente:** `file_utils.dart` `detectImageMime` (L3-14) **no reconoce `.heic`/`.heif`** → devuelve `null` → `MultipartFile` con `application/octet-stream`.
- **Evidencia backend:** `apps/api/src/products/products.controller.ts` `fileFilter` (L168-178): solo acepta `mime image/(png|jpe?g|webp)` o extensión `\.(png|jpe?g|webp)$` → **HEIC = 400 "Solo se permiten imágenes PNG/JPG/WEBP"**. Límite `fileSize: 15MB` (L175).
- **Consecuencia:** una foto tomada con la cámara del iPhone (HEIC por defecto) **no puede subirse** → error/fallo percibido. La combinación con C1/C2 (memoria) explica "la aplicación se cierra constantemente al trabajar con fotografías".
- **Solución recomendada:** convertir HEIC→JPEG en el cliente (aislado) o configurar el picker para devolver JPEG; en iOS `image_picker` ya convierte HEIC a JPEG cuando se fija `imageQuality`.

### C4. ALTO — Límite de 15 MB + timeout de 15 s: fotos grandes fallan en móvil — Android e iOS
- **Evidencia:** backend `products.controller.ts:175` `limits: { fileSize: 15 * 1024 * 1024 }`; app `env.dart:11` `_defaultApiTimeoutMs = 15000`; `api_client.dart:11-13` timeouts `connect/send/receive` = 15 s.
- **Consecuencia:** una foto JPEG 48 MP (>15 MB) se rechaza en el backend; y en una conexión móvil lenta, subir 8-15 MB en <15 s puede agotar `sendTimeout`/`receiveTimeout`. Ambos caminos rompen la creación del producto.
- **Reproducción:** foto >15 MB o red 3G/4G débil → error de subida/guardado.

### C5. ALTO — Acumulación de caché en disco con originales completos → “falta de espacio” — Android
- **Evidencia:** `fulltech_cache_manager.dart` `FulltechImageCacheManager.putImageBytes` (L90-137): escribe **el archivo original completo** bajo la URL completa **y** bajo la URL de thumbnail (doble escritura). Config (L20-38): `maxNrOfCacheObjects: 1200`, `stalePeriod: 30 días`.
- **Consecuencia:** el límite es por **número** de objetos, no por tamaño. 1200 originales × 5-15 MB = **hasta ~6-18 GB** de caché. En un móvil con poco almacenamiento esto produce el aviso de “falta de espacio” al escribir (`putFile` falla silenciosamente, `catch (_)` L136). Esto encaja con el reporte de Android.
- **Solución recomendada:** guardar en caché solo la miniatura (320px) ya procesada, o el JPEG recompreso a 1600px, nunca el original; acotar tamaño total de caché por bytes.

### C6. ALTO — Sin manejo de ciclo de vida: la actividad/proceso se destruye con el picker abierto y se pierde todo — Android (y parcial iOS)
- **Evidencia:** los formularios viven en rutas de diálogo sin estado persistido: `showModalBottomSheet` (`catalogo_screen.dart:969-1000`) y `showGeneralDialog` (`inventory_module_pages.dart:6830-6865`). El `State` guarda `_imageBytes` solo en RAM. No hay `retrieveLostData` (no aplica a `file_picker`). `AndroidManifest.xml` usa `launchMode="singleTop"` + `configChanges` parcial; bajo presión de memoria Android puede recrear la Activity mientras el picker/cámara está abierto.
- **Consecuencia:** al volver de la cámara/picker el formulario puede haber perdido el estado (imagen + campos) o el proceso completo se reinicia → coincide con “al volver a abrir, se cierra de nuevo”. iOS también mata el proceso por presión (C2).
- **Solución recomendada:** persistir borrador del formulario (imagen en caché temporal + campos) y restaurarlo tras `AppLifecycleState.resumed`; o capturar la foto y volver sin abandonar el proceso.

### C7. ALTO — Timeout de 20 s en la subida rompe el reintento del guardado (dead-end) — Android e iOS
- **Evidencia:** `inventory_module_pages.dart` `_resolveSelectedImageForSave` L7230-7249: `upload.timeout(Duration(seconds: 20), onTimeout: () => throw TimeoutException(...))`. `_imageUploadFuture` proviene de `_uploadSelectedImageWithRetry` (L7164) que completa con `null` tras 3 fallos y **no se reinicia** en un nuevo `_save()`.
- **Consecuencia:** si la subida tarda >20 s o falla 3 veces, el guardado falla; al reintentar, el mismo future ya completó → siempre vuelve a fallar salvo que el usuario re-seleccione la imagen. Formulario bloqueado en la práctica.
- **Solución recomendada:** reintentar la subida dentro de `_save()` si el future falló; aumentar/loguear el timeout; desacoplar “subir imagen” de “guardar producto”.

### C8. MEDIO — Doble toque y `setState` sin `mounted` en el formulario de catálogo — ambas plataformas
- **Evidencia:** `_ProductForm._pickImage` (`catalogo_screen.dart:3081`) **no** tiene guard de “picking” (a diferencia de inventario con `_isPickingImage`) y **no comprueba `mounted`** antes de `setState` (L3089) tras el `await`. El botón solo se deshabilita con `_saving` (L3261).
- **Consecuencia:** doble toque puede lanzar dos pickers; si el usuario cierra la bottom sheet mientras el picker está abierto → `setState() called after dispose()`. No mata el proceso, pero queda registrado como error y puede dejar la UI inconsistente.
- **Solución recomendada:** añadir guard `_picking` y `if (!mounted) return;` antes de cada `setState` post-await.

### C9. MEDIO — Sin solicitud ni manejo de permisos de cámara/fotos — Android e iOS
- **Evidencia:** `permission_handler` solo se usa para Bluetooth (`mobile_print_service.dart:294`) y micrófono (`service_order_quick_actions_modal.dart:1444`). No hay `Permission.camera`/`Permission.photos` en ningún flujo de producto. `AndroidManifest.xml` declara `CAMERA` pero no `READ_MEDIA_IMAGES` ni `READ_EXTERNAL_STORAGE`.
- **Consecuencia:** se depende del picker nativo. Si el usuario deniega la cámara o marca “No volver a preguntar”, el picker devuelve `null` sin explicación; la app no orienta ni re-dirige a Ajustes. En Android 13+ el photo picker no requiere permiso, pero en flujos de captura la denegación queda muda.
- **Solución recomendada:** solicitar y verificar permisos antes de abrir el picker; mostrar guía cuando estén denegados; no asumir que el picker siempre funciona.

### C10. MEDIO — Temporales de `file_picker` sin limpiar — ambas plataformas
- **Evidencia:** no existe ninguna llamada a `FilePicker.clearTemporaryFiles()` en `lib/` (grep: 0 resultados). El plugin copia el archivo seleccionado a la caché de la app y puede acumularlos.
- **Consecuencia:** crecimiento lento pero constante del almacenamiento de la app tras repetir selecciones → contribuye al aviso de espacio en Android.
- **Solución recomendada:** limpiar temporales tras subir/cancelar; guardar solo la miniatura procesada.

### C11. BAJO — Observabilidad insuficiente para diagnosticar cierres reales — ambas plataformas
- **Evidencia:** `main.dart`: `FlutterError.onError` (L74-87) → `AppErrorReporter` (guarda **solo en memoria**, máx. 10 eventos, `app_error_reporter.dart:_remember` L192-197); `PlatformDispatcher.onError` (L83-85) devuelve `true` (traga errores nativos); **no hay Crashlytics/Sentry**. `_configureImageCacheForPlatform` (L108-116) **solo aplica a web**, no a móvil (default Flutter: ~100 MB de image cache sin tope por bytes).
- **Consecuencia:** un cierre por Jetsam/LMK no deja rastro en el dispositivo. Falta: logs nativos de OOM, tamaño de heap, eventos de ciclo de vida, y métricas de la subida.
- **Solución recomendada:** registrar en disco/log remoto los eventos de memoria y ciclo de vida del flujo de imagen; exponer un panel de diagnóstico; no tragar los errores nativos silenciosamente.

### C12. BAJO — `image_picker` declarado y registrado pero sin usar — ambas plataformas
- **Evidencia:** `pubspec.yaml:47` declara `image_picker: ^1.1.2`; está en `pubspec.lock` y registrado como plugin (`.flutter-plugins-dependencies`), pero **ningún `.dart` lo importa**.
- **Consecuencia:** código nativo innecesario en el APK/IPA; y, sobre todo, es una oportunidad desaprovechada: `image_picker` permite `maxWidth/maxHeight/imageQuality` (resuelve C1, C2, C3 y C4 de una vez).
- **Solución recomendada:** evaluar migrar el flujo de producto a `image_picker` con límites, o eliminar la dependencia muerta.

### Periférico (fuera del flujo de producto, se documenta)
- `core/printing/ticket_builder.dart:34` `file.readAsBytesSync()` y `mobile_esc_pos_generator.dart:85-135` `img.decodeImage`/`copyResize` sobre el logo se ejecutan en el **hilo principal** al imprimir ESC/POS. En móvil, un logo grande puede congelar la UI (ANR) durante la impresión.
- `account_menu_screens.dart:1851-1883` procesa el logo de la empresa con `img.decodeImage` + `copyResize` + `encodePng/Jpg` en el main isolate: mismo patrón de riesgo que C1/C2 pero para logos.

---

## 4. Hipótesis pendientes (D)

Estas **no** se pueden confirmar solo con código; requieren dispositivo real, logs nativos o pruebas:

1. **Si el cierre es Jetsam (iOS) o LMK (Android)** por el pico de C2: requiere captura de `jetsam_event.log`/`kern.log` o `adb logcat` con `lowmemorykiller`. No hay telemetría hoy.
2. **El mensaje exacto de “falta de espacio o memoria”** en Android: no existe en el código fuente de la app (grep exhaustivo). Se asume que es nativo (toast del sistema `Storage space running out`, o `ENOSPC` al copiar en `file_picker`). Requiere `adb logcat` del dispositivo real.
3. **Pérdida de estado al volver de la cámara/picker** (C6): requiere reproducción con `android:donotAskAgain` y observando si la Activity se recrea (`adb logcat ActivityTaskManager`).
4. **Comportamiento con HEIC en iPhone** real: el backend lo rechaza por código, pero confirmar el flujo UX completo (mensaje mostrado al usuario) requiere prueba en dispositivo.
5. **Comportamiento de `file_picker` con `withData: true` en iPhone para HEIC**: confirmar si devuelve bytes HEIC crudos o ya convertidos en la versión 8.3.7 (el código de la app no convierte).
6. **¿Qué opción de “cámara” ve el usuario?** La app no implementa captura con cámara propia; el único camino es el picker del sistema. Confirmar si la clienta usa la cámara dentro del picker de Android/iOS o espera un botón de cámara dedicado.

---

## 5. Diferencias entre móvil y Windows (E)

**El flujo de código es el mismo en Windows y en móvil** (mismo `file_picker`, mismo `Image.memory`, mismo multipart). El problema aparece solo en móvil por:

| Factor | Windows (funciona) | Móvil (falla) |
|---|---|---|
| RAM disponible | 8-32 GB; el SO no mata procesos con facilidad | 3-8 GB; iOS Jetsam / Android LMK matan el proceso bajo presión |
| Tipo de imagen típica | Screenshots/descargas (≤2-5 MP) | Fotos de cámara 12-48 MP (HEIC en iPhone) |
| Decodificación de preview | Barata, no perceptible | Pico de 48-192 MB → OOM |
| Subida | Red cableada/WiFi estable | Red móvil lenta, timeouts de 15 s |
| Caché en disco | Mucho espacio libre | Poco espacio → “falta de espacio” |
| Formato | JPEG/PNG común | HEIC (rechazado por el backend) |

**Conclusión:** no es una ruta distinta en Windows; es **la misma ruta con presupuesto de memoria/almacenamiento/red mucho menor** y formatos de foto más pesados. Windows oculta el defecto; el móvil lo expone.

---

## 6. Riesgos de regresión (F)

Si una corrección se hace mal:

- **Migrar a `image_picker` en todas las plataformas** rompería Windows/web si no se aísla por plataforma (el proyecto depende de `file_picker` en otros flujos: export CSV, compras, servicios, cuentas).
- **Añadir compresión/redimensionado en el cliente** debe hacerse **solo en Android/iOS** (validación de plataforma), porque Windows funciona con bytes originales y no debe cambiarse su comportamiento.
- **Cambiar `putImageBytes`** afecta el warm-up y el render inmediato de la imagen recién subida (el caché se siembra para que `ProductNetworkImage` la muestre al instante). Reducir lo que se cachea debe mantener la miniatura sembrada.
- **Aumentar timeouts globales** afecta a todas las llamadas de la app (la UX de espera ya se gestiona con `skipLoader`). Debe acotarse a la subida de archivos.
- **Persistir borradores del formulario** toca el estado de la bottom sheet/dialog y puede introducir duplicados si no se limpia al guardar.
- **Tocar `Image.memory` de preview** debe mantener el fallback/estados de edición (imagen existente de red vs. nueva local).
- **No se debe tocar** el render de listas (`ProductNetworkImage` con thumbnails 320px + `memCacheWidth`), que ya está correcto y es la base de la buena performance actual.

---

## 7. Plan de corrección propuesto (G) — solo propuesta, NO ejecutado

1. **Fase 0 — Instrumentación (sin cambios de comportamiento):** logs del flujo de imagen (selección→bytes→subida→guardado), tamaño del archivo, duración, errores; captura de métricas de memoria. Protegido por plataforma.
2. **Fase 1 — Reducir memoria en móvil (crítico):** en Android/iOS, al seleccionar: redimensionar a ≤1600px y re-comprimir a JPEG (calidad ~85) en un **aislado** (hoy no hay ningún `compute`/`Isolate` en el proyecto); guardar solo ese buffer en `_imageBytes`; añadir `cacheWidth`/`cacheHeight` a las previews. **Windows intacto.**
3. **Fase 2 — HEIC (iPhone):** en iOS, convertir HEIC→JPEG en el cliente antes de subir (o usar `image_picker` con `imageQuality`, que ya convierte); actualizar `detectImageMime`/`isImageExtension` para `.heic/.heif` (con conversión previa). Validar contra el `fileFilter` del backend (solo PNG/JPG/WEBP).
4. **Fase 3 — Caché en disco:** `putImageBytes` debe cachear la miniatura (≤320px) ya procesada, no el original; acotar la caché por bytes; `FilePicker.clearTemporaryFiles()` tras subir/cancelar.
5. **Fase 4 — Robustez del guardado:** reintentar la subida dentro de `_save()` si el future falló (romper el dead-end de C7); guard `_picking` + `mounted` en el formulario de catálogo (C8); manejar `TimeoutException`/`FileSystemException` con mensajes claros y opciones de reintento.
6. **Fase 5 — Permisos y ciclo de vida:** solicitar/verificar permisos de cámara/fotos antes del picker (solo móvil); persistir borrador del formulario para restaurar tras volver de la cámara si el proceso sobrevive.
7. **Fase 6 — Verificación multiplataforma:** probar la matriz completa en Android, iPhone y confirmar que **Windows sigue idéntico**.

Cada fase es pequeña, reversible y verificable de forma independiente.

---

## 8. Archivos que probablemente deberán modificarse (H) — SOLO LISTADO, no modificados

| Archivo | Motivo |
|---|---|
| `apps/fulltech_app/lib/features/catalogo/catalogo_screen.dart` | `_ProductForm._pickImage` (L3081), `_submit` (L3097), preview `Image.memory` (L3274) |
| `apps/fulltech_app/lib/features/products/ui/inventory_module_pages.dart` | `_pickImage` (L7108), `_startSelectedImageUpload` (L7147), `_uploadSelectedImageWithRetry` (L7164), `_resolveSelectedImageForSave` (L7230), preview (L7634) |
| `apps/fulltech_app/lib/features/catalogo/data/catalog_repository.dart` | `uploadImage` (L307-334) |
| `apps/fulltech_app/lib/features/catalogo/application/catalog_controller.dart` | `create` (L388), `update` (L630) — subida + siembra de caché |
| `apps/fulltech_app/lib/core/cache/fulltech_cache_manager.dart` | `putImageBytes` (L90-137), `Config` (L20-38) |
| `apps/fulltech_app/lib/core/utils/file_utils.dart` | `detectImageMime`/`isImageExtension` (L3-25) — HEIC |
| `apps/fulltech_app/lib/core/utils/` (nuevo helper de imagen para móvil) | redimensionado/compresión en aislado |
| `apps/fulltech_app/lib/main.dart` | image cache para móvil (L108-116), errores de plataforma (L83-85) |
| `apps/fulltech_app/android/app/src/main/AndroidManifest.xml` | permisos de imágenes si se requiere compatibilidad pre-Android 13 |
| `apps/fulltech_app/pubspec.yaml` | decisión sobre `image_picker` (usarlo o quitarlo) |
| Backend `apps/api/src/products/products.controller.ts` | **NO tocar en esta fase**; documentar límites (15 MB, no-HEIC) para alinear el cliente |

---

## 9. Matriz de reproducción (pruebas a diseñar)

> Escenarios para Android e iOS. En cada uno: resultado esperado, riesgo actual, logs necesarios, métrica, y cómo confirmar fuga de memoria.

| # | Escenario | Resultado esperado | Riesgo actual | Logs necesarios | Métrica | ¿Fuga de memoria? |
|---|---|---|---|---|---|---|
| 1 | Crear producto sin foto | OK | Bajo | — | Heap estable | No |
| 2 | Imagen pequeña desde galería | OK | Medio | pick/subida | Heap +cache | Leve |
| 3 | Foto tomada con cámara (picker) | OK | **Alto** | pick/subida/OOM | Pico de RAM | Sí si se repite |
| 4 | JPEG alta resolución (12 MP) | OK | **Crítico** | Jetsam/LMK | Heap, pico | Sí |
| 5 | PNG grande | OK | **Crítico** | OOM | Heap | Sí |
| 6 | HEIC de iPhone | Debe convertirse | **Crítico** | backend 400 | Mensaje | n/a |
| 7 | Imagen con orientación EXIF | Correcta | Medio | — | — | n/a |
| 8 | >5 MB | OK (≤15) | Medio | timeout | Duración subida | n/a |
| 9 | >10 MB | OK (≤15) | **Alto** | timeout | Duración subida | n/a |
| 10 | RAM baja | Sin cierre | **Crítico** | Jetsam/LMK | Pico de RAM | Sí |
| 11 | Poco almacenamiento | Mensaje claro | **Alto** | ENOSPC | Espacio libre | n/a |
| 12 | Conexión lenta | Reintento seguro | **Alto** | retry | Intentos subida | n/a |
| 13 | Pérdida de conexión en subida | Reintento/estado claro | **Alto** | retry/error | Intentos | n/a |
| 14 | Doble toque en guardar | Un solo guardado | Medio | — | Requests | n/a |
| 15 | Volver atrás durante compresión | Cancelación limpia | Medio | dispose | — | n/a |
| 16 | App a segundo plano (picker) | Restaura estado | **Alto** | lifecycle | Estado | n/a |
| 17 | Denegar cámara | Guía clara | Medio | permiso | — | n/a |
| 18 | Denegar fotos | Guía clara | Medio | permiso | — | n/a |
| 19 | Seleccionar imagen y cancelar | Sin cambio | Bajo | — | — | n/a |
| 20 | Tomar foto y cancelar | Sin cambio | Bajo | — | — | n/a |
| 21 | Editar producto y sustituir foto | OK | **Alto** | subida/caché | Heap | Posible |
| 22 | Repetir el proceso varias veces | Sin degradación | **Crítico** | heap+disk | Heap/caché en disco | **Sí** (objetivo principal a medir) |
| 23 | Crear varios productos consecutivos | Sin degradación | **Alto** | heap+disk | Heap/caché | Sí |
| 24 | Cerrar y abrir tras fallo | Estado consistente | **Alto** | lifecycle | Persistencia | n/a |

**Cómo confirmar fuga:** medir con DevTools/`adb shell dumpsys meminfo` el heap retenido tras ciclos 1→22 repetidos; y el tamaño del directorio de caché (`/data/data/com.daleventa.pos/cache`) antes/después. Si el heap crece entre ciclos sin cerrar el formulario, o el caché crece en GB, hay fuga/acumulación.

---

## 10. Pruebas de aceptación (I)

Se declara resuelto cuando **en Android e iPhone reales**:

1. Crear/editar producto con foto de cámara (12-48 MP) **no cierra ni congela** la app (0 kills por Jetsam/LMK en logs nativos).
2. Subir fotos de hasta 15 MB en conexión móvil lenta termina en éxito con reintentos controlados, sin duplicados ni archivos huérfanos.
3. Fotos HEIC de iPhone se suben correctamente (convertidas a JPEG) y el backend las acepta.
4. La preview se renderiza sin picos de memoria (con `cacheWidth`/`cacheHeight` o con imagen ya redimensionada).
5. El caché en disco no crece de forma descontrolada (se cachea miniatura, no original).
6. Denegar permisos de cámara/fotos muestra una guía clara y no deja el formulario bloqueado.
7. Tras volver de la cámara/picker, el formulario conserva la imagen y los datos (o el proceso no se cae).
8. Doble toque en “guardar” produce una sola operación.
9. **Windows/escritorio/web siguen funcionando idéntico** (regresión cero fuera de móvil).

---

## 11. Veredicto (J)

- **Causa raíz más probable:** el flujo móvil carga la fotografía **completa en resolución original** a la RAM (`file_picker` con `withData: true`), la mantiene en el State, la **decodifica entera para la preview** (`Image.memory` sin `cacheWidth`/`cacheHeight`) y la **sube sin comprimir** al backend. Ese triple uso simultáneo de memoria (bytes + bitmap + multipart) supera el presupuesto de RAM de los móviles y provoca **cierre por presión de memoria** (Jetsam en iOS, LMK en Android), agravado en iPhone por **HEIC** (que además es rechazado por el backend) y en Android por la **acumulación de originales en la caché en disco** (aviso de espacio).
- **Nivel de confianza:** alto para los mecanismos de memoria/HEIC/caché (demostrados por código); medio-alto para el vínculo directo “cierre = OOM” (requiere logs nativos del dispositivo real).
- **Evidencia disponible:** todo el código citado (secciones C, B), versiones de dependencias, configuración nativa de Android/iOS, límites del backend y del cliente.
- **Evidencia faltante:** logs nativos de OOM/Jetsam/LMK del dispositivo de la clienta; confirmación del texto exacto del aviso de espacio en Android; confirmación del comportamiento HEIC real de `file_picker 8.3.7` en iPhone.
- **Próximo cambio mínimo recomendado (sin implementar aún):** **solo en Android/iOS**, al seleccionar la imagen: redimensionar y re-comprimir a JPEG en un aislado (≤1600px, calidad ~85), añadir `cacheWidth`/`cacheHeight` a la preview, y cachear la miniatura en lugar del original. Validar después en dispositivo real y **dejar Windows intacto**.

---

*Auditoría finalizada. No se modificó ningún archivo de código, no se hicieron commits ni despliegues. Se esperan instrucciones para iniciar la fase de correcciones.*
