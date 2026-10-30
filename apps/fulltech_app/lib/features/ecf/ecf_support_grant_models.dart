/// Modelos de la ASISTENCIA TEMPORAL que una empresa concede a Fulltech.
///
/// Reflejan exactamente lo que devuelve `GET /ecf/dgii/support-grants`. La
/// aplicación no calcula la vigencia por su cuenta: `active`, `revoked` y
/// `expired` llegan resueltos del backend, que es la única fuente de verdad.
library;

/// Alcances de la concesión. Los nombres coinciden con el enum del backend
/// (`EcfSupportScope`); enviar uno desconocido hace que el servidor lo ignore
/// en lugar de conceder algo que la pantalla no sabe describir.
class EcfSupportScopeOption {
  const EcfSupportScopeOption({
    required this.value,
    required this.label,
    required this.description,
  });

  final String value;
  final String label;
  final String description;

  /// Catálogo cerrado: la interfaz solo ofrece lo que el backend entiende.
  static const all = <EcfSupportScopeOption>[
    EcfSupportScopeOption(
      value: 'VIEW_DOSSIER',
      label: 'Ver el expediente',
      description:
          'Estado del proceso, requisitos y lista de evidencias. No permite '
          'modificar nada.',
    ),
    EcfSupportScopeOption(
      value: 'REVIEW_EVIDENCE',
      label: 'Revisar evidencias',
      description:
          'Abrir y revisar los documentos cargados y marcar su revisión '
          'interna.',
    ),
    EcfSupportScopeOption(
      value: 'REQUEST_CORRECTION',
      label: 'Solicitar correcciones',
      description:
          'Dejar observaciones y pedir cambios en el expediente. No aprueba '
          'ni autoriza nada ante la DGII.',
    ),
  ];

  static String labelFor(String value) {
    for (final option in all) {
      if (option.value == value) return option.label;
    }
    return value;
  }
}

/// Una concesión tal y como la devuelve el backend.
class EcfSupportGrant {
  const EcfSupportGrant({
    required this.id,
    required this.scopes,
    required this.createdAt,
    required this.expiresAt,
    this.reason,
    this.revokedAt,
    this.active = false,
    this.revoked = false,
    this.expired = false,
  });

  final String id;
  final List<String> scopes;
  final String? reason;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? revokedAt;
  final bool active;
  final bool revoked;
  final bool expired;

  factory EcfSupportGrant.fromJson(Map<String, dynamic> json) {
    return EcfSupportGrant(
      id: (json['id'] ?? '') as String,
      scopes: (json['scopes'] is List)
          ? (json['scopes'] as List)
                .whereType<String>()
                .toList(growable: false)
          : const <String>[],
      reason: json['reason'] as String?,
      createdAt: _parseDate(json['createdAt']),
      expiresAt: _parseDate(json['expiresAt']),
      revokedAt: _parseNullableDate(json['revokedAt']),
      active: json['active'] == true,
      revoked: json['revoked'] == true,
      expired: json['expired'] == true,
    );
  }

  /// Etiqueta legible del estado. Es deliberadamente explícita: nunca se
  /// muestra "activa" para algo que ya caducó o se revocó.
  String get statusLabel {
    if (revoked) return 'Revocada';
    if (expired) return 'Caducada';
    if (active) return 'Activa';
    return 'Inactiva';
  }

  List<String> get scopeLabels =>
      scopes.map(EcfSupportScopeOption.labelFor).toList(growable: false);
}

/// Lista de concesiones de la empresa autenticada.
class EcfSupportGrantList {
  const EcfSupportGrantList({required this.items});

  final List<EcfSupportGrant> items;

  factory EcfSupportGrantList.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    if (raw is! List) return const EcfSupportGrantList(items: []);
    return EcfSupportGrantList(
      items: raw
          .whereType<Map>()
          .map((row) => EcfSupportGrant.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  /// La concesión vigente, si existe. Puede haber como mucho una activa.
  EcfSupportGrant? get activeGrant {
    for (final grant in items) {
      if (grant.active) return grant;
    }
    return null;
  }

  bool get hasActive => activeGrant != null;
}

DateTime _parseDate(dynamic value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

DateTime? _parseNullableDate(dynamic value) {
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}
