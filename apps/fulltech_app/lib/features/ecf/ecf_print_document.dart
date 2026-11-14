/// Public fiscal print projection supplied by the backend, shared by all media.
class EcfPrintDocument {
  const EcfPrintDocument({
    required this.documentId,
    required this.documentType,
    required this.label,
    required this.encf,
    required this.environment,
    required this.state,
    required this.issueDate,
    required this.total,
    required this.issuerName,
    required this.issuerRnc,
    this.issuerAddress,
    this.buyerName,
    this.buyerRnc,
    this.expiresAt,
    this.originalEncf,
    this.originalIssueDate,
    this.modificationReason,
    this.modificationText,
    this.qrUrl,
    this.securityCode,
    this.signedAt,
    this.contingencyLegend,
    this.subtotal,
    this.currency = 'DOP',
    this.taxableBase,
    this.exemptAmount,
    this.itbisAmount,
    this.discountAmount,
    this.lines = const [],
  });

  final String documentId, documentType, label, encf, environment, state;
  final String issueDate, total, issuerName, issuerRnc;
  final String? issuerAddress, buyerName, buyerRnc, expiresAt, originalEncf;
  final String? originalIssueDate, modificationReason;
  final String? modificationText, qrUrl, securityCode, signedAt;
  final String? contingencyLegend;
  final String? subtotal;
  final String currency;
  final String? taxableBase, exemptAmount, itbisAmount, discountAmount;
  final List<EcfPrintLine> lines;
  bool get isTest => environment == 'SANDBOX';
  String get issueDateText => _date(issueDate);
  bool matchesTotal(double amount) {
    final value = double.tryParse(total);
    return value != null && value.isFinite && (value - amount).abs() < 0.005;
  }

  bool get hasStamp =>
      (state == 'SIGNED' || state == 'CONTINGENCY') &&
      qrUrl != null &&
      securityCode != null &&
      signedAt != null;
  String get notice => state == 'CONTINGENCY'
      ? '${isTest ? "PRUEBA TEST - SIN VALIDEZ FISCAL · " : ""}${contingencyLegend ?? "EMITIDO EN CONTINGENCIA - PENDIENTE DGII"}'
      : isTest
      ? 'PRUEBA TEST - SIN VALIDEZ FISCAL'
      : state == 'REJECTED'
      ? 'COMPROBANTE RECHAZADO - NO VALIDO PARA CREDITO FISCAL'
      : !hasStamp
      ? 'COMPROBANTE PENDIENTE DE EMISION - SIN VALIDEZ FISCAL'
      : '';
  List<String> get identityLines => [
    label,
    'e-NCF: $encf',
    'Fecha de emisión: $issueDateText',
    if (expiresAt != null) 'Vence: ${_date(expiresAt!)}',
    if (originalEncf != null) 'e-NCF modificado: $originalEncf',
    if (originalIssueDate != null)
      'Fecha comprobante modificado: ${_date(originalIssueDate!)}',
    if (modificationText != null) modificationText!,
    if (modificationReason != null) 'Motivo: $modificationReason',
    if (notice.isNotEmpty) notice,
  ];

  factory EcfPrintDocument.fromJson(Map<String, dynamic> json) =>
      EcfPrintDocument(
        documentId: json['documentId'] as String,
        contingencyLegend: json['contingencyLegend'] as String?,
        documentType: json['documentType'] as String,
        label: json['label'] as String,
        encf: json['encf'] as String? ?? '',
        environment: json['environment'] as String,
        state: json['state'] as String,
        issueDate: json['issueDate'] as String,
        total: json['total'].toString(),
        issuerName: json['issuerName'] as String,
        issuerRnc: json['issuerRnc'] as String,
        issuerAddress: json['issuerAddress'] as String?,
        buyerName: json['buyerName'] as String?,
        buyerRnc: json['buyerRnc'] as String?,
        expiresAt: json['expiresAt'] as String?,
        originalEncf: json['originalEncf'] as String?,
        originalIssueDate: json['originalIssueDate'] as String?,
        modificationReason: json['modificationReason'] as String?,
        modificationText: json['modificationText'] as String?,
        qrUrl: json['qrUrl'] as String?,
        securityCode: json['securityCode'] as String?,
        signedAt: json['signedAt'] as String?,
        subtotal: json['subtotal']?.toString(),
        currency: json['currency'] as String? ?? 'DOP',
        taxableBase: json['taxableBase']?.toString(),
        exemptAmount: json['exemptAmount']?.toString(),
        itbisAmount: json['itbisAmount']?.toString(),
        discountAmount: json['discountAmount']?.toString(),
        lines: (json['lines'] as List? ?? const [])
            .map(
              (line) =>
                  EcfPrintLine.fromJson(Map<String, dynamic>.from(line as Map)),
            )
            .toList(growable: false),
      );

  static String _date(String value) {
    final date = DateTime.tryParse(value);
    return date == null
        ? value
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class EcfPrintLine {
  const EcfPrintLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.taxableBase,
    required this.exemptAmount,
    required this.taxAmount,
    required this.discount,
    required this.taxExempt,
    this.unitOfMeasure,
  });
  final String name;
  final double quantity,
      unitPrice,
      total,
      taxableBase,
      exemptAmount,
      taxAmount,
      discount;
  final bool taxExempt;
  final String? unitOfMeasure;
  factory EcfPrintLine.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = double.parse(json[key].toString());
      if (!value.isFinite || value < 0) {
        throw FormatException('Importe fiscal inválido: $key');
      }
      return value;
    }

    return EcfPrintLine(
      name: json['name'] as String,
      quantity: number('quantity'),
      unitPrice: number('unitPrice'),
      total: number('total'),
      taxableBase: number('taxableBase'),
      exemptAmount: number('exemptAmount'),
      taxAmount: number('taxAmount'),
      discount: number('discount'),
      taxExempt: json['taxExempt'] == true,
      unitOfMeasure: json['unitOfMeasure'] as String?,
    );
  }
}
