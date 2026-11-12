import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../utils/trace_id.dart';
import '../domain/models/ai_chat_context.dart';
import '../domain/models/ai_assistant_message.dart';
import '../domain/services/ai_assistant_service.dart';

class AiAssistantState {
  final AiChatContext context;
  final List<AiAssistantMessage> messages;
  final bool sending;
  final bool uploadingAttachment;
  final AiPendingAttachment? attachment;
  final String? lastError;

  const AiAssistantState({
    required this.context,
    this.messages = const [],
    this.sending = false,
    this.uploadingAttachment = false,
    this.attachment,
    this.lastError,
  });

  AiAssistantState copyWith({
    AiChatContext? context,
    List<AiAssistantMessage>? messages,
    bool? sending,
    bool? uploadingAttachment,
    AiPendingAttachment? attachment,
    bool clearAttachment = false,
    String? lastError,
    bool clearError = false,
  }) {
    return AiAssistantState(
      context: context ?? this.context,
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
      uploadingAttachment: uploadingAttachment ?? this.uploadingAttachment,
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Archivo ya procesado por el motor y pendiente de enviar con el próximo mensaje.
class AiPendingAttachment {
  final String filename;
  final String mediaJobId;
  final String mimeType;

  const AiPendingAttachment({
    required this.filename,
    required this.mediaJobId,
    this.mimeType = '',
  });

  bool get isAudio => mimeType.toLowerCase().startsWith('audio/');
}

final aiAssistantControllerProvider =
    StateNotifierProvider<AiAssistantController, AiAssistantState>((ref) {
      return AiAssistantController(ref.watch(aiAssistantServiceProvider));
    });

final hideGlobalAiAssistantEntryPointProvider = Provider<bool>((ref) => false);

final desktopAiAssistantPanelOpenProvider = StateProvider<bool>((ref) => false);

class AiAssistantController extends StateNotifier<AiAssistantState> {
  AiAssistantController(this._service)
    : super(AiAssistantState(context: const AiChatContext(module: 'general')));

  static const _uuid = Uuid();

  final AiAssistantService _service;

  /// Conversación abierta en APPYRA IA. Se conserva entre mensajes del mismo módulo y se
  /// descarta al cambiar de módulo (eso cuenta como conversación nueva).
  String? _conversationId;

  /// Último envío fallido, para reutilizar su identificador si el usuario lo reintenta.
  String? _failedMessageContent;
  String? _failedClientMessageId;

  void setContext(AiChatContext context) {
    final sameContext =
        state.context.module == context.module &&
        state.context.screenName == context.screenName &&
        state.context.route == context.route &&
        state.context.entityType == context.entityType &&
        state.context.entityId == context.entityId;
    if (sameContext) return;

    final moduleChanged = state.context.module != context.module;
    final nextMessages = state.messages.isEmpty
        ? [_buildStarterMessage(context)]
        : state.messages;
    if (moduleChanged) {
      _conversationId = null;
      _failedMessageContent = null;
      _failedClientMessageId = null;
    }
    state = state.copyWith(
      context: context,
      messages: nextMessages,
      clearAttachment: moduleChanged,
    );
  }

  /// Sube el archivo y lo deja listo para el próximo mensaje.
  ///
  /// Mientras se procesa, el compositor queda ocupado: enviar el mensaje sin el adjunto ya
  /// procesado daría una respuesta que ignora la captura sin avisar de nada.
  Future<void> attachFile({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    if (state.uploadingAttachment) return;
    state = state.copyWith(uploadingAttachment: true, clearError: true);
    try {
      final mediaJobId = await _service.uploadAttachment(
        filename: filename,
        bytes: bytes,
        mimeType: mimeType,
      );
      state = state.copyWith(
        uploadingAttachment: false,
        attachment: AiPendingAttachment(
          filename: filename,
          mediaJobId: mediaJobId,
          mimeType: mimeType,
        ),
      );
    } catch (e) {
      state = state.copyWith(
        uploadingAttachment: false,
        lastError: e.toString(),
      );
    }
  }

  void clearAttachment() {
    if (state.attachment == null) return;
    state = state.copyWith(clearAttachment: true);
  }

  String _clientMessageIdFor(String message) {
    if (_failedClientMessageId != null && _failedMessageContent == message) {
      return _failedClientMessageId!;
    }
    return _uuid.v4();
  }

  AiAssistantMessage _buildStarterMessage(AiChatContext context) {
    final area = _describeContext(context);
    return AiAssistantMessage(
      id: TraceId.next('ai-assistant-intro'),
      role: AiAssistantMessageRole.assistant,
      content:
          'Estoy listo para orientarte en $area. Puedo explicarte la pantalla actual, resumirte normas del Manual Interno y ayudarte a validar datos reales como clientes, cotizaciones u operaciones cuando exista contexto autorizado.',
      createdAt: DateTime.now(),
    );
  }

  String _describeContext(AiChatContext context) {
    final screen = (context.screenName ?? '').trim();
    if (screen.isNotEmpty) return 'la pantalla "$screen"';

    switch (context.module.trim().toLowerCase()) {
      case 'clientes':
        return 'Clientes';
      case 'catalogo':
        return 'Productos';
      case 'cotizaciones':
        return 'Cotizaciones';
      case 'service-orders':
        return 'Operaciones';
      case 'manual-interno':
        return 'Manual Interno';
      default:
        return 'FULLTECH';
    }
  }

  List<Map<String, dynamic>> _buildHistoryPayload() {
    final all = state.messages;
    final start = all.length > 16 ? all.length - 16 : 0;
    final items = all.sublist(start);
    return items.map((m) {
      return {'role': m.isUser ? 'user' : 'assistant', 'content': m.content};
    }).toList();
  }

  Future<void> sendMessage(String message) async {
    final normalized = message.trim();
    final pendingAttachment = state.attachment;
    // Un adjunto es un mensaje por sí mismo: una nota de voz, una foto o un PDF
    // deben poder enviarse sin escribir texto.
    if (normalized.isEmpty && pendingAttachment == null) return;

    if (state.sending) return;

    final now = DateTime.now();
    // El turno necesita una frase con sentido: si solo hay archivo, se dice qué
    // se envía en lugar de mandar un mensaje vacío al modelo.
    final turnText = normalized.isNotEmpty
        ? normalized
        : (pendingAttachment!.isAudio
              ? 'Te envío una nota de voz.'
              : 'Te envío un archivo adjunto.');

    final nextMessages = List<AiAssistantMessage>.from(state.messages)
      ..add(
        AiAssistantMessage(
          id: TraceId.next('ai-user'),
          role: AiAssistantMessageRole.user,
          // El nombre del archivo queda en el mensaje: si el turno falla, el usuario ve a qué
          // mensaje pertenecía el adjunto en lugar de un texto sin contexto.
          content: pendingAttachment == null
              ? turnText
              : '$turnText\n\nAdjunto: ${pendingAttachment.filename}',
          createdAt: now,
        ),
      );

    state = state.copyWith(
      messages: nextMessages,
      sending: true,
      clearError: true,
    );

    final clientMessageId = _clientMessageIdFor(turnText);
    final attachment = state.attachment;

    try {
      final result = await _service.chat(
        context: state.context,
        message: turnText,
        history: _buildHistoryPayload(),
        conversationId: _conversationId,
        clientMessageId: clientMessageId,
        mediaJobId: attachment?.mediaJobId,
      );

      final nextConversationId = result.conversationId;
      if (nextConversationId != null && nextConversationId.trim().isNotEmpty) {
        _conversationId = nextConversationId.trim();
      }
      _failedMessageContent = null;
      _failedClientMessageId = null;

      final assistant = AiAssistantMessage(
        id: TraceId.next('ai-assistant'),
        role: AiAssistantMessageRole.assistant,
        content: result.content,
        citations: result.citations,
        createdAt: DateTime.now(),
      );

      state = state.copyWith(
        messages: [...state.messages, assistant],
        sending: false,
        clearAttachment: attachment != null,
      );
    } catch (e) {
      _failedMessageContent = turnText;
      _failedClientMessageId = clientMessageId;
      final content = e.toString();
      final assistant = AiAssistantMessage(
        id: TraceId.next('ai-assistant-error'),
        role: AiAssistantMessageRole.assistant,
        content: content,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(
        messages: [...state.messages, assistant],
        sending: false,
        lastError: content,
      );
    }
  }
}
