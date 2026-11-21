import 'package:daleventa_pos/core/ai_assistant/data/datasources/ai_assistant_datasource.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/models/ai_support_case.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_chat_panel_host.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_support_case_link.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SupportSource extends AiAssistantDataSource {
  _SupportSource() : super(Dio());
  final keys = <String?>[];
  bool fail = false;
  String status = 'open';
  @override
  Future<Map<String, dynamic>> supportCase(String id, {String? message, String? requestId}) async {
    if (message != null) keys.add(requestId);
    if (fail) throw ApiException('No se pudo confirmar');
    return {'id': id, 'reference': 'SUP-123', 'status': status,
      'messages': [{'authorType': 'user', 'body': 'Estamos revisando tu caso'}]};
  }
}

void main() {
  for (final width in [390.0, 1280.0]) {
    testWidgets('consulta y respuesta quedan dentro del chat a $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final source = _SupportSource();
      await tester.pumpWidget(ProviderScope(overrides: [aiAssistantDataSourceProvider.overrideWithValue(source)],
        child: MaterialApp(home: Scaffold(body: Align(alignment: Alignment.centerRight,
          child: SizedBox(width: width < 500 ? width : 500, child: AiChatPanelHost(
            child: const AiSupportCaseLink(supportCase: AiSupportCase(id: 'case-1', reference: 'SUP-123')))))))));
      await tester.tap(find.text('Ver soporte · SUP-123'));
      await tester.pumpAndSettle();
      expect(find.text('Abierto'), findsOneWidget);
      expect(find.textContaining('Estamos revisando'), findsOneWidget);
      final panel = tester.getRect(find.byType(AiChatPanelHost));
      final dialog = tester.getRect(find.byType(AlertDialog));
      expect(dialog.left, greaterThanOrEqualTo(panel.left));
      expect(dialog.top, greaterThanOrEqualTo(panel.top));
      expect(dialog.right, lessThanOrEqualTo(panel.right));
      expect(dialog.bottom, lessThanOrEqualTo(panel.bottom));
      await tester.enterText(find.byType(TextField), 'Gracias');
      source.fail = true;
      await tester.tap(find.text('Enviar a soporte')); await tester.pumpAndSettle();
      expect(find.text('No se pudo confirmar'), findsOneWidget);
      source.fail = false;
      await tester.tap(find.text('Enviar a soporte')); await tester.pumpAndSettle();
      expect(source.keys.length, 2); expect(source.keys[0], source.keys[1]);
      source.status = 'resolved';
      await tester.tap(find.text('Actualizar')); await tester.pumpAndSettle();
      expect(find.text('Resuelto'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Volver al chat')); await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
