class CrmComercialUserRef {
  const CrmComercialUserRef({
    required this.id,
    required this.nombreCompleto,
    this.role,
  });

  final String id;
  final String nombreCompleto;
  final String? role;

  factory CrmComercialUserRef.fromJson(Map<String, dynamic> json) {
    return CrmComercialUserRef(
      id: (json['id'] ?? '').toString(),
      nombreCompleto: (json['nombreCompleto'] ?? 'Sin nombre').toString(),
      role: json['role']?.toString(),
    );
  }
}

class CrmComercialStatusEntry {
  const CrmComercialStatusEntry({
    required this.id,
    required this.estadoNuevo,
    this.estadoAnterior,
    this.nota,
    this.createdAt,
    this.changedBy,
  });

  final String id;
  final String estadoNuevo;
  final String? estadoAnterior;
  final String? nota;
  final DateTime? createdAt;
  final CrmComercialUserRef? changedBy;

  factory CrmComercialStatusEntry.fromJson(Map<String, dynamic> json) {
    return CrmComercialStatusEntry(
      id: (json['id'] ?? '').toString(),
      estadoNuevo: (json['estadoNuevo'] ?? '').toString(),
      estadoAnterior: json['estadoAnterior']?.toString(),
      nota: json['nota']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      changedBy: (json['changedByUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['changedByUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialNote {
  const CrmComercialNote({
    required this.id,
    required this.note,
    this.createdAt,
    this.author,
  });

  final String id;
  final String note;
  final DateTime? createdAt;
  final CrmComercialUserRef? author;

  factory CrmComercialNote.fromJson(Map<String, dynamic> json) {
    return CrmComercialNote(
      id: (json['id'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      author: (json['authorUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['authorUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialActivity {
  const CrmComercialActivity({
    required this.id,
    required this.activityType,
    required this.description,
    this.dueAt,
    this.completedAt,
    this.createdAt,
    this.assignedTo,
    this.createdBy,
  });

  final String id;
  final String activityType;
  final String description;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final CrmComercialUserRef? assignedTo;
  final CrmComercialUserRef? createdBy;

  factory CrmComercialActivity.fromJson(Map<String, dynamic> json) {
    return CrmComercialActivity(
      id: (json['id'] ?? '').toString(),
      activityType: (json['activityType'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      dueAt: DateTime.tryParse((json['dueAt'] ?? '').toString()),
      completedAt: DateTime.tryParse((json['completedAt'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      assignedTo: (json['assignedToUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['assignedToUser'] as Map<String, dynamic>,
            )
          : null,
      createdBy: (json['createdByUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['createdByUser'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class CrmComercialCustomer {
  const CrmComercialCustomer({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.estadoActual,
    this.direccion,
    this.ciudad,
    this.etiqueta,
    this.nextAction,
    this.nextActionAt,
    this.updatedAt,
    this.responsable,
    this.statusHistory = const [],
    this.notes = const [],
    this.activities = const [],
  });

  final String id;
  final String nombre;
  final String telefono;
  final String estadoActual;
  final String? direccion;
  final String? ciudad;
  final String? etiqueta;
  final String? nextAction;
  final DateTime? nextActionAt;
  final DateTime? updatedAt;
  final CrmComercialUserRef? responsable;
  final List<CrmComercialStatusEntry> statusHistory;
  final List<CrmComercialNote> notes;
  final List<CrmComercialActivity> activities;

  factory CrmComercialCustomer.fromJson(Map<String, dynamic> json) {
    return CrmComercialCustomer(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      estadoActual: (json['estadoActual'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
      ciudad: json['ciudad']?.toString(),
      etiqueta: json['etiqueta']?.toString(),
      nextAction: json['nextAction']?.toString(),
      nextActionAt: DateTime.tryParse((json['nextActionAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      responsable: (json['responsableUser'] is Map<String, dynamic>)
          ? CrmComercialUserRef.fromJson(
              json['responsableUser'] as Map<String, dynamic>,
            )
          : null,
      statusHistory: ((json['statusHistory'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialStatusEntry.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      notes: ((json['notes'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialNote.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      activities: ((json['activities'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialActivity.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class CrmComercialCustomerListResponse {
  const CrmComercialCustomerListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<CrmComercialCustomer> items;
  final int total;
  final int page;
  final int pageSize;

  factory CrmComercialCustomerListResponse.fromJson(Map<String, dynamic> json) {
    return CrmComercialCustomerListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialCustomer.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
    );
  }
}

class CrmComercialWhatsappInstance {
  const CrmComercialWhatsappInstance({
    required this.id,
    required this.instanceName,
    required this.status,
    required this.webhookEnabled,
    required this.isCompany,
    this.userId,
    this.userName,
    this.userRole,
    this.phoneNumber,
  });

  final String id;
  final String instanceName;
  final String status;
  final bool webhookEnabled;
  final bool isCompany;
  final String? userId;
  final String? userName;
  final String? userRole;
  final String? phoneNumber;

  factory CrmComercialWhatsappInstance.fromJson(Map<String, dynamic> json) {
    return CrmComercialWhatsappInstance(
      id: (json['id'] ?? '').toString(),
      instanceName: (json['instanceName'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      webhookEnabled: json['webhookEnabled'] == true,
      isCompany: json['isCompany'] == true,
      userId: json['userId']?.toString(),
      userName: json['userName']?.toString(),
      userRole: json['userRole']?.toString(),
      phoneNumber: json['phoneNumber']?.toString(),
    );
  }
}

class CrmComercialSettings {
  const CrmComercialSettings({
    required this.id,
    required this.enabled,
    this.selectedWhatsappInstanceId,
    this.selectedWhatsappInstanceName,
    this.updatedAt,
    this.selectedInstanceExists,
    this.warning,
    this.realMessagesReady,
  });

  final String id;
  final bool enabled;
  final String? selectedWhatsappInstanceId;
  final String? selectedWhatsappInstanceName;
  final DateTime? updatedAt;
  final bool? selectedInstanceExists;
  final String? warning;
  final bool? realMessagesReady;

  factory CrmComercialSettings.fromJson(Map<String, dynamic> json) {
    return CrmComercialSettings(
      id: (json['id'] ?? 'global').toString(),
      enabled: json['enabled'] == true,
      selectedWhatsappInstanceId:
          json['selectedWhatsappInstanceId']?.toString(),
      selectedWhatsappInstanceName:
          json['selectedWhatsappInstanceName']?.toString(),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
      selectedInstanceExists: json['selectedInstanceExists'] is bool
          ? json['selectedInstanceExists'] as bool
          : null,
      warning: json['warning']?.toString(),
      realMessagesReady: json['realMessagesReady'] is bool
          ? json['realMessagesReady'] as bool
          : null,
    );
  }
}

class CrmComercialInboxConversation {
  const CrmComercialInboxConversation({
    required this.id,
    required this.contactName,
    this.remotePhone,
    this.remoteJid,
    this.remoteAvatarUrl,
    this.lastMessageAt,
    this.lastMessagePreview,
    this.lastMessageType,
    this.lastMessageDirection,
    this.unreadCount = 0,
    this.messageCount = 0,
    this.crmCustomerId,
    this.crmCustomerName,
    this.crmCustomerStatus,
    this.isNewContact = false,
    this.canConvertToCrm = false,
    this.botPaused = false,
    this.botStatus,
    this.botSkippedReason,
    this.isExcluded = false,
  });

  final String id;
  final String contactName;
  final String? remotePhone;
  final String? remoteJid;
  final String? remoteAvatarUrl;
  final DateTime? lastMessageAt;
  final String? lastMessagePreview;
  final String? lastMessageType;
  final String? lastMessageDirection;
  final int unreadCount;
  final int messageCount;
  final String? crmCustomerId;
  final String? crmCustomerName;
  final String? crmCustomerStatus;
  final bool isNewContact;
  final bool canConvertToCrm;
  final bool botPaused;
  final String\? botStatus;
  final String\? botSkippedReason;
  final bool isExcluded;

  bool get isOutgoingLastMessage =>
      (lastMessageDirection ?? '').toUpperCase() == 'OUTGOING';

  CrmComercialInboxConversation copyWith({
    String? id,
    String? contactName,
    String? remotePhone,
    String? remoteJid,
    String? remoteAvatarUrl,
    DateTime? lastMessageAt,
    String? lastMessagePreview,
    String? lastMessageType,
    String? lastMessageDirection,
    int? unreadCount,
    int? messageCount,
    String? crmCustomerId,
    String? crmCustomerName,
    String? crmCustomerStatus,
    bool? isNewContact,
    bool? canConvertToCrm,
    bool? botPaused,
    String? botStatus,
    String? botSkippedReason,
    bool? isExcluded,
  }) {
    return CrmComercialInboxConversation(
      id: id ?? this.id,
      contactName: contactName ?? this.contactName,
      remotePhone: remotePhone ?? this.remotePhone,
      remoteJid: remoteJid ?? this.remoteJid,
      remoteAvatarUrl: remoteAvatarUrl ?? this.remoteAvatarUrl,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageDirection: lastMessageDirection ?? this.lastMessageDirection,
      unreadCount: unreadCount ?? this.unreadCount,
      messageCount: messageCount ?? this.messageCount,
      crmCustomerId: crmCustomerId ?? this.crmCustomerId,
      crmCustomerName: crmCustomerName ?? this.crmCustomerName,
      crmCustomerStatus: crmCustomerStatus ?? this.crmCustomerStatus,
      isNewContact: isNewContact ?? this.isNewContact,
      canConvertToCrm: canConvertToCrm ?? this.canConvertToCrm,
      botPaused: botPaused ?? this.botPaused,
      botStatus: botStatus ?? this.botStatus,
      botSkippedReason: botSkippedReason ?? this.botSkippedReason,
      isExcluded: isExcluded ?? this.isExcluded,
    );
  }

  factory CrmComercialInboxConversation.fromJson(Map<String, dynamic> json) {
    return CrmComercialInboxConversation(
      id: (json['id'] ?? '').toString(),
      contactName: (json['contactName'] ?? 'Nuevo contacto').toString(),
      remotePhone: json['remotePhone']?.toString(),
      remoteJid: json['remoteJid']?.toString(),
      remoteAvatarUrl: json['remoteAvatarUrl']?.toString(),
      lastMessageAt: DateTime.tryParse((json['lastMessageAt'] ?? '').toString()),
      lastMessagePreview: json['lastMessagePreview']?.toString(),
      lastMessageType: json['lastMessageType']?.toString(),
      lastMessageDirection: json['lastMessageDirection']?.toString(),
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      crmCustomerId: json['crmCustomerId']?.toString(),
      crmCustomerName: json['crmCustomerName']?.toString(),
      crmCustomerStatus: json['crmCustomerStatus']?.toString(),
      isNewContact: json['isNewContact'] == true,
      canConvertToCrm: json['canConvertToCrm'] == true,
      botPaused: json['botPaused'] == true,
      botStatus: json['botStatus']?.toString(),
      botSkippedReason: json['botSkippedReason']?.toString(),
      isExcluded: json['isExcluded'] == true,
    );
  }
}

class CrmComercialInboxMessage {
  const CrmComercialInboxMessage({
    required this.id,
    required this.direction,
    required this.messageType,
    this.body,
    this.caption,
    this.mediaUrl,
    this.mediaMimeType,
    this.senderName,
    this.sentAt,
    this.mediaStorageKey,
    this.mediaStatus,
    this.originalFileName,
    this.mediaFileSize,
  });

  final String id;
  final String direction;
  final String messageType;
  final String? body;
  final String? caption;
  final String? mediaUrl;
  final String? mediaMimeType;
  final String? senderName;
  final DateTime? sentAt;
  final String? mediaStorageKey;
  final String? mediaStatus;
  final String? originalFileName;
  final int? mediaFileSize;

  bool get isOutgoing => direction.toUpperCase() == 'OUTGOING';
  bool get mediaFailed => (mediaStatus ?? '').toLowerCase() == 'failed';

  String get displayText {
    final main = (body ?? '').trim();
    if (main.isNotEmpty) return main;
    final alt = (caption ?? '').trim();
    if (alt.isNotEmpty) return alt;
    return '[${messageType.toLowerCase()}]';
  }

  factory CrmComercialInboxMessage.fromJson(Map<String, dynamic> json) {
    return CrmComercialInboxMessage(
      id: (json['id'] ?? '').toString(),
      direction: (json['direction'] ?? 'INCOMING').toString(),
      messageType: (json['messageType'] ?? 'TEXT').toString(),
      body: json['body']?.toString(),
      caption: json['caption']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      mediaMimeType: json['mediaMimeType']?.toString(),
      senderName: json['senderName']?.toString(),
      sentAt: DateTime.tryParse((json['sentAt'] ?? '').toString()),
      mediaStorageKey: json['mediaStorageKey']?.toString(),
      mediaStatus: json['mediaStatus']?.toString(),
      originalFileName: json['originalFileName']?.toString(),
      mediaFileSize: json['mediaFileSize'] is int ? json['mediaFileSize'] as int : null,
    );
  }
}

class CrmComercialInboxConversationListResponse {
  const CrmComercialInboxConversationListResponse({
    required this.items,
    this.warning,
  });

  final List<CrmComercialInboxConversation> items;
  final String? warning;

  factory CrmComercialInboxConversationListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return CrmComercialInboxConversationListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) =>
              CrmComercialInboxConversation.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
      warning: json['warning']?.toString(),
    );
  }
}

class CrmComercialInboxMessageListResponse {
  const CrmComercialInboxMessageListResponse({
    required this.items,
    this.conversation,
    this.warning,
  });

  final List<CrmComercialInboxMessage> items;
  final CrmComercialInboxConversation? conversation;
  final String? warning;

  factory CrmComercialInboxMessageListResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    final conversationJson = json['conversation'];
    return CrmComercialInboxMessageListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                CrmComercialInboxMessage.fromJson(entry.cast<String, dynamic>()),
          )
          .toList(growable: false),
      conversation: conversationJson is Map<String, dynamic>
          ? CrmComercialInboxConversation.fromJson(conversationJson)
          : null,
      warning: json['warning']?.toString(),
    );
  }
}

class CrmComercialAiReplySuggestion {
  const CrmComercialAiReplySuggestion({
    required this.intent,
    required this.suggestedReply,
    required this.nextAction,
    required this.missingData,
    required this.confidence,
    required this.dataUsed,
    this.aiConfigured,
    this.message,
  });

  final String intent;
  final String suggestedReply;
  final String nextAction;
  final List<String> missingData;
  final double confidence;
  final List<String> dataUsed;
  final bool? aiConfigured;
  final String? message;

  factory CrmComercialAiReplySuggestion.fromJson(Map<String, dynamic> json) {
    return CrmComercialAiReplySuggestion(
      intent: (json['intent'] ?? '').toString(),
      suggestedReply: (json['suggestedReply'] ?? '').toString(),
      nextAction: (json['nextAction'] ?? '').toString(),
      missingData: ((json['missingData'] as List<dynamic>?) ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(growable: false),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      dataUsed: ((json['dataUsed'] as List<dynamic>?) ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(growable: false),
      aiConfigured: json['aiConfigured'] is bool ? json['aiConfigured'] as bool : null,
      message: json['message']?.toString(),
    );
  }
}

class CrmComercialLibraryItem {
  const CrmComercialLibraryItem({
    required this.id,
    required this.companyId,
    required this.title,
    required this.type,
    required this.isActive,
    required this.sortOrder,
    required this.tags,
    required this.useCount,
    this.description,
    this.contentText,
    this.mediaUrl,
    this.fileName,
    this.mimeType,
    this.latitude,
    this.longitude,
    this.externalUrl,
    this.category,
    this.lastUsedAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String companyId;
  final String title;
  final String type;
  final bool isActive;
  final int sortOrder;
  final List<String> tags;
  final int useCount;
  final String? description;
  final String? contentText;
  final String? mediaUrl;
  final String? fileName;
  final String? mimeType;
  final double? latitude;
  final double? longitude;
  final String? externalUrl;
  final String? category;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isMedia => const {'IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT'}.contains(type.toUpperCase());
  bool get isTextual => !isMedia;

  factory CrmComercialLibraryItem.fromJson(Map<String, dynamic> json) {
    return CrmComercialLibraryItem(
      id: (json['id'] ?? '').toString(),
      companyId: (json['companyId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      type: (json['type'] ?? 'TEXT').toString(),
      isActive: json['isActive'] == true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      tags: ((json['tags'] as List<dynamic>?) ?? const [])
          .map((entry) => entry.toString())
          .where((entry) => entry.trim().isNotEmpty)
          .toList(growable: false),
      useCount: (json['useCount'] as num?)?.toInt() ?? 0,
      description: json['description']?.toString(),
      contentText: json['contentText']?.toString(),
      mediaUrl: json['mediaUrl']?.toString(),
      fileName: json['fileName']?.toString(),
      mimeType: json['mimeType']?.toString(),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      externalUrl: json['externalUrl']?.toString(),
      category: json['category']?.toString(),
      lastUsedAt: DateTime.tryParse((json['lastUsedAt'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
    );
  }
}

class CrmCommercialLibraryListResponse {
  const CrmCommercialLibraryListResponse({required this.items});

  final List<CrmComercialLibraryItem> items;

  factory CrmCommercialLibraryListResponse.fromJson(Map<String, dynamic> json) {
    return CrmCommercialLibraryListResponse(
      items: ((json['items'] as List<dynamic>?) ?? const [])
          .whereType<Map>()
          .map((entry) => CrmComercialLibraryItem.fromJson(entry.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class CrmComercialFollowupTask {
    const CrmComercialFollowupTask({
      required this.id,
      required this.customerId,
      required this.title,
      required this.status,
      required this.effectiveStatus,
      required this.priority,
      this.description,
      this.dueDate,
      this.completedAt,
      this.createdAt,
      this.assignedTo,
      this.createdBy,
      this.completedBy,
    });

    final String id;
    final String customerId;
    final String title;
    final String status;
    final String effectiveStatus;
    final String priority;
    final String? description;
    final DateTime? dueDate;
    final DateTime? completedAt;
    final DateTime? createdAt;
    final CrmComercialUserRef? assignedTo;
    final CrmComercialUserRef? createdBy;
    final CrmComercialUserRef? completedBy;

    bool get isPending => effectiveStatus == 'PENDIENTE';
    bool get isOverdue => effectiveStatus == 'VENCIDA';
    bool get isCompleted => status == 'COMPLETADA';
    bool get isCancelled => status == 'CANCELADA';
    bool get isActive => status == 'PENDIENTE';

    factory CrmComercialFollowupTask.fromJson(Map<String, dynamic> json) {
      return CrmComercialFollowupTask(
        id: (json['id'] ?? '').toString(),
        customerId: (json['customerId'] ?? '').toString(),
        title: (json['title'] ?? '').toString(),
        status: (json['status'] ?? 'PENDIENTE').toString(),
        effectiveStatus:
            (json['effectiveStatus'] ?? json['status'] ?? 'PENDIENTE').toString(),
        priority: (json['priority'] ?? 'NORMAL').toString(),
        description: json['description']?.toString(),
        dueDate: DateTime.tryParse((json['dueDate'] ?? '').toString()),
        completedAt: DateTime.tryParse((json['completedAt'] ?? '').toString()),
        createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
        assignedTo: (json['assignedUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['assignedUser'] as Map<String, dynamic>)
            : null,
        createdBy: (json['createdByUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['createdByUser'] as Map<String, dynamic>)
            : null,
        completedBy: (json['completedByUser'] is Map<String, dynamic>)
            ? CrmComercialUserRef.fromJson(
                json['completedByUser'] as Map<String, dynamic>)
            : null,
      );
    }
  }
