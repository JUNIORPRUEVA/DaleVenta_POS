import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El webhook del proveedor llega a `https://<host>/webhook/dosa` (sin `/api`),
/// que es la URL que DOSA ya tiene configurada. La PWA es quien recibe esa
/// ruta, así que el proxy tiene que reenviarla al backend: si cae en
/// `try_files`, nginx responde **405** a un POST y el evento se pierde.
///
/// Esta prueba fija el contrato del `docker-entrypoint.sh` (plantilla nginx).
void main() {
  late String nginx;

  setUpAll(() {
    final file = File('docker-entrypoint.sh');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'La plantilla nginx viaja dentro de la imagen de la PWA.',
    );
    nginx = file.readAsStringSync();
  });

  group('proxy del webhook DOSA', () {
    test('reenvía /webhook/ al backend', () {
      expect(nginx, contains('location ^~ /webhook/'));
      expect(nginx, contains('proxy_pass __UPSTREAM__/webhook/;'));
    });

    test('mantiene la ruta canónica /api/', () {
      expect(nginx, contains('location /api/'));
      expect(nginx, contains('proxy_pass __UPSTREAM__/;'));
    });

    test('el webhook no cae en el fallback estático', () {
      // Un `try_files` para /webhook/ devolvería el index.html y un POST sería
      // 405. El bloque debe ser de proxy, no de ficheros.
      final bloque = RegExp(
        r'location \^~ /webhook/ \{[^}]*\}',
        dotAll: true,
      ).firstMatch(nginx);
      expect(bloque, isNotNull);
      expect(bloque!.group(0)!.contains('try_files'), isFalse);
      expect(bloque.group(0)!.contains('proxy_pass'), isTrue);
    });
  });
}
