import 'package:daleventa_pos/core/ai_assistant/application/ai_assistant_controller.dart';
import 'package:daleventa_pos/core/ai_assistant/data/datasources/ai_assistant_datasource.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/models/ai_chat_context.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/services/ai_assistant_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAiAssistantDataSource extends AiAssistantDataSource {
  _FakeAiAssistantDataSource() : super(Dio());

  final List<String?> sentConversationIds = [];
  final List<String?> sentClientMessageIds = [];
  final List<String?> sentMediaJobIds = [];
  final List<String> sentMessages = [];
  final List<String> uploadedFiles = [];

  String? nextConversationId = 'conv-1';
  String? nextMediaJobId = 'job-1';
  bool fail = false;
  bool failUpload = false;

  @override
  Future<Map<String, dynamic>> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
    String? conversationId,
    String? clientMessageId,
    String? mediaJobId,
  }) async {
    sentConversationIds.add(conversationId);
    sentClientMessageIds.add(clientMessageId);
    sentMediaJobIds.add(mediaJobId);
    sentMessages.add(message);
    if (fail) {
      throw StateError('fallo simulado');
    }
    return <String, dynamic>{
      'content': 'respuesta de prueba',
      'denied': false,
      'citations': <Map<String, dynamic>>[],
      'conversationId': nextConversationId,
      'requiresHumanReview': false,
    };
  }

  @override
  Future<Map<String, dynamic>> uploadAttachment({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    uploadedFiles.add(filename);
    if (failUpload) {
      throw StateError('subida fallida');
    }
    return <String, dynamic>{'mediaJobId': nextMediaJobId};
  }
}

void main() {
  late _FakeAiAssistantDataSource fake;
  late AiAssistantController controller;

  setUp(() {
    fake = _FakeAiAssistantDataSource();
    controller = AiAssistantController(AiAssistantService(fake));
    controller.setContext(const AiChatContext(module: 'catalogo'));
  });

  test('conserva el conversationId entre mensajes del mismo módulo', () async {
    await controller.sendMessage('primero');
    expect(fake.sentConversationIds, [null]);

    await controller.sendMessage('segundo');
    expect(fake.sentConversationIds, [null, 'conv-1']);
  });

  test('descarta la conversación al cambiar de módulo', () async {
    await controller.sendMessage('primero');
    await controller.sendMessage('segundo');
    expect(fake.sentConversationIds, [null, 'conv-1']);

    controller.setContext(const AiChatContext(module: 'ventas'));
    await controller.sendMessage('otro tema');

    expect(fake.sentConversationIds, [null, 'conv-1', null]);
  });

  test('reutiliza el clientMessageId al reintentar el mismo texto', () async {
    fake.fail = true;
    await controller.sendMessage('falla');
    final firstId = fake.sentClientMessageIds.last;

    await controller.sendMessage('falla');
    expect(fake.sentClientMessageIds.last, firstId);
    expect(fake.sentClientMessageIds.where((id) => id == firstId).length, 2);

    fake.fail = false;
    await controller.sendMessage('otro mensaje');
    expect(fake.sentClientMessageIds.last, isNot(firstId));
  });

  test('genera un clientMessageId distinto por mensaje correcto', () async {
    await controller.sendMessage('uno');
    await controller.sendMessage('dos');

    expect(fake.sentClientMessageIds.first, isNotNull);
    expect(fake.sentClientMessageIds.last, isNotNull);
    expect(
      fake.sentClientMessageIds.first,
      isNot(fake.sentClientMessageIds.last),
    );
  });

  test(
    'envía el adjunto procesado con el mensaje y lo descarta después',
    () async {
      await controller.attachFile(
        filename: 'captura.png',
        bytes: const [1, 2, 3],
        mimeType: 'image/png',
      );

      expect(fake.uploadedFiles, ['captura.png']);
      expect(controller.state.attachment?.mediaJobId, 'job-1');

      await controller.sendMessage('¿Qué dice la captura?');

      expect(fake.sentMediaJobIds, ['job-1']);
      expect(controller.state.attachment, isNull);

      await controller.sendMessage('y ahora qué hago');

      expect(fake.sentMediaJobIds, ['job-1', null]);
    },
  );

  test('un mensaje sin adjunto no envía mediaJobId', () async {
    await controller.sendMessage('¿Qué es FullPOS Cloud?');

    expect(fake.sentMediaJobIds, [null]);
  });

  test('si la subida falla, no se adjunta nada y se informa', () async {
    fake.failUpload = true;

    await controller.attachFile(
      filename: 'captura.png',
      bytes: const [1],
      mimeType: 'image/png',
    );

    expect(controller.state.attachment, isNull);
    expect(controller.state.uploadingAttachment, isFalse);
    expect(controller.state.lastError, isNotNull);
  });

  test('envía una nota de voz aunque no se haya escrito texto', () async {
    await controller.attachFile(
      filename: 'nota-de-voz-20261111-124530.m4a',
      bytes: const [1, 2, 3],
      mimeType: 'audio/mp4',
    );
    expect(controller.state.attachment, isNotNull);

    await controller.sendMessage('');

    expect(fake.sentMediaJobIds, ['job-1']);
    expect(
      fake.sentMessages.single,
      'Te envío una nota de voz.',
      reason: 'El turno necesita una frase con sentido, no un mensaje vacío.',
    );
    final userMessage = controller.state.messages.lastWhere((m) => m.isUser);
    expect(userMessage.content, contains('nota-de-voz-20261111-124530.m4a'));
    expect(
      controller.state.attachment,
      isNull,
      reason: 'El adjunto se consume al enviarse.',
    );
  });

  test('un adjunto que no es audio usa el texto genérico', () async {
    await controller.attachFile(
      filename: 'captura.png',
      bytes: const [1],
      mimeType: 'image/png',
    );

    await controller.sendMessage('   ');

    expect(fake.sentMediaJobIds, ['job-1']);
    expect(fake.sentMessages.single, 'Te envío un archivo adjunto.');
  });

  test('sin texto y sin adjunto no envía nada', () async {
    await controller.sendMessage('   ');

    expect(fake.sentMediaJobIds, isEmpty);
    expect(fake.sentMessages, isEmpty);
    expect(controller.state.messages.where((m) => m.isUser), isEmpty);
  });
}
