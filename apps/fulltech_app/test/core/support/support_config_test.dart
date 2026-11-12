import 'package:daleventa_pos/core/support/support_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupportConfig', () {
    test('usa el número oficial sin signos ni separadores', () {
      expect(SupportConfig.whatsappNumber, '18295319442');
      expect(RegExp(r'^[0-9]+$').hasMatch(SupportConfig.whatsappNumber), isTrue);
      expect(SupportConfig.phoneDisplay, '829-531-9442');
    });

    test('construye una URI wa.me válida', () {
      final uri = SupportConfig.whatsappUri('Hola, necesito ayuda');

      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/18295319442');
      expect(uri.queryParameters['text'], 'Hola, necesito ayuda');
    });

    test('codifica acentos, saltos de línea y símbolos', () {
      const message = 'Avería en Caja\nAño: 2026 · ¿qué hago? & + #';
      final uri = SupportConfig.whatsappUri(message);

      expect(uri.queryParameters['text'], message);
      expect(uri.toString(), isNot(contains(' ')));
      expect(uri.toString(), contains('wa.me/18295319442'));
    });

    test('usa el saludo por defecto si el mensaje está vacío', () {
      final uri = SupportConfig.whatsappUri('   ');

      expect(uri.queryParameters['text'], SupportConfig.defaultGreeting);
    });
  });
}
