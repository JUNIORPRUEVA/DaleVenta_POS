import 'ai_assistant_citation.dart';
import 'ai_assistant_resource.dart';
import 'ai_support_case.dart';

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
  final List<AiAssistantResource> resources;
  final AiAssistantAttachment? attachment;
  final AiSupportIncident? incident;
  final AiSupportCase? supportCase;
  final bool requiresHumanReview;

  const AiAssistantMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.citations = const [],
    this.resources = const [],
    this.attachment,
    this.incident,
    this.supportCase,
    this.requiresHumanReview = false,
  });

  bool get isUser => role == AiAssistantMessageRole.user;
}

class AiSupportIncident {
  final String reference;
  final String status;
  final bool duplicate;

  const AiSupportIncident({
    required this.reference,
    required this.status,
    this.duplicate = false,
  });

  static AiSupportIncident? fromMap(dynamic value) {
    if (value is! Map) return null;
    final reference = value['reference'];
    final status = value['status'];
    if (reference is! String ||
        !RegExp(r'^FPS-\d{4}-\d{6,}$').hasMatch(reference) ||
        !const {
          'OPEN',
          'IN_PROGRESS',
          'WAITING_CUSTOMER',
          'RESOLVED',
          'CLOSED',
        }.contains(status)) {
      return null;
    }
    return AiSupportIncident(
      reference: reference,
      status: status as String,
      duplicate: value['duplicate'] == true,
    );
  }
}

enum AiAssistantMessageRole { user, assistant }
