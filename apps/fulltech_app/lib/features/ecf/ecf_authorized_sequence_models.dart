/// Modelos de la numeración que la **DGII** autorizó a la empresa.
///
/// El dato no lo entrega ninguna API: lo transcribe el cliente desde la Oficina
/// Virtual y el backend guarda quién lo declaró, cuándo y con qué versión del
/// texto. La interfaz solo refleja lo que el servidor confirmó.
library;

class EcfAuthorizedSequence {
  const EcfAuthorizedSequence({
    required this.documentType,
    required this.authorizationNumber,
    required this.rangeFrom,
    required this.rangeTo,
    required this.approvedQuantity,
    required this.declarationVersion,
    this.expiresAt,
    this.declaredAt,
  });

  factory EcfAuthorizedSequence.fromJson(Map<String, dynamic> json) {
    return EcfAuthorizedSequence(
      documentType: '${json['documentType'] ?? ''}',
      authorizationNumber: '${json['authorizationNumber'] ?? ''}',
      rangeFrom: _asInt(json['rangeFrom']),
      rangeTo: _asInt(json['rangeTo']),
      approvedQuantity: _asInt(json['approvedQuantity']),
      declarationVersion: '${json['declarationVersion'] ?? ''}',
      expiresAt: _asDate(json['expiresAt']),
      declaredAt: _asDate(json['declaredAt']),
    );
  }

  final String documentType;
  final String authorizationNumber;
  final int rangeFrom;
  final int rangeTo;
  final int approvedQuantity;
  final String declarationVersion;
  final DateTime? expiresAt;
  final DateTime? declaredAt;

  /// Cantidad de comprobantes que cubre el rango declarado.
  int get declaredQuantity => rangeTo - rangeFrom + 1;
}

class EcfAuthorizedSequencesView {
  const EcfAuthorizedSequencesView({
    required this.items,
    required this.supportedTypes,
    required this.declarationVersion,
    required this.declarationText,
    this.environment = 'PRODUCTION',
  });

  factory EcfAuthorizedSequencesView.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final items = rawItems is List
        ? rawItems
              .whereType<Map>()
              .map(
                (row) =>
                    EcfAuthorizedSequence.fromJson(row.cast<String, dynamic>()),
              )
              .toList(growable: false)
        : const <EcfAuthorizedSequence>[];
    final rawTypes = json['supportedTypes'];
    return EcfAuthorizedSequencesView(
      environment: '${json['environment'] ?? 'PRODUCTION'}',
      items: items,
      supportedTypes: rawTypes is List
          ? rawTypes.map((value) => '$value').toList(growable: false)
          : const <String>[],
      declarationVersion: '${json['declarationVersion'] ?? ''}',
      declarationText: '${json['declarationText'] ?? ''}',
    );
  }

  static const empty = EcfAuthorizedSequencesView(
    items: <EcfAuthorizedSequence>[],
    supportedTypes: <String>[],
    declarationVersion: '',
    declarationText: '',
  );

  final List<EcfAuthorizedSequence> items;
  final String environment;
  final List<String> supportedTypes;
  final String declarationVersion;
  final String declarationText;

  EcfAuthorizedSequence? forType(String documentType) {
    for (final item in items) {
      if (item.documentType == documentType) return item;
    }
    return null;
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

DateTime? _asDate(dynamic value) {
  final text = '${value ?? ''}'.trim();
  if (text.isEmpty || text == 'null') return null;
  return DateTime.tryParse(text);
}
