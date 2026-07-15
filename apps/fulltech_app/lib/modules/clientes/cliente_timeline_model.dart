class ClienteTimelineEvent {
  final String eventType;
  final String eventId;
  final DateTime at;
  final String title;
  final num? amount;
  final String? status;
  final String? userId;
  final String? userName;
  final Map<String, dynamic> meta;

  const ClienteTimelineEvent({
    required this.eventType,
    required this.eventId,
    required this.at,
    required this.title,
    this.amount,
    this.status,
    this.userId,
    this.userName,
    this.meta = const {},
  });

  static num? _parseAmount(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

  factory ClienteTimelineEvent.fromJson(Map<String, dynamic> json) {
    final at =
        DateTime.tryParse((json['at'] ?? '').toString()) ?? DateTime(1970);
    final metaRaw = json['meta'];

    return ClienteTimelineEvent(
      eventType: (json['eventType'] ?? '').toString(),
      eventId: (json['eventId'] ?? '').toString(),
      at: at,
      title: (json['title'] ?? '').toString(),
      amount: _parseAmount(json['amount']),
      status: (json['status'] as String?)?.trim().isEmpty == true
          ? null
          : json['status'] as String?,
      userId: (json['userId'] as String?)?.trim().isEmpty == true
          ? null
          : json['userId'] as String?,
      userName: (json['userName'] as String?)?.trim().isEmpty == true
          ? null
          : json['userName'] as String?,
      meta: metaRaw is Map ? metaRaw.cast<String, dynamic>() : const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'eventType': eventType,
      'eventId': eventId,
      'at': at.toIso8601String(),
      'title': title,
      'amount': amount,
      'status': status,
      'userId': userId,
      'userName': userName,
      'meta': meta,
    };
  }
}

class ClienteTimelineResponse {
  final List<ClienteTimelineEvent> items;
  final String before;
  final int take;

  const ClienteTimelineResponse({
    required this.items,
    required this.before,
    required this.take,
  });

  factory ClienteTimelineResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final List<dynamic> list = rawItems is List ? rawItems : const [];
    final mapped = list
        .whereType<Map>()
        .map((e) => ClienteTimelineEvent.fromJson(e.cast<String, dynamic>()))
        .toList();

    return ClienteTimelineResponse(
      items: mapped,
      before: (json['before'] ?? '').toString(),
      take: (json['take'] as num?)?.toInt() ?? mapped.length,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'before': before,
      'take': take,
    };
  }
}
