class ClienteModel {
  final String id;
  final String ownerId;
  final String nombre;
  final String telefono;
  final String? direccion;
  final String? locationUrl;
  final double? latitude;
  final double? longitude;
  final String? correo;
  final String? taxId;
  final String? businessName;
  final String? taxIdType;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;
  final String? syncStatus;
  final bool updatedLocal;

  const ClienteModel({
    required this.id,
    required this.ownerId,
    required this.nombre,
    required this.telefono,
    this.direccion,
    this.locationUrl,
    this.latitude,
    this.longitude,
    this.correo,
    this.taxId,
    this.businessName,
    this.taxIdType,
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
    this.syncStatus,
    this.updatedLocal = false,
  });

  factory ClienteModel.fromMap(Map<String, dynamic> map) {
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

    return ClienteModel(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? map['ownerId'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      telefono: (map['telefono'] ?? '').toString(),
      direccion: (map['direccion'] as String?)?.trim().isEmpty == true
          ? null
          : map['direccion'] as String?,
      locationUrl:
          ((map['locationUrl'] ?? map['location_url']) as String?)
                  ?.trim()
                  .isEmpty ==
              true
          ? null
          : (map['locationUrl'] ?? map['location_url']) as String?,
      latitude: parseLatitude(map['latitude']),
      longitude: parseLongitude(map['longitude']),
      correo:
          ((map['correo'] ?? map['email']) as String?)?.trim().isEmpty == true
          ? null
          : (map['correo'] ?? map['email']) as String?,
      taxId: _optionalString(map['taxId'] ?? map['tax_id']),
      businessName: _optionalString(
        map['businessName'] ?? map['business_name'],
      ),
      taxIdType: _optionalString(map['taxIdType'] ?? map['tax_id_type']),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : (map['createdAt'] != null
                ? DateTime.tryParse(map['createdAt'].toString())
                : null),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : (map['updatedAt'] != null
                ? DateTime.tryParse(map['updatedAt'].toString())
                : null),
      isDeleted: _toBool(map['is_deleted'] ?? map['isDeleted']),
      syncStatus: map['sync_status'] as String? ?? map['syncStatus'] as String?,
      updatedLocal: _toBool(map['updated_local'] ?? map['updatedLocal']),
    );
  }

  factory ClienteModel.fromJson(Map<String, dynamic> json) =>
      ClienteModel.fromMap(json);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'nombre': nombre,
      'telefono': telefono,
      'direccion': direccion,
      'location_url': locationUrl,
      'latitude': latitude,
      'longitude': longitude,
      'correo': correo,
      'taxId': taxId,
      'businessName': businessName,
      'taxIdType': taxIdType,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
      'sync_status': syncStatus,
      'updated_local': updatedLocal ? 1 : 0,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  Map<String, dynamic> toApiPayload() {
    return {
      'nombre': nombre.trim(),
      'telefono': telefono.trim(),
      'direccion': direccion?.trim().isEmpty == true ? null : direccion?.trim(),
      'location_url': locationUrl?.trim().isEmpty == true
          ? null
          : locationUrl?.trim(),
      'email': correo?.trim().isEmpty == true ? null : correo?.trim(),
      'taxId': taxId?.trim().isEmpty == true ? null : taxId?.trim(),
      'businessName': businessName?.trim().isEmpty == true
          ? null
          : businessName?.trim(),
      'taxIdType': taxIdType?.trim().isEmpty == true ? null : taxIdType?.trim(),
    };
  }

  ClienteModel copyWith({
    String? id,
    String? ownerId,
    String? nombre,
    String? telefono,
    String? direccion,
    String? locationUrl,
    double? latitude,
    double? longitude,
    String? correo,
    String? taxId,
    String? businessName,
    String? taxIdType,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
    String? syncStatus,
    bool? updatedLocal,
    bool clearDireccion = false,
    bool clearLocationUrl = false,
    bool clearCorreo = false,
    bool clearTaxId = false,
    bool clearBusinessName = false,
    bool clearTaxIdType = false,
    bool clearSyncStatus = false,
  }) {
    return ClienteModel(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      direccion: clearDireccion ? null : (direccion ?? this.direccion),
      locationUrl: clearLocationUrl ? null : (locationUrl ?? this.locationUrl),
      latitude: clearLocationUrl ? null : (latitude ?? this.latitude),
      longitude: clearLocationUrl ? null : (longitude ?? this.longitude),
      correo: clearCorreo ? null : (correo ?? this.correo),
      taxId: clearTaxId ? null : (taxId ?? this.taxId),
      businessName: clearBusinessName
          ? null
          : (businessName ?? this.businessName),
      taxIdType: clearTaxIdType ? null : (taxIdType ?? this.taxIdType),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      syncStatus: clearSyncStatus ? null : (syncStatus ?? this.syncStatus),
      updatedLocal: updatedLocal ?? this.updatedLocal,
    );
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      return normalized == '1' || normalized == 'true' || normalized == 'yes';
    }
    return false;
  }

  static String? _optionalString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
