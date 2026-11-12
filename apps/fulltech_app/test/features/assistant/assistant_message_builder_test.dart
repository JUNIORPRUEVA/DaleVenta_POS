import 'package:daleventa_pos/features/assistant/domain/assistant_message_builder.dart';
import 'package:daleventa_pos/features/assistant/domain/assistant_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AssistantMessageBuilder · avería', () {
    test('incluye tipo, módulo y descripción', () {
      final message = AssistantMessageBuilder.fault(
        module: AssistantSupportModule.cash,
        description: 'Al hacer corte de turno la app se cierra.',
      );

      expect(message, contains('Tipo: Avería'));
      expect(message, contains('Módulo: Caja y turnos'));
      expect(
        message,
        contains('Descripción: Al hacer corte de turno la app se cierra.'),
      );
    });

    test('agrega empresa, plataforma y versión cuando existen', () {
      final message = AssistantMessageBuilder.fault(
        module: AssistantSupportModule.billing,
        description: 'No guarda la venta.',
        companyName: 'Colmado La Esquina',
        platformLabel: 'Windows',
        appVersion: '1.0.7+151',
      );

      expect(message, contains('Empresa: Colmado La Esquina'));
      expect(message, contains('Plataforma: Windows'));
      expect(message, contains('Versión: 1.0.7+151'));
    });

    test('omite campos opcionales vacíos y normaliza espacios', () {
      final message = AssistantMessageBuilder.fault(
        module: AssistantSupportModule.other,
        description: '  Falla   al   cobrar  ',
        extra: '   ',
        companyName: '   ',
        platformLabel: '',
        appVersion: null,
      );

      expect(message, contains('Descripción: Falla al cobrar'));
      expect(message, isNot(contains('Información adicional:')));
      expect(message, isNot(contains('Empresa:')));
      expect(message, isNot(contains('Plataforma:')));
      expect(message, isNot(contains('Versión:')));
    });
  });

  group('AssistantMessageBuilder · sugerencia', () {
    test('incluye tipo, título y descripción', () {
      final message = AssistantMessageBuilder.suggestion(
        title: 'Exportar ventas a Excel',
        description: 'Necesito descargar el reporte del día en Excel.',
        platformLabel: 'Android',
      );

      expect(message, contains('Tipo: Sugerencia de mejora'));
      expect(message, contains('Título: Exportar ventas a Excel'));
      expect(
        message,
        contains(
          'Descripción: Necesito descargar el reporte del día en Excel.',
        ),
      );
      expect(message, contains('Plataforma: Android'));
    });
  });

  group('AssistantMessageBuilder · privacidad', () {
    test('no agrega datos de clientes ni credenciales por sí mismo', () {
      final message = AssistantMessageBuilder.fault(
        module: AssistantSupportModule.users,
        description: 'No puedo entrar al módulo de usuarios.',
      );

      // El constructor solo escribe los campos que recibe; nunca inventa
      // contraseñas, tokens, PIN, importes ni datos de clientes.
      expect(message.toLowerCase(), isNot(contains('password')));
      expect(message.toLowerCase(), isNot(contains('token')));
      expect(message.toLowerCase(), isNot(contains('pin:')));
      expect(message.toLowerCase(), isNot(contains('cliente:')));
    });

    test('el mensaje de contacto es corto y no expone datos internos', () {
      final greeting = AssistantMessageBuilder.greeting();

      expect(greeting, 'Hola, necesito asistencia con FullPOS Cloud.');
      expect(greeting.length, lessThan(80));
    });
  });
}
