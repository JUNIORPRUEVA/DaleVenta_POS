enum DocumentFlowStatus {
  pendingPreparation,
  readyForReview,
  readyForFinalization,
  approved,
  rejected,
  sent,
}

DocumentFlowStatus parseDocumentFlowStatus(String raw) {
  switch (raw.trim()) {
    case 'pending_preparation':
      return DocumentFlowStatus.pendingPreparation;
    case 'ready_for_review':
      return DocumentFlowStatus.readyForReview;
    case 'ready_for_finalization':
      return DocumentFlowStatus.readyForFinalization;
    case 'approved':
      return DocumentFlowStatus.approved;
    case 'rejected':
      return DocumentFlowStatus.rejected;
    case 'sent':
      return DocumentFlowStatus.sent;
    default:
      return DocumentFlowStatus.pendingPreparation;
  }
}

String documentFlowStatusApiValue(DocumentFlowStatus status) {
  switch (status) {
    case DocumentFlowStatus.pendingPreparation:
      return 'pending_preparation';
    case DocumentFlowStatus.readyForReview:
      return 'ready_for_review';
    case DocumentFlowStatus.readyForFinalization:
      return 'ready_for_finalization';
    case DocumentFlowStatus.approved:
      return 'approved';
    case DocumentFlowStatus.rejected:
      return 'rejected';
    case DocumentFlowStatus.sent:
      return 'sent';
  }
}

extension DocumentFlowStatusX on DocumentFlowStatus {
  String get label {
    switch (this) {
      case DocumentFlowStatus.pendingPreparation:
        return 'Pendiente de preparación';
      case DocumentFlowStatus.readyForReview:
        return 'Listo para revisión';
      case DocumentFlowStatus.readyForFinalization:
        return 'Listo para finalización';
      case DocumentFlowStatus.approved:
        return 'Aprobado';
      case DocumentFlowStatus.rejected:
        return 'Rechazado';
      case DocumentFlowStatus.sent:
        return 'Enviado';
    }
  }
}

class DocumentFlowUserSummary {
  final String id;
  final String nombreCompleto;
  final String? email;

  const DocumentFlowUserSummary({
    required this.id,
    required this.nombreCompleto,
    this.email,
  });

  factory DocumentFlowUserSummary.fromJson(Map<String, dynamic> json) {
    return DocumentFlowUserSummary(
      id: (json['id'] ?? '').toString(),
      nombreCompleto: (json['nombreCompleto'] ?? '').toString(),
      email: json['email']?.toString(),
    );
  }
}

class DocumentFlowClientSummary {
  final String id;
  final String nombre;
  final String telefono;
  final String? direccion;

  const DocumentFlowClientSummary({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.direccion,
  });

  factory DocumentFlowClientSummary.fromJson(Map<String, dynamic> json) {
    return DocumentFlowClientSummary(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      direccion: json['direccion']?.toString(),
    );
  }
}

class DocumentFlowOrderSummary {
  final String id;
  final String? quotationId;
  final String status;
  final String serviceType;
  final String category;
  final DateTime? scheduledFor;
  final DateTime? finalizedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DocumentFlowClientSummary client;

  const DocumentFlowOrderSummary({
    required this.id,
    this.quotationId,
    required this.status,
    required this.serviceType,
    required this.category,
    required this.client,
    this.scheduledFor,
    this.finalizedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory DocumentFlowOrderSummary.fromJson(Map<String, dynamic> json) {
    return DocumentFlowOrderSummary(
      id: (json['id'] ?? '').toString(),
      quotationId: json['quotationId']?.toString(),
      status: (json['status'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      client: DocumentFlowClientSummary.fromJson(_asMap(json['client'])),
      scheduledFor: _asDateTime(json['scheduledFor']),
      finalizedAt: _asDateTime(json['finalizedAt']),
      createdAt: _asDateTime(json['createdAt']),
      updatedAt: _asDateTime(json['updatedAt']),
    );
  }
}

class DocumentFlowInvoiceItem {
  final String description;
  final double qty;
  final double unitPrice;
  final double lineTotal;

  const DocumentFlowInvoiceItem({
    required this.description,
    required this.qty,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory DocumentFlowInvoiceItem.fromJson(Map<String, dynamic> json) {
    final qty = _asDouble(json['qty']);
    final unitPrice = _asDouble(json['unitPrice']);
    return DocumentFlowInvoiceItem(
      description: (json['description'] ?? '').toString(),
      qty: qty,
      unitPrice: unitPrice,
      lineTotal: _asDouble(json['lineTotal'], fallback: qty * unitPrice),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'qty': qty,
      'unitPrice': unitPrice,
      'lineTotal': lineTotal,
    };
  }
}

class DocumentFlowInvoiceDraft {
  final String currency;
  final String clientName;
  final String clientPhone;
  final List<DocumentFlowInvoiceItem> items;
  final double subtotal;
  final double tax;
  final double total;
  final String notes;

  const DocumentFlowInvoiceDraft({
    required this.currency,
    required this.clientName,
    required this.clientPhone,
    required this.items,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.notes,
  });

  factory DocumentFlowInvoiceDraft.fromJson(Map<String, dynamic> json) {
    final items = _asList(json['items'])
        .map((item) => DocumentFlowInvoiceItem.fromJson(_asMap(item)))
        .where((item) => item.description.trim().isNotEmpty)
        .toList(growable: false);
    return DocumentFlowInvoiceDraft(
      currency: (json['currency'] ?? 'DOP').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      clientPhone: (json['clientPhone'] ?? '').toString(),
      items: items,
      subtotal: _asDouble(json['subtotal']),
      tax: _asDouble(json['tax']),
      total: _asDouble(json['total']),
      notes: (json['notes'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currency': currency,
      'clientName': clientName,
      'clientPhone': clientPhone,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'notes': notes,
    };
  }
}

class DocumentFlowWarrantyDraft {
  final String title;
  final String summary;
  final String serviceType;
  final String category;
  final String clientName;
  final List<String> terms;

  const DocumentFlowWarrantyDraft({
    required this.title,
    required this.summary,
    required this.serviceType,
    required this.category,
    required this.clientName,
    required this.terms,
  });

  factory DocumentFlowWarrantyDraft.fromJson(Map<String, dynamic> json) {
    return DocumentFlowWarrantyDraft(
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      terms: _asList(json['terms'])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'summary': summary,
      'serviceType': serviceType,
      'category': category,
      'clientName': clientName,
      'terms': terms,
    };
  }
}

class OrderDocumentFlowModel {
  final String id;
  final String orderId;
  final DocumentFlowStatus status;
  final DocumentFlowInvoiceDraft invoiceDraft;
  final DocumentFlowWarrantyDraft warrantyDraft;
  final String? invoiceFinalUrl;
  final String? warrantyFinalUrl;
  final String? preparedById;
  final String? approvedById;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DocumentFlowUserSummary? preparedBy;
  final DocumentFlowUserSummary? approvedBy;
  final DocumentFlowOrderSummary order;

  const OrderDocumentFlowModel({
    required this.id,
    required this.orderId,
    required this.status,
    required this.invoiceDraft,
    required this.warrantyDraft,
    required this.order,
    this.invoiceFinalUrl,
    this.warrantyFinalUrl,
    this.preparedById,
    this.approvedById,
    this.sentAt,
    this.createdAt,
    this.updatedAt,
    this.preparedBy,
    this.approvedBy,
  });

  factory OrderDocumentFlowModel.fromJson(Map<String, dynamic> json) {
    return OrderDocumentFlowModel(
      id: (json['id'] ?? '').toString(),
      orderId: (json['orderId'] ?? '').toString(),
      status: parseDocumentFlowStatus((json['status'] ?? '').toString()),
      invoiceDraft: DocumentFlowInvoiceDraft.fromJson(
        _asMap(json['invoiceDraftJson']),
      ),
      warrantyDraft: DocumentFlowWarrantyDraft.fromJson(
        _asMap(json['warrantyDraftJson']),
      ),
      invoiceFinalUrl: json['invoiceFinalUrl']?.toString(),
      warrantyFinalUrl: json['warrantyFinalUrl']?.toString(),
      preparedById: json['preparedById']?.toString(),
      approvedById: json['approvedById']?.toString(),
      sentAt: _asDateTime(json['sentAt']),
      createdAt: _asDateTime(json['createdAt']),
      updatedAt: _asDateTime(json['updatedAt']),
      preparedBy: json['preparedBy'] is Map
          ? DocumentFlowUserSummary.fromJson(_asMap(json['preparedBy']))
          : null,
      approvedBy: json['approvedBy'] is Map
          ? DocumentFlowUserSummary.fromJson(_asMap(json['approvedBy']))
          : null,
      order: DocumentFlowOrderSummary.fromJson(_asMap(json['order'])),
    );
  }
}

class DocumentFlowSendResult {
  final OrderDocumentFlowModel flow;
  final String toNumber;
  final String messageText;
  final List<String> attachments;

  const DocumentFlowSendResult({
    required this.flow,
    required this.toNumber,
    required this.messageText,
    required this.attachments,
  });

  factory DocumentFlowSendResult.fromJson(Map<String, dynamic> json) {
    final payload = _asMap(json['whatsappPayload']);
    return DocumentFlowSendResult(
      flow: OrderDocumentFlowModel.fromJson(_asMap(json['flow'])),
      toNumber: (payload['toNumber'] ?? '').toString(),
      messageText: (payload['messageText'] ?? '').toString(),
      attachments: _asList(payload['attachments'])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, entry) => MapEntry('$key', entry));
  }
  return <String, dynamic>{};
}

List<dynamic> _asList(dynamic value) {
  if (value is List) return value;
  return const [];
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

double _asDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}
