import 'dart:io';

import 'package:daleventa_pos/core/storage/windows_product_paths.dart';
import 'package:flutter_test/flutter_test.dart';

/// Aislamiento del almacenamiento en builds UAT.
///
/// Se ejecuta dos veces para probar las dos ramas reales:
///   flutter test test/core/storage/windows_product_paths_uat_guard_test.dart
///   flutter test test/core/storage/windows_product_paths_uat_guard_test.dart \
///     --dart-define=FULLPOS_UAT_PROFILE=true
///
/// Con el perfil UAT y sin carpeta propia, la app **debe** fallar cerrada:
/// de lo contrario abriría las bases reales de `C:\Program Files\DaleVentas POS`.
void main() {
  test('productRoot respeta el aislamiento exigido por el perfil', () {
    if (!Platform.isWindows) {
      return; // el aislamiento de Windows solo aplica en Windows
    }
    final override =
        (Platform.environment['DALEVENTAS_POS_ROOT'] ?? '').trim();
    final uatProfile = WindowsProductPaths.isUatProfile;

    if (uatProfile && override.isEmpty) {
      expect(
        () => WindowsProductPaths.productRoot(),
        throwsStateError,
        reason: 'una build UAT sin carpeta propia no puede arrancar',
      );
      return;
    }

    if (override.isNotEmpty) {
      expect(WindowsProductPaths.productRoot()!.path, override);
      expect(
        WindowsProductPaths.folder(WindowsProductFolder.databases)!.path,
        '$override${Platform.pathSeparator}databases',
      );
      return;
    }

    // Build normal: resuelve sin lanzar (carpeta del producto).
    expect(WindowsProductPaths.productRoot, returnsNormally);
  });

  test('el nombre del producto no se confunde con el de la versión publicada', () {
    expect(WindowsProductPaths.productName, isNotEmpty);
    if (WindowsProductPaths.isUatMayoreoBuild) {
      expect(WindowsProductPaths.productName, contains('UAT'));
    }
  });
}
