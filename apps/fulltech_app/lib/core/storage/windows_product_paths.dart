import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum WindowsProductFolder { app, databases, mediaCache, logs, config, updates }

class WindowsProductPaths {
  WindowsProductPaths._();

  static const bool isUatMayoreoBuild = bool.fromEnvironment(
    'FULLPOS_UAT_BUILD',
    defaultValue: false,
  );

  /// Perfil UAT (misma bandera que usa `UatApiConfig` para exigir una API local).
  ///
  /// En una build UAT el almacenamiento DEBE estar aislado: si no se indica una
  /// carpeta propia, la app falla cerrada en vez de abrir las bases reales de
  /// `C:\Program Files\DaleVentas POS\databases`. Ocurrió en la aceptación UAT:
  /// una build de prueba, al no llevar la variable, resolvía exactamente la
  /// misma ruta que la instalación real del cliente.
  static const bool isUatProfile = bool.fromEnvironment(
    'FULLPOS_UAT_PROFILE',
    defaultValue: false,
  );

  static String get productName =>
      isUatMayoreoBuild ? 'DaleVentas POS UAT Mayoreo' : 'DaleVentas POS';

  static String get overrideRootEnv => isUatMayoreoBuild
      ? 'DALEVENTAS_POS_UAT_MAYOREO_ROOT'
      : 'DALEVENTAS_POS_ROOT';

  /// Build UAT aislada: **prohibe** usar el directorio de datos de produccion
  /// (`C:\Program Files\DaleVentas POS`). Con esta bandera, si no hay
  /// `DALEVENTAS_POS_ROOT` explicito, se devuelve `null` y los consumidores caen
  /// al directorio de datos de la propia aplicacion (que en UAT es otro por
  /// tener identidad de ejecutable distinta).
  static const bool uatIsolation = bool.fromEnvironment(
    'DALEVENTAS_POS_UAT_ISOLATION',
    defaultValue: false,
  );

  static bool get isOfficialWindowsStorageEnabled {
    if (kIsWeb || !Platform.isWindows) return false;
    if (uatIsolation) return _overrideRoot().isNotEmpty;
    if (_overrideRoot().isNotEmpty) return true;
    return kReleaseMode;
  }

  static bool get hasOverrideRoot {
    return _overrideRoot().isNotEmpty;
  }

  static Directory? productRoot() {
    if (kIsWeb || !Platform.isWindows) return null;

    final override = _overrideRoot();
    if (override.isNotEmpty) return Directory(override);

    // Fail-closed: una build UAT sin carpeta propia nunca debe tocar los datos
    // reales del cliente.
    if (isUatProfile) {
      throw StateError(
        'Build UAT sin almacenamiento aislado: define $overrideRootEnv con una '
        'carpeta exclusiva de pruebas antes de abrir la aplicación.',
      );
    }

    // Aislamiento UAT flexible (Guardian): nunca se usa la raiz de produccion.
    if (uatIsolation) return null;

    if (!kReleaseMode) return null;

    final programFiles = (Platform.environment['ProgramFiles'] ?? '').trim();
    final base = programFiles.isEmpty ? r'C:\Program Files' : programFiles;
    return Directory(p.join(base, productName));
  }

  static Directory? folder(WindowsProductFolder folder) {
    final root = productRoot();
    if (root == null) return null;
    return Directory(p.join(root.path, _folderName(folder)));
  }

  static String pathForRoot(String root, WindowsProductFolder folder) {
    return p.join(root, _folderName(folder));
  }

  static String _overrideRoot() {
    return (Platform.environment[overrideRootEnv] ?? '').trim();
  }

  static String _folderName(WindowsProductFolder folder) {
    return switch (folder) {
      WindowsProductFolder.app => 'app',
      WindowsProductFolder.databases => 'databases',
      WindowsProductFolder.mediaCache => 'media_cache',
      WindowsProductFolder.logs => 'logs',
      WindowsProductFolder.config => 'config',
      WindowsProductFolder.updates => 'updates',
    };
  }
}
