class ClienteProfileClient {
  final String id;
  final String nombre;
  final String telefono;
  final String phoneNormalized;
  final String? email;
  final String? direccion;
  final String? locationUrl;
  final double? latitude;
  final double? longitude;
  final String? notas;
  final String? ownerId;
  final DateTime? lastActivityAt;
  final bool isDeleted;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ClienteProfileClient({
    required this.id,
    required this.nombre,
    required this.telefono,
    required this.phoneNormalized,
    this.email,
    this.direccion,
    this.locationUrl,
    this.latitude,
    this.longitude,
    this.notas,
    this.ownerId,
    this.lastActivityAt,
    this.isDeleted = false,
    this.createdAt,
    this.updatedAt,
  });

  factory ClienteProfileClient.fromJson(Map<String, dynamic> json) {
    double? parseLatitude(dynamic value) {
      if (value == null) return null;
      final parsed = double.tryParse(value.toString());
      if (parsed == null || !parsed.isFinite) return null;
      return parsed >= -90 && parsed <= 90 ? parsed : null;
    }

    double? parseLongitude(dynamic value) {
      if (value == null) return null;
      final parsed = double.tryParse(value.toString());
      if (parsed == null || !parsed.isFinite) return null;
      return parsed >= -180 && parsed <= 180 ? parsed : null;
    }

    return ClienteProfileClient(
      id: (json['id'] ?? '').toString(),
      nombre: (json['nombre'] ?? '').toString(),
      telefono: (json['telefono'] ?? '').toString(),
      phoneNormalized: (json['phoneNormalized'] ?? '').toString(),
      email: (json['email'] as String?)?.trim().isEmpty == true
          ? null
          : json['email'] as String?,
      direccion: (json['direccion'] as String?)?.trim().isEmpty == true
          ? null
          : json['direccion'] as String?,
      locationUrl:
          ((json['locationUrl'] ?? json['location_url']) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (json['locationUrl'] ?? json['location_url']) as String?,
      latitude: parseLatitude(json['latitude']),
      longitude: parseLongitude(json['longitude']),
      notas: (json['notas'] as String?)?.trim().isEmpty == true
          ? null
          : json['notas'] as String?,
      ownerId: (json['ownerId'] as String?)?.trim().isEmpty == true
          ? null
          : json['ownerId'] as String?,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
      isDeleted: json['isDeleted'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'telefono': telefono,
      'phoneNormalized': phoneNormalized,
      'email': email,
      'direccion': direccion,
      'locationUrl': locationUrl,
      'latitude': latitude,
      'longitude': longitude,
      'notas': notas,
      'ownerId': ownerId,
      'lastActivityAt': lastActivityAt?.toIso8601String(),
      'isDeleted': isDeleted,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}

class ClienteProfileCreatedBy {
  final String id;
  final String? nombreCompleto;
  final String? email;
  final String? role;

  const ClienteProfileCreatedBy({
    required this.id,
    this.nombreCompleto,
    this.email,
    this.role,
  });

  String get displayName {
    final name = (nombreCompleto ?? '').trim();
    if (name.isNotEmpty) return name;
    final mail = (email ?? '').trim();
    if (mail.isNotEmpty) return mail;
    return id;
  }

  String get label {
    final r = (role ?? '').trim();
    return r.isEmpty ? displayName : '$displayName ($r)';
  }

  factory ClienteProfileCreatedBy.fromJson(Map<String, dynamic> json) {
    return ClienteProfileCreatedBy(
      id: (json['id'] ?? '').toString(),
      nombreCompleto:
          (json['nombreCompleto'] as String?)?.trim().isEmpty == true
          ? null
          : json['nombreCompleto'] as String?,
      email: (json['email'] as String?)?.trim().isEmpty == true
          ? null
          : json['email'] as String?,
      role: (json['role'] as String?)?.trim().isEmpty == true
          ? null
          : json['role'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombreCompleto': nombreCompleto,
      'email': email,
      'role': role,
    };
  }
}

class ClienteProfileMetrics {
  final int salesCount;
  final num? salesTotal;
  final DateTime? lastSaleAt;
  final int servicesCount;
  final int serviceOrdersCount;
  final int legacyServicesCount;
  final int serviceReferencesCount;
  final num? legacyServicesTotal;
  final DateTime? lastServiceAt;
  final DateTime? lastReferenceAt;
  final int cotizacionesCount;
  final num? cotizacionesTotal;
  final DateTime? lastCotizacionAt;
  final DateTime? lastActivityAt;

  const ClienteProfileMetrics({
    required this.salesCount,
    required this.salesTotal,
    required this.lastSaleAt,
    required this.servicesCount,
    required this.serviceOrdersCount,
    required this.legacyServicesCount,
    required this.serviceReferencesCount,
    required this.legacyServicesTotal,
    required this.lastServiceAt,
    required this.lastReferenceAt,
    required this.cotizacionesCount,
    required this.cotizacionesTotal,
    required this.lastCotizacionAt,
    required this.lastActivityAt,
  });

  static num? _parseNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value;
    return num.tryParse(value.toString());
  }

  factory ClienteProfileMetrics.fromJson(Map<String, dynamic> json) {
    return ClienteProfileMetrics(
      salesCount: (json['salesCount'] as num?)?.toInt() ?? 0,
      salesTotal: _parseNum(json['salesTotal']),
      lastSaleAt: json['lastSaleAt'] != null
          ? DateTime.tryParse(json['lastSaleAt'].toString())
          : null,
      servicesCount: (json['servicesCount'] as num?)?.toInt() ?? 0,
      serviceOrdersCount: (json['serviceOrdersCount'] as num?)?.toInt() ?? 0,
      legacyServicesCount: (json['legacyServicesCount'] as num?)?.toInt() ?? 0,
      serviceReferencesCount:
          (json['serviceReferencesCount'] as num?)?.toInt() ?? 0,
      legacyServicesTotal: _parseNum(json['legacyServicesTotal']),
      lastServiceAt: json['lastServiceAt'] != null
          ? DateTime.tryParse(json['lastServiceAt'].toString())
          : null,
      lastReferenceAt: json['lastReferenceAt'] != null
          ? DateTime.tryParse(json['lastReferenceAt'].toString())
          : null,
      cotizacionesCount: (json['cotizacionesCount'] as num?)?.toInt() ?? 0,
      cotizacionesTotal: _parseNum(json['cotizacionesTotal']),
      lastCotizacionAt: json['lastCotizacionAt'] != null
          ? DateTime.tryParse(json['lastCotizacionAt'].toString())
          : null,
      lastActivityAt: json['lastActivityAt'] != null
          ? DateTime.tryParse(json['lastActivityAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'salesCount': salesCount,
      'salesTotal': salesTotal,
      'lastSaleAt': lastSaleAt?.toIso8601String(),
      'servicesCount': servicesCount,
      'serviceOrdersCount': serviceOrdersCount,
      'legacyServicesCount': legacyServicesCount,
      'serviceReferencesCount': serviceReferencesCount,
      'legacyServicesTotal': legacyServicesTotal,
      'lastServiceAt': lastServiceAt?.toIso8601String(),
      'lastReferenceAt': lastReferenceAt?.toIso8601String(),
      'cotizacionesCount': cotizacionesCount,
      'cotizacionesTotal': cotizacionesTotal,
      'lastCotizacionAt': lastCotizacionAt?.toIso8601String(),
      'lastActivityAt': lastActivityAt?.toIso8601String(),
    };
  }
}

class ClienteProfileResponse {
  final ClienteProfileClient client;
  final ClienteProfileMetrics metrics;
  final ClienteProfileCreatedBy? createdBy;

  const ClienteProfileResponse({
    required this.client,
    required this.metrics,
    required this.createdBy,
  });

  factory ClienteProfileResponse.fromJson(Map<String, dynamic> json) {
    final clientRaw =
        (json['client'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final metricsRaw =
        (json['metrics'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final createdByRaw = (json['createdBy'] as Map?)?.cast<String, dynamic>();

    return ClienteProfileResponse(
      client: ClienteProfileClient.fromJson(clientRaw),
      metrics: ClienteProfileMetrics.fromJson(metricsRaw),
      createdBy: createdByRaw == null
          ? null
          : ClienteProfileCreatedBy.fromJson(createdByRaw),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'client': client.toJson(),
      'metrics': metrics.toJson(),
      'createdBy': createdBy?.toJson(),
    };
  }
}
