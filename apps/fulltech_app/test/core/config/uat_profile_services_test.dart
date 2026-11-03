import 'package:daleventa_pos/core/config/uat_api_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Blindaje del perfil UAT para los servicios que NO son el backend:
/// actualizador comercial, descarga de instaladores y analítica de marketing.
///
/// Las pruebas inyectan `uatProfile` porque `isUatProfile` es una constante de
/// compilación (`--dart-define`): en las pruebas vale `false`, así que el valor
/// real del build se pasa explícitamente. La última prueba comprueba el valor
/// por defecto, que es el que usan los builds comerciales.
void main() {
  group('actualizaciones comerciales', () {
    test('están deshabilitadas en el perfil UAT aunque estén configuradas', () {
      expect(
        UatApiConfig.commercialUpdatesAllowed(true, uatProfile: true),
        isFalse,
      );
    });

    test('siguen habilitadas en un build comercial configurado', () {
      expect(
        UatApiConfig.commercialUpdatesAllowed(true, uatProfile: false),
        isTrue,
      );
      expect(
        UatApiConfig.commercialUpdatesAllowed(false, uatProfile: false),
        isFalse,
      );
    });

    test('el valor por defecto respeta el flag real del build', () {
      // Sin `--dart-define=FULLPOS_UAT_PROFILE=true` el perfil no está activo,
      // así que el comportamiento comercial permanece intacto.
      expect(UatApiConfig.commercialUpdatesAllowed(true), isTrue);
      expect(UatApiConfig.commercialAnalyticsId('123456'), '123456');
    });
  });

  group('hosts de descarga de instaladores', () {
    const r2Host = '612fe68377329d5c3fbc84056a28aa64.r2.cloudflarestorage.com';

    test('el host comercial de almacenamiento queda fuera en el perfil UAT', () {
      expect(
        UatApiConfig.allowedUpdateDownloadHosts({r2Host}, uatProfile: true),
        isEmpty,
      );
    });

    test('un host local explícito sí se admite en el perfil UAT', () {
      final allowed = UatApiConfig.allowedUpdateDownloadHosts({
        ' 127.0.0.1 ',
        'localhost',
      }, uatProfile: true);
      expect(allowed, containsAll(<String>['127.0.0.1', 'localhost']));
    });

    test('un build comercial conserva los hosts configurados', () {
      final allowed = UatApiConfig.allowedUpdateDownloadHosts({
        r2Host,
      }, uatProfile: false);
      expect(allowed, {r2Host});
    });
  });

  group('analítica comercial', () {
    test('no se emite ningún identificador desde el perfil UAT', () {
      expect(
        UatApiConfig.commercialAnalyticsId('1234567890', uatProfile: true),
        isNull,
      );
    });

    test('un build comercial conserva su identificador', () {
      expect(
        UatApiConfig.commercialAnalyticsId('1234567890', uatProfile: false),
        '1234567890',
      );
    });
  });
}
