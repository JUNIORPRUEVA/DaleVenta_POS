import 'package:daleventa_pos/core/api/env.dart';
import 'package:daleventa_pos/core/config/product_config.dart';
import 'package:daleventa_pos/core/config/uat_network_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fase 3 — el perfil UAT no puede caer en el backend de producción.
///
/// El incidente: un artefacto compilado solo con `--dart-define=APP_ENV=uat`
/// (sin `API_BASE_URL`) llegaba a hablar con producción porque
/// `Env.apiBaseUrl` usa `ProductConfig.productionApiBaseUrl` como valor por
/// defecto. `FULLPOS_UAT_BUILD` no cubría ese caso: solo miraba un define
/// distinto.
///
/// Esta prueba fija la garantía para las DOS banderas que declaran el perfil:
///   `APP_ENV=uat` y `FULLPOS_UAT_PROFILE=true`.
///
/// Se ejecuta de dos formas:
///   1. `flutter test` (sin defines): el guardia está inactivo y el build
///      comercial conserva su comportamiento histórico (fallback a producción).
///   2. `flutter test --dart-define=APP_ENV=uat`:
///      `Env.apiBaseUrl` DEBE lanzar `StateError` en vez de devolver la URL
///      productiva. Es la verificación que demuestra el cierre del fallo.
const String _appEnv = String.fromEnvironment('APP_ENV', defaultValue: '');
const bool _uatProfile = bool.fromEnvironment(
  'FULLPOS_UAT_PROFILE',
  defaultValue: false,
);

bool get _perfilUatActivo =>
    _uatProfile || _appEnv.trim().toLowerCase() == 'uat';

void main() {
  group('Env.apiBaseUrl · perfil UAT declarado sin API_BASE_URL', () {
    test('UatNetworkGuard refleja el perfil declarado', () {
      expect(UatNetworkGuard.isUat, _perfilUatActivo);
    });

    test('sin URL explícita: cierra en UAT y usa el default comercial fuera',
        () {
      if (_perfilUatActivo) {
        expect(
          () => Env.apiBaseUrl,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('UAT_CONFIG_REFUSED'),
            ),
          ),
          reason: 'un build del perfil UAT no puede resolver la URL por defecto',
        );
      } else {
        // Comportamiento comercial intacto: no se cambia el fallback histórico.
        expect(Env.apiBaseUrl, ProductConfig.productionApiBaseUrl);
      }
    });

    test('el host productivo sigue estando prohibido para el perfil UAT', () {
      final uri = Uri.parse(ProductConfig.productionApiBaseUrl);
      expect(
        UatNetworkGuard.rejectionReason(uri),
        'URL_POINTS_TO_PRODUCTION',
      );
    });

    test('un destino local con el puerto correcto sí se acepta en UAT', () {
      expect(
        UatNetworkGuard.rejectionReason(
          Uri.parse('http://127.0.0.1:4004'),
        ),
        isNull,
      );
    });
  });
}
