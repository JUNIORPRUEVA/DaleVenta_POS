import 'package:dio/dio.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/ai_assistant/data/datasources/ai_assistant_datasource.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/models/ai_assistant_resource.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/models/ai_chat_context.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/services/ai_assistant_service.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_resource_card.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_chat_panel_host.dart';

class _ResourceService extends AiAssistantService {
  _ResourceService(this.bytes) : super(_ResourceDataSource({}));
  final Uint8List bytes;
  @override
  Future<Uint8List> resourceBytes(AiAssistantResource resource) async => bytes;
}

class _ResourceDataSource extends AiAssistantDataSource {
  _ResourceDataSource(this.reply) : super(Dio());
  final Map<String, dynamic> reply;
  @override
  Future<Map<String, dynamic>> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
    String? conversationId,
    String? clientMessageId,
    String? mediaJobId,
  }) async => reply;
}

void main() {
  testWidgets(
    'an approved image has an accessible action and opens a real preview',
    (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(
        recorder,
      ).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final bytes = (await tester.runAsync(() async {
        final image = await picture.toImage(2, 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final result = data!.buffer.asUint8List();
        image.dispose();
        return result;
      }))!;
      picture.dispose();
      const resource = AiAssistantResource(
        id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        title: 'Captura de ayuda',
        kind: 'IMAGE',
        mimeType: 'image/png',
        fileName: 'ayuda.png',
        sizeBytes: 100,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            aiAssistantServiceProvider.overrideWithValue(
              _ResourceService(bytes),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 320,
                  height: 500,
                  child: AiChatPanelHost(
                    child: AiAssistantResourceCard(resource: resource),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(AiAssistantResourceCard)),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.bySemanticsLabel('Abrir imagen: Captura de ayuda');
      expect(action, findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cerrar imagen'), findsOneWidget);
      final panel = tester.getRect(find.byType(AiChatPanelHost));
      final preview = tester.getRect(find.byType(Dialog));
      expect(preview.left, greaterThanOrEqualTo(panel.left));
      expect(preview.top, greaterThanOrEqualTo(panel.top));
      expect(preview.right, lessThanOrEqualTo(panel.right));
      expect(preview.bottom, lessThanOrEqualTo(panel.bottom));
      await tester.tap(find.byTooltip('Cerrar imagen'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Cerrar imagen'), findsNothing);
    },
  );
  const image = {
    'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'title': 'Captura de ayuda',
    'kind': 'IMAGE',
    'mimeType': 'image/png',
    'fileName': 'captura.png',
    'sizeBytes': 100,
    'version': 1,
  };
  test('accepts approved image, video and document metadata', () {
    expect(AiAssistantResource.fromMap(image)?.isImage, isTrue);
    expect(
      AiAssistantResource.fromMap({
        ...image,
        'kind': 'VIDEO',
        'mimeType': 'video/mp4',
      })?.isVideo,
      isTrue,
    );
    expect(
      AiAssistantResource.fromMap({
        ...image,
        'kind': 'DOCUMENT',
        'mimeType': 'application/pdf',
      })?.kind,
      'DOCUMENT',
    );
  });
  test('rejects mismatched, oversized and unsafe resource identifiers', () {
    for (final row in [
      {...image, 'id': '../another-agent'},
      {...image, 'kind': 'VIDEO'},
      {...image, 'sizeBytes': 33 * 1024 * 1024},
      {...image, 'mimeType': 'text/html'},
    ]) {
      expect(AiAssistantResource.fromMap(row), isNull);
    }
  });
  test('legacy responses do not require a resources field', () async {
    final service = AiAssistantService(
      _ResourceDataSource({'content': 'Respuesta anterior'}),
    );
    final reply = await service.chat(
      context: const AiChatContext(module: 'ventas'),
      message: 'Ayuda',
      history: [],
    );
    expect(reply.resources, isEmpty);
    expect(reply.content, 'Respuesta anterior');
  });
  test(
    'parses up to three library resources without losing the response',
    () async {
      final service = AiAssistantService(
        _ResourceDataSource({
          'content': 'Consulta esta ayuda',
          'resources': [image, image, image, image],
        }),
      );
      final reply = await service.chat(
        context: const AiChatContext(module: 'ventas'),
        message: 'Ayuda',
        history: [],
      );
      expect(reply.resources, hasLength(3));
      expect(reply.resources.first.title, 'Captura de ayuda');
    },
  );
}
