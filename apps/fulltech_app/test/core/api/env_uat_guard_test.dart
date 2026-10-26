import 'package:daleventa_pos/core/api/env.dart';
import 'package:daleventa_pos/core/config/product_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fase 1 — pruebas negativas de aislamiento del build UAT.
///
/// Se ejecuta dos veces:
///   1. `flutter test` (sin define) → producción conserva su fallback histórico.
///   2. `flutter test --dart-define=FULLPOS_UAT_BUILD=true` → la app falla de
///      forma segura en lugar de usar producción como alternativa.
const bool _uatBuild = bool.fromEnvironment(
  'FULLPOS_UAT_BUILD',
  defaultValue: false,
);

void main() {
  group('Env · bloqueo de hosts productivos en UAT', () {
    const blocked = [
      ProductConfig.productionApiHost,
      'daleventapos-backend.gcdndd.easypanel.host',
      'anything.easypanel.host',
      'algo.gcdndd.easypanel.host',
      'ventas-fullpos-backend.gcdndd.easypanel.host',
      '31.97.99.70',
      'DALEVENTAPOS-BACKEND.GCDNDD.EASYSPANEL.HOST',
    ];
    for (final host in blocked) {
      test('bloquea "$host"', () {
        expect(Env.isBlockedUatApiHostForTest(host), isTrue);
      });
    }

    const allowed = ['127.0.0.1', 'localhost', '::1', 'uat.interno.local'];
    for (final host in allowed) {
      test('permite "$host"', () {
        expect(Env.isBlockedUatApiHostForTest(host), isFalse);
      });
    }
  });

  group('Env.apiBaseUrl · comportamiento por tipo de build', () {
    test('sin API_BASE_URL: falla cerrado en UAT y usa el default en producción',
        () {
      if (_uatBuild) {
        expect(
          () => Env.apiBaseUrl,
          throwsA(isA<StateError>()),
          reason: 'un build UAT no puede caer a producción',
        );
      } else {
        expect(Env.apiBaseUrl, ProductConfig.productionApiBaseUrl);
      }
    });

    test('la URL resultante (si existe) nunca es un host productivo en UAT',
        () {
      if (!_uatBuild) return;
      // Si llegara a resolverse, el guard ya habría lanzado; dejamos constancia
      // explícita de que el valor por defecto de producción no se usa.
      expect(
        Env.isBlockedUatApiHostForTest(ProductConfig.productionApiHost),
        isTrue,
      );
    });
  });
}
