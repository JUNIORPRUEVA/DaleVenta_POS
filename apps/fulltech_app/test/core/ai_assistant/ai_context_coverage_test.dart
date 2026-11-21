import 'package:daleventa_pos/core/ai_assistant/presentation/ai_chat_context_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Facturación mantiene su ruta técnica y permite cotizar sin ser el historial', () {
    final billing = buildAiChatContextFromLocation('/cotizaciones?quoteId=quote-123');
    expect(billing.module, 'cotizaciones');
    expect(billing.screenName, 'Facturación');
    expect(billing.route, '/cotizaciones?quoteId=quote-123');
    expect(billing.entityType, 'quote');
    expect(billing.entityId, 'quote-123');
    final history = buildAiChatContextFromLocation('/cotizaciones/historial');
    expect(history.screenName, 'Historial de cotizaciones');
    expect(history.module, 'cotizaciones');
    expect(buildAiChatContextFromLocation('/ventas/nueva').screenName, 'Facturación');
  });
  for (final entry in {
    '/ecf/documents': 'ecf',
    '/planes/pago': 'planes',
    '/caja/turnos': 'caja',
    '/ventas/compras/suplidores': 'compras',
    '/configuracion/almacenes': 'almacenes',
    '/ventas/creditos': 'ventas',
  }.entries) {
    test('identifica ${entry.key} sin confundir módulos', () {
      final context = buildAiChatContextFromLocation(entry.key);
      expect(context.module, entry.value);
      expect(context.screenName, isNotEmpty);
    });
  }
}
