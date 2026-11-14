/// Safe history projection read from the server, independent of sale tax flags.
class EcfSaleFiscalDocument {
  const EcfSaleFiscalDocument({
    required this.documentId,
    required this.documentType,
    required this.status,
    this.encf,
    this.environment,
    this.conditional = false,
  });
  final String documentId, documentType, status;
  final String? encf, environment;
  final bool conditional;
  bool get canDispatch =>
      const {'LOCAL_VALIDATED', 'READY_TO_SEND'}.contains(status);
  factory EcfSaleFiscalDocument.fromJson(Map<String, dynamic> json) =>
      EcfSaleFiscalDocument(
        documentId: json['documentId'] as String,
        documentType: json['documentType'] as String,
        status: json['status'] as String,
        encf: json['encf'] as String?,
        environment: json['environment'] as String?,
        conditional: json['conditional'] == true,
      );
}

class EcfSaleFiscal {
  const EcfSaleFiscal({
    required this.saleId,
    this.intent,
    this.sequenceDueDate,
    this.requiresReview = false,
    this.documents = const [],
    this.creditNotes = const [],
    this.pendingRefundIds = const [],
  });
  final String saleId;
  final String? intent, sequenceDueDate;
  final bool requiresReview;
  final List<EcfSaleFiscalDocument> documents, creditNotes;
  final List<String> pendingRefundIds;
  bool get isElectronic => intent != null || documents.isNotEmpty;
  EcfSaleFiscalDocument? get original =>
      documents.length == 1 ? documents.single : null;
  factory EcfSaleFiscal.fromJson(Map<String, dynamic> json) {
    List<EcfSaleFiscalDocument> parse(String key) =>
        (json[key] as List? ?? const [])
            .whereType<Map>()
            .map(
              (e) => EcfSaleFiscalDocument.fromJson(e.cast<String, dynamic>()),
            )
            .toList(growable: false);
    return EcfSaleFiscal(
      saleId: json['saleId'] as String,
      intent: json['intent'] as String?,
      sequenceDueDate: json['sequenceDueDate'] as String?,
      requiresReview: json['requiresReview'] == true,
      documents: parse('documents'),
      creditNotes: parse('creditNotes'),
      pendingRefundIds: (json['pendingRefundIds'] as List? ?? const [])
          .cast<String>(),
    );
  }
}
