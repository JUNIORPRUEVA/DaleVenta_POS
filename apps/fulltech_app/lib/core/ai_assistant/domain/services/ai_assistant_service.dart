import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../errors/api_exception.dart';
import '../../data/datasources/ai_assistant_datasource.dart';
import '../models/ai_chat_context.dart';
import '../models/ai_assistant_citation.dart';

final aiAssistantServiceProvider = Provider<AiAssistantService>((ref) {
  return AiAssistantService(ref.watch(aiAssistantDataSourceProvider));
});

class AiAssistantChatResult {
  final String content;
  final bool denied;
  final List<AiAssistantCitation> citations;

  /// Conversación en APPYRA IA. El panel la reenvía para conservar la continuidad.
  final String? conversationId;

  /// La respuesta exige revisión humana (derivación o validación fallida).
  final bool requiresHumanReview;

  const AiAssistantChatResult({
    required this.content,
    required this.denied,
    required this.citations,
    this.conversationId,
    this.requiresHumanReview = false,
  });
}

class AiAssistantService {
  final AiAssistantDataSource _dataSource;

  AiAssistantService(this._dataSource);

  Future<AiAssistantChatResult> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
    String? conversationId,
    String? clientMessageId,
    String? mediaJobId,
  }) async {
    final res = await _dataSource.chat(
      context: context,
      message: message,
      history: history,
      conversationId: conversationId,
      clientMessageId: clientMessageId,
      mediaJobId: mediaJobId,
    );

    final content = (res['content'] ?? res['message'] ?? '').toString();
    final denied = res['denied'] == true;
    final rawConversationId = res['conversationId'];
    final requiresHumanReview = res['requiresHumanReview'] == true;

    final rawCitations = res['citations'];
    final citations = <AiAssistantCitation>[];
    if (rawCitations is List) {
      for (final item in rawCitations) {
        if (item is Map) {
          citations.add(
            AiAssistantCitation.fromMap(item.cast<String, dynamic>()),
          );
        }
      }
    }

    return AiAssistantChatResult(
      content: content.trim().isEmpty
          ? 'No pude generar una respuesta válida. Inténtalo de nuevo.'
          : content,
      denied: denied,
      citations: citations,
      conversationId:
          rawConversationId is String && rawConversationId.trim().isNotEmpty
          ? rawConversationId.trim()
          : null,
      requiresHumanReview: requiresHumanReview,
    );
  }

  /// Sube un archivo y devuelve el identificador del trabajo multimedia.
  ///
  /// El texto extraído no vuelve por aquí: lo usa el motor al responder el mensaje que lo
  /// acompañe, y así el contenido del archivo nunca se muestra como si fuera una respuesta.
  Future<String> uploadAttachment({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final res = await _dataSource.uploadAttachment(
      filename: filename,
      bytes: bytes,
      mimeType: mimeType,
    );
    final jobId = (res['mediaJobId'] ?? '').toString().trim();
    if (jobId.isEmpty) {
      throw ApiException('El motor no devolvió el identificador del archivo.');
    }
    return jobId;
  }
}
