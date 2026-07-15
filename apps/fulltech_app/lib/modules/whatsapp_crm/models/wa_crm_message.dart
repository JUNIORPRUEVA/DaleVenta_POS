enum WaMessageDirection { incoming, outgoing }

enum WaMessageType { text, image, audio, video, document, sticker, other }

String? sanitizeWaText(dynamic value) {
  if (value is! String) return null;
  final technicalText = _readableEvolutionJsonText(value);
  if (technicalText != null) return technicalText;
  final units = value.codeUnits;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    final isHigh = unit >= 0xD800 && unit <= 0xDBFF;
    final isLow = unit >= 0xDC00 && unit <= 0xDFFF;

    if (isHigh) {
      if (i + 1 < units.length) {
        final next = units[i + 1];
        if (next >= 0xDC00 && next <= 0xDFFF) {
          out.writeCharCode(unit);
          out.writeCharCode(next);
          i++;
          continue;
        }
      }
      out.write('\uFFFD');
      continue;
    }

    if (isLow) {
      out.write('\uFFFD');
      continue;
    }

    // Keep common whitespace, but drop other control chars to avoid render issues.
    if (unit < 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) {
      continue;
    }

    out.writeCharCode(unit);
  }
  return out.toString();
}

String? _readableEvolutionJsonText(String value) {
  final text = value.trim();
  if (text.isEmpty || !text.startsWith('{')) return null;
  final looksLikeEvolutionPayload =
      text.contains('reactionMessage') ||
      text.contains('protocolMessage') ||
      text.contains('senderKeyDistributionMessage') ||
      text.contains('messageContextInfo') ||
      text.contains('deviceListMetadata');
  if (!looksLikeEvolutionPayload) return null;

  final reactionMatch = RegExp(
    r'"reactionMessage"\s*:\s*\{[\s\S]*?"text"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"',
  ).firstMatch(text);
  if (reactionMatch != null) {
    final reaction = _decodeJsonFragment(reactionMatch.group(1) ?? '').trim();
    return reaction.isEmpty ? 'Reaccionó a un mensaje' : 'Reacción: $reaction';
  }

  if (text.contains('protocolMessage')) return 'Actualización de WhatsApp';
  if (text.contains('senderKeyDistributionMessage')) {
    return 'Mensaje de sistema WhatsApp';
  }
  if (text.contains('messageContextInfo') ||
      text.contains('deviceListMetadata')) {
    return 'Mensaje técnico de WhatsApp';
  }
  return null;
}

String _decodeJsonFragment(String value) {
  return value
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', r'\')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\r', '\r')
      .replaceAll(r'\t', '\t');
}

class WaCrmMessage {
  const WaCrmMessage({
    required this.id,
    required this.conversationId,
    required this.direction,
    required this.messageType,
    required this.sentAt,
    this.evolutionId,
    this.body,
    this.mediaUrl,
    this.mediaMimeType,
    this.mediaStorageKey,
    this.mediaFileSize,
    this.mediaStatus,
    this.mediaError,
    this.caption,
    this.senderName,
  });

  final String id;
  final String conversationId;
  final WaMessageDirection direction;
  final WaMessageType messageType;
  final DateTime sentAt;
  final String? evolutionId;
  final String? body;
  final String? mediaUrl;
  final String? mediaMimeType;
  final String? mediaStorageKey;
  final int? mediaFileSize;
  final String? mediaStatus;
  final String? mediaError;
  final String? caption;
  final String? senderName;

  bool get isOutgoing => direction == WaMessageDirection.outgoing;
  bool get isIncoming => direction == WaMessageDirection.incoming;
  bool get mediaFailed => mediaStatus?.toLowerCase() == 'failed';

  String get previewText {
    switch (messageType) {
      case WaMessageType.image:
        return caption?.isNotEmpty == true ? 'Imagen: ${caption!}' : 'Imagen';
      case WaMessageType.audio:
        return 'Audio';
      case WaMessageType.video:
        return caption?.isNotEmpty == true ? 'Video: ${caption!}' : 'Video';
      case WaMessageType.document:
        return body?.isNotEmpty == true ? 'Documento: $body' : 'Documento';
      case WaMessageType.sticker:
        return 'Sticker';
      default:
        return body ?? '';
    }
  }

  factory WaCrmMessage.fromJson(Map<String, dynamic> json) {
    return WaCrmMessage(
      id: sanitizeWaText(json['id']) ?? '',
      conversationId:
          sanitizeWaText(json['conversationId'] ?? json['conversation_id']) ??
          '',
      direction: _parseDirection(
        sanitizeWaText(json['direction']) ?? 'INCOMING',
      ),
      messageType: _parseType(
        sanitizeWaText(json['messageType'] ?? json['message_type']) ?? 'TEXT',
      ),
      sentAt: _parseDate(json['sentAt'] ?? json['sent_at']) ?? DateTime.now(),
      evolutionId: sanitizeWaText(json['evolutionId'] ?? json['evolution_id']),
      body: sanitizeWaText(json['body']),
      mediaUrl: sanitizeWaText(json['mediaUrl'] ?? json['media_url']),
      mediaMimeType: sanitizeWaText(
        json['mediaMimeType'] ?? json['media_mime_type'],
      ),
      mediaStorageKey: sanitizeWaText(
        json['mediaStorageKey'] ?? json['media_storage_key'],
      ),
      mediaFileSize: (json['mediaFileSize'] ?? json['media_file_size']) is num
          ? ((json['mediaFileSize'] ?? json['media_file_size']) as num).toInt()
          : null,
      mediaStatus: sanitizeWaText(json['mediaStatus'] ?? json['media_status']),
      mediaError: sanitizeWaText(json['mediaError'] ?? json['media_error']),
      caption: sanitizeWaText(json['caption']),
      senderName: sanitizeWaText(json['senderName'] ?? json['sender_name']),
    );
  }

  static WaMessageDirection _parseDirection(String v) {
    switch (v.toUpperCase()) {
      case 'OUTGOING':
        return WaMessageDirection.outgoing;
      default:
        return WaMessageDirection.incoming;
    }
  }

  static WaMessageType _parseType(String v) {
    switch (v.toUpperCase()) {
      case 'IMAGE':
        return WaMessageType.image;
      case 'AUDIO':
        return WaMessageType.audio;
      case 'VIDEO':
        return WaMessageType.video;
      case 'DOCUMENT':
        return WaMessageType.document;
      case 'STICKER':
        return WaMessageType.sticker;
      case 'OTHER':
        return WaMessageType.other;
      default:
        return WaMessageType.text;
    }
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}
