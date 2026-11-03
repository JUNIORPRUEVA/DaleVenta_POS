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
    this.canProceed = false,
    this.diagnostics = const EcfCertificateDiagnostics.empty(),
  });

  final bool valid;

  /// Única señal que habilita a continuar en el asistente.
  ///
  /// `valid` dice que el archivo es correcto; `canProceed` añade que el titular
  /// está identificado con un dato del expediente. Un certificado correcto de
  /// titular desconocido no habilita el avance.
  final bool canProceed;
  final String? code;
  final String message;
  final EcfCertificateInfo? certificate;

  /// Estado por comprobación: `PASS`, `FAIL` o `NOT_EVALUATED`.
  final Map<String, String> checks;

  /// `MATCH_COMPANY`, `MATCH_REPRESENTATIVE`, `MISMATCH`,
  /// `NOT_VERIFIABLE` o `NOT_EVALUATED`.
  final String identity;
  final List<String> notes;

  /// Diagnóstico seguro: booleanos, enums y fechas. Nunca identificadores.
  final EcfCertificateDiagnostics diagnostics;

  /// El certificado se abrió bien pero falta el dato para identificar al titular.
  bool get identityNotVerifiable => identity == 'NOT_VERIFIABLE';

  /// Qué falta exactamente, en lenguaje del usuario. `null` si puede avanzar.
  String? get blockingReason {
    if (canProceed) return null;
    if (code == 'ECF_CERTIFICATE_IDENTITY_NOT_VERIFIABLE') {
      final missing = diagnostics.missingCanonicalFields;
      if (missing.contains('representative.identification')) {
        return 'Falta la cédula del representante legal en los datos de la '
            'empresa para comprobar que el certificado sea suyo.';
      }
      if (missing.contains('company.rnc')) {
        return 'Falta el RNC de la empresa en los datos fiscales.';
      }
      return 'Todavía no se puede comprobar que el certificado sea de tu '
          'empresa o de su representante legal.';
    }
    if (code == 'ECF_CERTIFICATE_IDENTITY_MISMATCH') {
      return 'El titular del certificado no coincide con el RNC de la empresa '
          'ni con la cédula de su representante legal.';
    }
    return message.isNotEmpty ? message : 'El certificado no es utilizable.';
  }

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
      // Compatibilidad: si el backend todavía no envía `canProceed`, se deduce
      // del estado de identidad en lugar de asumir que puede avanzar.
      canProceed:
          json['canProceed'] == true ||
          (json['canProceed'] == null &&
              json['valid'] == true &&
              (json['identity'] as String?) != 'NOT_VERIFIABLE'),
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
      diagnostics: EcfCertificateDiagnostics.fromJson(json['diagnostics']),
    );
  }
}

/// Diagnóstico SEGURO del resultado.
///
/// No contiene identificadores, nombres ni material del certificado: solo
/// booleanos, enums y fechas, suficientes para saber qué condición falló.
class EcfCertificateDiagnostics {
  const EcfCertificateDiagnostics({
    required this.matchedAs,
    required this.hasCompanyTaxId,
    required this.hasRepresentativeId,
    required this.missingCanonicalFields,
    required this.holderKind,
    required this.notAfter,
    required this.daysRemaining,
    required this.keyMatchesCertificate,
  });

  const EcfCertificateDiagnostics.empty()
    : matchedAs = null,
      hasCompanyTaxId = false,
      hasRepresentativeId = false,
      missingCanonicalFields = const <String>[],
      holderKind = 'UNKNOWN',
      notAfter = null,
      daysRemaining = null,
      keyMatchesCertificate = null;

  /// `COMPANY`, `REPRESENTATIVE` o `null`.
  final String? matchedAs;
  final bool hasCompanyTaxId;
  final bool hasRepresentativeId;
  final List<String> missingCanonicalFields;

  /// `PERSON`, `ORGANIZATION` o `UNKNOWN`.
  final String holderKind;
  final String? notAfter;
  final int? daysRemaining;
  final bool? keyMatchesCertificate;

  factory EcfCertificateDiagnostics.fromJson(Object? json) {
    if (json is! Map) return const EcfCertificateDiagnostics.empty();
    final map = json.cast<String, dynamic>();
    final canonical = map['canonical'];
    final certificate = map['certificate'];
    final validity = map['validity'];
    final privateKey = map['privateKey'];
    final missing = map['missingCanonicalFields'];
    final days = validity is Map ? validity['daysRemaining'] : null;
    final matches = privateKey is Map ? privateKey['matchesCertificate'] : null;
    return EcfCertificateDiagnostics(
      matchedAs: map['identityMatchedAs']?.toString(),
      hasCompanyTaxId:
          canonical is Map && canonical['hasCompanyTaxId'] == true,
      hasRepresentativeId:
          canonical is Map && canonical['hasRepresentativeId'] == true,
      missingCanonicalFields: missing is List
          ? missing.map((item) => item.toString()).toList(growable: false)
          : const <String>[],
      holderKind:
          (certificate is Map ? certificate['holderKind']?.toString() : null) ??
          'UNKNOWN',
      notAfter: validity is Map ? validity['notAfter']?.toString() : null,
      daysRemaining: days is num ? days.toInt() : null,
      keyMatchesCertificate: matches is bool ? matches : null,
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
