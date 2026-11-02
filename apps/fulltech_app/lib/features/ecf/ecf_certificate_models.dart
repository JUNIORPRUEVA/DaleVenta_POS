/// Resultado de la validación CRIPTOGRÁFICA de un certificado PFX/P12.
///
/// Regla del módulo: este informe dice lo que se comprobó y, sobre todo, lo que
/// NO se comprobó. Nunca declara que la DGII haya aceptado el certificado.
class EcfCertificateReport {
  const EcfCertificateReport({
    required this.valid,
    required this.code,
    required this.message,
    required this.certificate,
    required this.checks,
    required this.identity,
    required this.notes,
  });

  final bool valid;
  final String? code;
  final String message;
  final EcfCertificateInfo? certificate;

  /// Estado por comprobación: `PASS`, `FAIL` o `NOT_EVALUATED`.
  final Map<String, String> checks;

  /// `MATCH`, `MISMATCH` o `NOT_EVALUATED`.
  final String identity;
  final List<String> notes;

  /// Comprobaciones que este producto todavía no puede concluir.
  ///
  /// Se listan a propósito en la interfaz: «no comprobado» no es «correcto».
  List<String> get pendingChecks => const <String>[
    'Cadena de confianza del certificado',
    'Revocación (lista del emisor)',
    // DGII CA5241: la firma también puede rechazarse por discrepancias con el
    // administrador e-CF del RNC. Ese rol no se consulta desde aquí.
    'Coincidencia con el administrador e-CF del RNC en la DGII',
    // DGII CA5388 / Norma 10-21 art. 14: la delegación la registra el proveedor.
    'Delegación de firma registrada ante la DGII',
  ];

  factory EcfCertificateReport.fromJson(Map<String, dynamic> json) {
    final certificate = json['certificate'];
    final checks = json['checks'];
    final notes = json['notes'];
    return EcfCertificateReport(
      valid: json['valid'] == true,
      code: json['code'] as String?,
      message: (json['message'] as String?) ?? '',
      certificate: certificate is Map
          ? EcfCertificateInfo.fromJson(certificate.cast<String, dynamic>())
          : null,
      checks: checks is Map
          ? checks.map(
              (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
            )
          : const <String, String>{},
      identity: (json['identity'] as String?) ?? 'NOT_EVALUATED',
      notes: notes is List
          ? notes.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
    );
  }
}

class EcfCertificateInfo {
  const EcfCertificateInfo({
    this.commonName,
    this.organization,
    this.serialNumber,
    this.issuer,
    this.notBefore,
    this.notAfter,
    this.daysRemaining,
    this.fingerprintShort,
  });

  final String? commonName;
  final String? organization;
  final String? serialNumber;
  final String? issuer;
  final String? notBefore;
  final String? notAfter;
  final int? daysRemaining;
  final String? fingerprintShort;

  factory EcfCertificateInfo.fromJson(Map<String, dynamic> json) {
    String? text(Object? value) {
      final raw = value?.toString().trim();
      return raw == null || raw.isEmpty ? null : raw;
    }

    final days = json['daysRemaining'];
    return EcfCertificateInfo(
      commonName: text(json['commonName']),
      organization: text(json['organization']),
      serialNumber: text(json['serialNumber']),
      issuer: text(json['issuer']),
      notBefore: text(json['notBefore']),
      notAfter: text(json['notAfter']),
      daysRemaining: days is num ? days.toInt() : null,
      fingerprintShort: text(json['fingerprintShort']),
    );
  }

  /// Fecha legible (AAAA-MM-DD) sin depender del formato ISO completo.
  String? get notAfterLabel => _dateLabel(notAfter);
  String? get notBeforeLabel => _dateLabel(notBefore);

  static String? _dateLabel(String? iso) {
    if (iso == null) return null;
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return null;
    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }
}
