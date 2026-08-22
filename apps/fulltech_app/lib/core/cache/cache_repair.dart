import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Recupera/limpia el índice JSON interno de `flutter_cache_manager`
/// (`JsonCacheInfoRepository`) cuando quedó vacío o corrupto (p. ej. por una
/// escritura interrumpida al cerrar la app o un cierre abrupto).
///
/// SOLO toca el archivo de índice del caché de imágenes; NUNCA datos de
/// negocio, base de datos, sesión ni preferencias. Al borrar el índice, el
/// `CacheManager` lo reconstruye limpio al abrir y las imágenes se vuelven a
/// descargar normalmente.
class CacheInfoFileGuard {
  CacheInfoFileGuard._();

  /// Índice JSON del `DefaultCacheManager` (avatares, facturas, etc.).
  static Future<void> repairDefaultCacheManagerInfo() async {
    await repairJsonInfoFile(cacheKey: DefaultCacheManager.key);
  }

  /// Si `<appSupport>/<cacheKey>.json` existe y está vacío (0 bytes/solo
  /// espacios) o contiene JSON inválido, lo borra para que el manager
  /// reconstruya el índice limpio al abrir. Evita el
  /// `FormatException: Unexpected end of input` en `_readFile`.
  ///
  /// [directory] permite inyectar el directorio base en tests; si es null se
  /// resuelve con `getApplicationSupportDirectory()`.
  static Future<void> repairJsonInfoFile({
    required String cacheKey,
    Directory? directory,
  }) async {
    if (kIsWeb) return;
    File? file;
    try {
      file = await _infoFile(cacheKey, directory);
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        // Índice vacío → eliminar para reconstrucción limpia.
        await file.delete();
        return;
      }
      // Lanza si el contenido no es JSON deserializable.
      jsonDecode(raw);
    } on Object {
      // Índice corrupto → borrar SOLO ese archivo (mejor esfuerzo).
      try {
        final target = file ?? await _infoFile(cacheKey, directory);
        if (await target.exists()) await target.delete();
      } on Object {
        // Si no se puede, el paquete reporta y continúa con caché vacío.
      }
    }
  }

  static Future<File> _infoFile(String cacheKey, Directory? directory) async {
    final baseDir = directory ?? await getApplicationSupportDirectory();
    return File(p.join(baseDir.path, '$cacheKey.json'));
  }
}

/// Variante de [JsonCacheInfoRepository] que se auto-recupera: antes de leer
/// el archivo JSON de índice, valida su contenido y lo borra si quedó
/// vacío/corrupto. Así el `CacheManager` abre con un índice limpio en vez de
/// reportar el `FormatException` de `_readFile`.
class SelfHealingJsonCacheInfoRepository extends JsonCacheInfoRepository {
  SelfHealingJsonCacheInfoRepository({required String databaseName})
      : super(databaseName: databaseName);

  @override
  Future<bool> open() async {
    final key = databaseName;
    if (key != null && key.isNotEmpty) {
      await CacheInfoFileGuard.repairJsonInfoFile(cacheKey: key);
    }
    return super.open();
  }
}

/// Devuelve el repositorio de metadatos apropiado por plataforma (mismo
/// criterio que el paquete `flutter_cache_manager`), pero con auto-recuperación
/// en las plataformas que usan el índice JSON (Windows/Linux). En
/// móvil/macOS el paquete usa sqflite (`CacheObjectProvider`) y se conserva ese
/// comportamiento. Se usa `dart:io Platform` (igual que el paquete), no
/// `defaultTargetPlatform`, para no cambiar el comportamiento en tests.
CacheInfoRepository buildCacheInfoRepositoryForPlatform(String cacheKey) {
  if (kIsWeb) return NonStoringObjectProvider();
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    return CacheObjectProvider(databaseName: cacheKey);
  }
  return SelfHealingJsonCacheInfoRepository(databaseName: cacheKey);
}
