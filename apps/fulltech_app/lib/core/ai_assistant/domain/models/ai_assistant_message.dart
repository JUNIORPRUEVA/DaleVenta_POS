import 'ai_assistant_citation.dart';

/// Archivo que viaja con un mensaje del chat.
///
/// Guarda los bytes **sólo** para poder enseñar la miniatura dentro de la conversación: el archivo
/// no se persiste en la app ni se vuelve a enviar (el motor ya lo tiene y el mensaje lleva su
/// `mediaJobId`). Por eso `bytes` puede ser `null` —archivo grande o mensaje reconstruido— y la
/// burbuja cae entonces a una ficha con el nombre.
class AiAssistantAttachment {
  const AiAssistantAttachment({
    required this.filename,
    required this.mimeType,
    this.bytes,
  });

  final String filename;
  final String mimeType;
  final List<int>? bytes;

  bool get isImage => mimeType.toLowerCase().startsWith('image/');
  bool get isAudio => mimeType.toLowerCase().startsWith('audio/');
  bool get hasPreview => isImage && (bytes?.isNotEmpty ?? false);
}

class AiAssistantMessage {
  final String id;
  final AiAssistantMessageRole role;
  final String content;
  final DateTime createdAt;
  final List<AiAssistantCitation> citations;
  final AiAssistantAttachment? attachment;

  const AiAssistantMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.citations = const [],
    this.attachment,
  });

  bool get isUser => role == AiAssistantMessageRole.user;
}

enum AiAssistantMessageRole { user, assistant }
