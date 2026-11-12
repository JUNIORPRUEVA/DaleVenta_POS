import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/auth_repository.dart';
import '../../../api/api_routes.dart';
import '../../../errors/api_exception.dart';
import '../../domain/models/ai_chat_context.dart';

final aiAssistantDataSourceProvider = Provider<AiAssistantDataSource>((ref) {
  return AiAssistantDataSource(ref.watch(dioProvider));
});

class AiAssistantDataSource {
  AiAssistantDataSource(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
    String? conversationId,
    String? clientMessageId,
    String? mediaJobId,
  }) async {
    final conversation = (conversationId ?? '').trim();
    final clientMessage = (clientMessageId ?? '').trim();
    final media = (mediaJobId ?? '').trim();
    return _post(
      ApiRoutes.aiChat,
      data: {
        'context': context.toMap(),
        'message': message.trim(),
        if (history.isNotEmpty) 'history': history,
        if (conversation.isNotEmpty) 'conversationId': conversation,
        if (clientMessage.isNotEmpty) 'clientMessageId': clientMessage,
        if (media.isNotEmpty) 'mediaJobId': media,
      },
    );
  }

  /// Sube una captura o un documento al motor multimedia del asistente.
  ///
  /// El archivo no se guarda en la app: se envía al backend, que lo reenvía al motor. La respuesta
  /// trae el identificador que hay que incluir en el siguiente mensaje.
  Future<Map<String, dynamic>> uploadAttachment({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType.parse(mimeType),
        ),
      });
      final response = await _dio.post(
        ApiRoutes.aiAttachments,
        data: form,
        // Sin `contentType` explícito: Dio añade `multipart/form-data` **con** su `boundary`, y
        // fijarlo a mano lo dejaría fuera y el servidor no podría separar las partes.
        options: Options(extra: const {'skipLoader': true}),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return data.cast<String, dynamic>();
      throw ApiException('Respuesta inválida al adjuntar el archivo.');
    } on DioException catch (error) {
      final message = _extractMessage(
        error.response?.data,
        'No se pudo adjuntar el archivo.',
      );
      throw ApiException(message, error.response?.statusCode);
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, {
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: data,
        options: Options(extra: const {'skipLoader': true}),
      );
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      if (response.data is Map) {
        return (response.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del asistente IA.');
    } on DioException catch (error) {
      final message = _extractMessage(
        error.response?.data,
        'No se pudo consultar el asistente IA.',
      );
      throw ApiException(message, error.response?.statusCode);
    }
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .join(' | ');
        if (normalized.isNotEmpty) return normalized;
      }
      final errorMessage = data['error'];
      if (errorMessage is String && errorMessage.trim().isNotEmpty) {
        return errorMessage;
      }
    }
    return fallback;
  }
}
