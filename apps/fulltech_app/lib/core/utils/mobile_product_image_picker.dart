import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../debug/trace_log.dart';
import 'is_flutter_test.dart';
import 'mobile_product_image_platform_stub.dart'
    if (dart.library.io) 'mobile_product_image_platform_io.dart'
    as mobile_platform;

/// Política de optimización de imágenes de producto en móvil (Android/iOS).
///
/// Justificación técnica:
/// - Las fotos de cámara moderna (12–48 MP) no se necesitan a resolución
///   completa dentro de un POS. 1600 px en el lado mayor mantiene buena
///   nitidez visual para mostrar productos.
/// - JPEG calidad 85 conserva calidad sin acercarse al límite de 15 MB del
///   backend (objetivo habitual < 1 MB por foto).
/// - `image_picker` procesa de forma NATIVA (fuera del isolate de Dart):
///   redimensiona, comprime, aplica la orientación EXIF y convierte
///   HEIC/HEIF a JPEG en iOS. Por eso no se requiere el paquete `image` ni
///   `compute` para esta fase.
const double kMobileProductImageMaxDimension = 1600;
const int kMobileProductImageQuality = 85;

/// true únicamente en Android e iOS (nunca en Windows/escritorio/web/tests).
/// En tests de Flutter se simula Android por defecto; se mantiene la ruta
/// desktop (FilePicker) salvo que un test fuerce explícitamente la plataforma
/// móvil con `debugDefaultTargetPlatformOverride`.
bool isMobileImagePlatform() {
  if (kIsWeb) return false;
  if (isFlutterTest) {
    return debugDefaultTargetPlatformOverride == TargetPlatform.android ||
        debugDefaultTargetPlatformOverride == TargetPlatform.iOS;
  }
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

enum MobileProductImageSource { camera, gallery }

class MobileProductImagePickResult {
  const MobileProductImagePickResult({
    required this.filePath,
    required this.filename,
  });

  /// Ruta absoluta del archivo optimizado (JPEG, ≤1600 px).
  final String filePath;

  /// Nombre del archivo optimizado (siempre `.jpg` en móvil).
  final String filename;
}

/// Abre la cámara o la galería (según [source]) y devuelve la imagen ya
/// optimizada (≤1600 px, JPEG ~85) en una ruta temporal propia de la app.
///
/// Devuelve `null` si el usuario cancela o si no hay plataforma móvil.
/// Lanza [Exception] si el permiso es denegado, la cámara no está disponible
/// o la imagen no puede procesarse.
Future<MobileProductImagePickResult?> pickMobileProductImage({
  required MobileProductImageSource source,
}) async {
  if (!isMobileImagePlatform()) return null;
  final sourceLabel = source == MobileProductImageSource.camera
      ? 'camera'
      : 'gallery';
  _logMobileImage(
    'mobile_image.pick.start',
    detail: 'source=$sourceLabel platform=${defaultTargetPlatform.name}',
  );
  final picker = ImagePicker();
  final XFile? picked;
  try {
    picked = await picker.pickImage(
      source: source == MobileProductImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: kMobileProductImageMaxDimension,
      maxHeight: kMobileProductImageMaxDimension,
      imageQuality: kMobileProductImageQuality,
      // Evita cargar metadatos EXIF/GPS completos (menos memoria).
      requestFullMetadata: false,
    );
  } on Exception catch (error, stackTrace) {
    _logMobileImage(
      'mobile_image.pick.error',
      detail: 'source=$sourceLabel',
      error: error,
      stackTrace: stackTrace,
    );
    // Permiso denegado, cámara no disponible, imagen ilegible, etc.
    rethrow;
  }
  if (picked == null) {
    // Cancelar es un estado normal, no un error.
    _logMobileImage('mobile_image.pick.cancel', detail: 'source=$sourceLabel');
    return null;
  }
  return processPickedMobileImage(picked);
}

/// Procesa el `XFile` devuelto por el picker: detecta el formato real del
/// contenido (magic bytes), copia a una ruta propia con la extensión y MIME
/// coherentes, y limpia de forma segura el temporal del plugin.
///
/// Separado del picker para poder probarlo de forma unitaria con archivos
/// reales sin depender de la plataforma ni de `image_picker`.
Future<MobileProductImagePickResult> processPickedMobileImage(
  XFile picked,
) async {
  _logMobileImage('mobile_image.process.start', detail: 'path=${picked.path}');
  final detected = await mobile_platform.detectImageContentType(picked.path);
  final extension = detected?.extension ?? _extensionFromFileName(picked.name);
  final path = await mobile_platform.copyToUniqueAppPath(
    picked.path,
    extension: extension,
  );
  // Nuestra copia ya existe y está completa: se puede limpiar el temporal del
  // plugin de forma segura (nunca una foto de la galería del usuario).
  await mobile_platform.deletePluginTempSafely(picked.path, ownCopyPath: path);
  final size = await mobile_platform.fileSizeBytes(path);
  _logMobileImage(
    'mobile_image.process.done',
    detail:
        'ext=$extension mime=${detected?.mime ?? 'null'} bytes=${size ?? 0}',
  );
  _logMobileImage('mobile_image.cleanup', detail: 'pluginTemp=${picked.path}');
  return MobileProductImagePickResult(
    filePath: path,
    filename: mobile_platform.fileNameFromPath(path),
  );
}

String _extensionFromFileName(String name) {
  final value = name.trim().toLowerCase();
  final dot = value.lastIndexOf('.');
  if (dot < 0 || dot == value.length - 1) return '.jpg';
  final ext = value.substring(dot);
  return (ext == '.jpeg') ? '.jpg' : ext;
}

/// Elimina el archivo temporal optimizado cuando ya no se necesita.
/// Nunca borra archivos originales de la galería del usuario.
Future<void> deleteMobileProductImageTemp(String? path) {
  return mobile_platform.deleteTemp(path);
}

/// Preview de la imagen optimizada a partir de su ruta. Usa `Image.file` con
/// `cacheWidth`/`cacheHeight` para NO decodificar a resolución completa
/// (evita picos de memoria en móvil). Solo construye la vista en Android/iOS.
Widget buildMobileProductImagePreview({
  required String path,
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  int? cacheWidth,
  int? cacheHeight,
}) {
  return mobile_platform.buildPreview(
    path: path,
    width: width,
    height: height,
    fit: fit,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
  );
}

/// Selector móvil "Tomar foto / Elegir de galería" integrado con el diseño
/// del sistema (bottom sheet). Devuelve `null` si el usuario cancela.
Future<MobileProductImageSource?> showMobileProductImageSourceChooser(
  BuildContext context,
) async {
  return showModalBottomSheet<MobileProductImageSource>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Agregar fotografía',
                style: theme.textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              subtitle: const Text('Usa la cámara del teléfono'),
              onTap: () =>
                  Navigator.of(context).pop(MobileProductImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de galería'),
              subtitle: const Text('Selecciona una imagen existente'),
              onTap: () =>
                  Navigator.of(context).pop(MobileProductImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// Traduce errores del flujo móvil de imágenes a mensajes claros para el
/// usuario, sin que el formulario quede bloqueado.
String mobileProductImageErrorMessage(Object error) {
  final raw = error.toString().toLowerCase();
  if (raw.contains('camera') &&
      (raw.contains('permission') || raw.contains('denied'))) {
    return 'No se pudo acceder a la cámara. Revisa los permisos de la aplicación.';
  }
  if (raw.contains('does_not_exist') ||
      raw.contains('no such file') ||
      raw.contains('cannot open')) {
    return 'La imagen seleccionada ya no está disponible. Intenta de nuevo.';
  }
  if (raw.contains('unsupported') || raw.contains('format')) {
    return 'No se pudo convertir la imagen a un formato compatible. Prueba con otra fotografía.';
  }
  if (raw.contains('space') ||
      raw.contains('disk') ||
      raw.contains('storage') ||
      raw.contains('enospc')) {
    return 'No hay suficiente espacio en el dispositivo para procesar la imagen.';
  }
  return 'No se pudo procesar la imagen: $error';
}

/// true si el error proviene de un permiso denegado de cámara/fotos
/// (permite ofrecer la acción “Abrir Configuración” sin forzarla).
bool isMobilePermissionError(Object error) {
  final raw = error.toString().toLowerCase();
  return raw.contains('camera_access_denied') ||
      raw.contains('photo_access_denied') ||
      (raw.contains('camera') &&
          (raw.contains('permission') || raw.contains('denied')));
}

/// Recupera (solo Android) una imagen seleccionada que se perdió porque el
/// sistema destruyó la MainActivity durante la captura (cámara/galería).
/// Best-effort: nunca lanza; devuelve `null` si no hay datos, hay un error de
/// permiso previo o falla el procesamiento. En iOS/Windows no hace nada.
Future<MobileProductImagePickResult?> recoverLostMobileImage() async {
  if (!isMobileImagePlatform()) return null;
  _logMobileImage('mobile_image.recover.start');
  final LostDataResponse response;
  try {
    response = await ImagePicker().retrieveLostData();
  } catch (error, stackTrace) {
    // Captura amplia (incluye UnimplementedError de plataformas/mocks sin
    // getLostData): la recuperación es best-effort y NUNCA debe lanzar.
    _logMobileImage(
      'mobile_image.recover.error',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
  if (response.isEmpty) return null;
  if (response.exception != null) {
    // Si la captura previa terminó en error de permiso, se informa como tal
    // (el formulario sigue funcionando; no hay crash).
    _logMobileImage(
      'mobile_image.recover.error',
      detail: 'exception=${response.exception!.code}',
      error: response.exception,
    );
    return null;
  }
  final file = response.file;
  if (file == null) return null;
  try {
    return await processPickedMobileImage(file);
  } catch (error, stackTrace) {
    _logMobileImage(
      'mobile_image.recover.error',
      error: error,
      stackTrace: stackTrace,
    );
    return null;
  }
}

/// Log estructurado (solo debug) de los eventos móviles críticos. No registra
/// bytes, Base64, credenciales ni datos sensibles.
void _logMobileImage(
  String event, {
  String detail = '',
  Object? error,
  StackTrace? stackTrace,
}) {
  TraceLog.log(
    'MobileImage',
    detail.isEmpty ? event : '$event $detail',
    error: error,
    stackTrace: stackTrace,
  );
}
