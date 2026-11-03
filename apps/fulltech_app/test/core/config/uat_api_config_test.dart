import 'package:daleventa_pos/core/config/product_config.dart';
import 'package:daleventa_pos/core/config/uat_api_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión del riesgo reportado: un build UAT sin `API_BASE_URL` explícita
/// podía acabar hablando con el backend de producción, porque
/// `Env.apiBaseUrl` cae a `ProductConfig.productionApiBaseUrl`.
///
/// Estas pruebas fijan el contrato del blindaje. El perfil comercial no cambia:
/// `isUatProfile` debe seguir siendo `false` por defecto.
void main() {
  group('perfil comercial — el blindaje NO aplica', () {
    test('isUatProfile es false sin --dart-define', () {
      expect(
        UatApiConfig.isUatProfile,
        isFalse,
        reason:
            'los builds comerciales deben conservar el comportamiento actual '
            '(fallback a la URL de producción)',
      );
    });

    test('la URL de producción sigue siendo la de siempre', () {
      expect(
        ProductConfig.productionApiBaseUrl,
        'https://daleventapos-backend.gcdndd.easypanel.host',
      );
    });
  });

  group('perfil UAT — rechaza todo lo que no sea local', () {
    test('sin API_BASE_URL no hay valor por defecto', () {
      expect(UatApiConfig.rejectionReason(''), 'API_BASE_URL_REQUIRED');
      expect(UatApiConfig.rejectionReason('   '), 'API_BASE_URL_REQUIRED');
      expect(
        () => UatApiConfig.resolve(''),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('UAT_API_BASE_URL_REFUSED'),
          ),
        ),
      );
    });

    test('rechaza el backend de producción', () {
      expect(
        UatApiConfig.rejectionReason(ProductConfig.productionApiBaseUrl),
        'API_BASE_URL_POINTS_TO_REMOTE',
      );
    });

    test('rechaza infraestructura remota conocida', () {
      for (final url in const [
        'https://daleventapos-backend.gcdndd.easypanel.host',
        'https://otro.easypanel.host',
        'https://hostinger.example.com',
        'http://31.97.99.70:4000',
        'https://ventas-fullpos-backend.gcdndd.easypanel.host',
      ]) {
        expect(
          UatApiConfig.rejectionReason(url),
          'API_BASE_URL_POINTS_TO_REMOTE',
          reason: url,
        );
      }
    });

    test('rechaza cualquier host que no sea local', () {
      expect(
        UatApiConfig.rejectionReason('http://192.168.1.50:4002'),
        'API_BASE_URL_MUST_BE_LOCAL',
      );
      expect(
        UatApiConfig.rejectionReason('https://uat.midominio.com'),
        'API_BASE_URL_MUST_BE_LOCAL',
      );
    });

    test('rechaza valores mal formados', () {
      expect(UatApiConfig.rejectionReason('no-es-una-url'), 'API_BASE_URL_INVALID');
      expect(
        UatApiConfig.rejectionReason('ftp://127.0.0.1'),
        'API_BASE_URL_INVALID_SCHEME',
      );
      expect(
        UatApiConfig.rejectionReason('/api'),
        'API_BASE_URL_INVALID',
        reason: 'una ruta relativa no sirve en escritorio',
      );
    });

    test('acepta el backend UAT local y normaliza la barra final', () {
      expect(UatApiConfig.rejectionReason('http://127.0.0.1:4003'), isNull);
      expect(
        UatApiConfig.resolve('http://127.0.0.1:4003'),
        'http://127.0.0.1:4003',
      );
      expect(
        UatApiConfig.resolve('http://127.0.0.1:4003/'),
        'http://127.0.0.1:4003',
      );
      expect(
        UatApiConfig.resolve('http://localhost:4003'),
        'http://localhost:4003',
      );
    });

    test('nunca devuelve la URL de producción', () {
      for (final value in const ['', '   ', '/api', 'nope', 'http://10.0.0.9']) {
        Object? thrown;
        try {
          UatApiConfig.resolve(value);
        } catch (error) {
          thrown = error;
        }
        expect(thrown, isA<StateError>(), reason: value);
      }
    });

    test('la negativa nombra la variable rechazada', () {
      // `APP_BASE_URL` en escritorio se descarta y cae a la URL pública de
      // producción si no se blinda. El perfil UAT lo impide y lo dice.
      expect(
        () => UatApiConfig.resolve('', key: 'APP_BASE_URL'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('UAT_APP_BASE_URL_REFUSED'),
          ),
        ),
      );
      expect(
        () => UatApiConfig.resolve(
          ProductConfig.productionAppBaseUrl,
          key: 'RELEASES_API_BASE_URL',
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('UAT_RELEASES_API_BASE_URL_REFUSED'),
          ),
        ),
      );
    });

    test('la URL pública de la app también se rechaza', () {
      // La app de validación no debe enlazar a la infraestructura pública.
      expect(
        UatApiConfig.rejectionReason(ProductConfig.productionAppBaseUrl),
        'API_BASE_URL_POINTS_TO_REMOTE',
      );
    });
  });
}
