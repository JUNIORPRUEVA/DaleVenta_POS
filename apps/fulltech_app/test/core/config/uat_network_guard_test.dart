import 'package:daleventa_pos/core/config/uat_network_guard.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de seguridad de la guardia de red UAT.
///
/// El incidente que motivan estas pruebas: un build Windows con solo
/// `--dart-define=APP_ENV=uat` terminó leyendo datos de producción. El criterio
/// GO es que **ninguna configuración incompleta de UAT se conecte a producción**.
///
/// `UatNetworkGuard.isUat` es una constante de compilación (`false` en las
/// pruebas), por lo que el modo UAT se inyecta explícitamente donde la API lo
/// permite. Las constantes de compilación se comprueban aparte en el script de
/// build (`scripts/build/build_windows_ecf_uat.ps1`).
void main() {
  group('UAT sin API_BASE_URL', () {
    test('se rechaza y no hay valor por defecto', () {
      expect(
        () => UatNetworkGuard.requireAllowedUrl('', key: 'API_BASE_URL'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('UAT_CONFIG_REFUSED'),
          ),
        ),
      );
      expect(
        () => UatNetworkGuard.requireAllowedUrl('   ', key: 'APP_BASE_URL'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('UAT con URL productiva', () {
    test('rechaza el host productivo conocido', () {
      expect(
        UatNetworkGuard.rejectionReason(
          Uri.parse('https://daleventapos-backend.gcdndd.easypanel.host'),
        ),
        'URL_POINTS_TO_PRODUCTION',
      );
    });

    test('rechaza la IP productiva conocida', () {
      expect(
        UatNetworkGuard.rejectionReason(Uri.parse('https://31.97.99.70:443')),
        'URL_POINTS_TO_PRODUCTION',
      );
    });

    test('rechaza cualquier subdominio de EasyPanel', () {
      for (final url in [
        'https://algo.easypanel.host',
        'https://otro.onqyr1.easypanel.host',
        'https://x.gcdndd.easypanel.host',
      ]) {
        expect(
          UatNetworkGuard.rejectionReason(Uri.parse(url)),
          'URL_POINTS_TO_PRODUCTION',
          reason: url,
        );
      }
    });

    test('rechaza un host remoto no listado', () {
      expect(
        UatNetworkGuard.rejectionReason(Uri.parse('http://192.168.1.10:4004')),
        'URL_MUST_BE_LOCAL',
      );
    });
  });

  group('UAT con URL local', () {
    test('acepta 127.0.0.1:4004 y normaliza la barra final', () {
      expect(
        UatNetworkGuard.requireAllowedUrl(
          'http://127.0.0.1:4004/',
          key: 'API_BASE_URL',
        ),
        'http://127.0.0.1:4004',
      );
    });

    test('acepta localhost:4004', () {
      expect(
        UatNetworkGuard.requireAllowedUrl(
          'http://localhost:4004',
          key: 'APP_BASE_URL',
        ),
        'http://localhost:4004',
      );
    });

    test('rechaza un puerto distinto', () {
      expect(
        UatNetworkGuard.rejectionReason(Uri.parse('http://127.0.0.1:8080')),
        'URL_PORT_NOT_ALLOWED',
      );
    });

    test('rechaza una URL local sin puerto (iría al 80)', () {
      expect(
        UatNetworkGuard.rejectionReason(Uri.parse('http://127.0.0.1')),
        'URL_PORT_REQUIRED',
      );
    });

    test('rechaza esquemas que no son http/https', () {
      expect(
        UatNetworkGuard.rejectionReason(Uri.parse('ws://127.0.0.1:4004')),
        'URL_INVALID_SCHEME',
      );
    });
  });

  group('UAT con redirección hacia producción', () {
    test('el destino de la redirección se bloquea antes de enviarse', () {
      expect(
        () => UatNetworkGuard.assertAllowedUri(
          Uri.parse('https://daleventapos-backend.gcdndd.easypanel.host/auth/login'),
          key: 'REDIRECT',
          uat: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('un destino local permitido pasa', () {
      expect(
        () => UatNetworkGuard.assertAllowedUri(
          Uri.parse('http://127.0.0.1:4004/auth/login'),
          key: 'REQUEST',
          uat: true,
        ),
        returnsNormally,
      );
    });
  });

  group('Aislamiento de almacenamiento', () {
    test('UAT usa prefijo y base de datos propios', () {
      expect(UatNetworkGuard.storageNamespaceFor(uat: true), 'uat.');
      expect(
        UatNetworkGuard.offlineDatabaseFileNameFor(uat: true),
        'fulltech_offline_uat.db',
      );
    });

    test('el build comercial conserva claves y base originales', () {
      expect(UatNetworkGuard.storageNamespaceFor(uat: false), '');
      expect(
        UatNetworkGuard.offlineDatabaseFileNameFor(uat: false),
        'fulltech_offline.db',
      );
    });
  });

  group('Build comercial (sin perfil UAT)', () {
    test('la guardia no interviene', () {
      // `isUat` es false en esta compilación de pruebas, igual que en un build
      // comercial: un host remoto no se bloquea aquí porque el build comercial
      // debe funcionar contra su backend.
      expect(UatNetworkGuard.isUat, isFalse);
      expect(
        () => UatNetworkGuard.assertAllowedUri(
          Uri.parse('https://daleventapos-backend.gcdndd.easypanel.host/ping'),
          key: 'REQUEST',
        ),
        returnsNormally,
      );
    });
  });
}
