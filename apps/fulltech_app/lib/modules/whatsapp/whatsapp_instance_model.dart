class WhatsappInstanceModel {
  final String id;
  final String userId;
  final String instanceName;
  final String status; // pending | connected
  final String? phoneNumber;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WhatsappInstanceModel({
    required this.id,
    required this.userId,
    required this.instanceName,
    required this.status,
    this.phoneNumber,
    this.createdAt,
    this.updatedAt,
  });

  bool get isConnected => status == 'connected';
  bool get isPending => status == 'pending';

  factory WhatsappInstanceModel.fromJson(Map<String, dynamic> json) {
    return WhatsappInstanceModel(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      instanceName: json['instanceName'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      phoneNumber: json['phoneNumber'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'instanceName': instanceName,
    'status': status,
    if (phoneNumber != null) 'phoneNumber': phoneNumber,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  WhatsappInstanceModel copyWith({
    String? id,
    String? userId,
    String? instanceName,
    String? status,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return WhatsappInstanceModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      instanceName: instanceName ?? this.instanceName,
      status: status ?? this.status,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class WhatsappInstanceStatusResponse {
  final bool exists;
  final String? status;
  final String? instanceName;
  final String? phoneNumber;
  final String? id;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const WhatsappInstanceStatusResponse({
    required this.exists,
    this.status,
    this.instanceName,
    this.phoneNumber,
    this.id,
    this.createdAt,
    this.updatedAt,
  });

  bool get isConnected => status == 'connected';

  factory WhatsappInstanceStatusResponse.fromJson(Map<String, dynamic> json) {
    return WhatsappInstanceStatusResponse(
      exists: json['exists'] as bool? ?? false,
      status: json['status'] as String?,
      instanceName: json['instanceName'] as String?,
      phoneNumber: json['phoneNumber'] as String?,
      id: json['id'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}

class WhatsappQrResponse {
  final String instanceName;
  final String qrBase64;
  final String status;

  const WhatsappQrResponse({
    required this.instanceName,
    required this.qrBase64,
    required this.status,
  });

  factory WhatsappQrResponse.fromJson(Map<String, dynamic> json) {
    return WhatsappQrResponse(
      instanceName: json['instanceName'] as String? ?? '',
      qrBase64: json['qrBase64'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
    );
  }
}

class WhatsappAdminUserEntry {
  final String id;
  final String nombreCompleto;
  final String email;
  final String role;
  final WhatsappInstanceStatusResponse? whatsapp;

  const WhatsappAdminUserEntry({
    required this.id,
    required this.nombreCompleto,
    required this.email,
    required this.role,
    this.whatsapp,
  });

  factory WhatsappAdminUserEntry.fromJson(Map<String, dynamic> json) {
    final wa = json['whatsapp'];
    return WhatsappAdminUserEntry(
      id: json['id'] as String? ?? '',
      nombreCompleto: json['nombreCompleto'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? '',
      whatsapp: wa != null
          ? WhatsappInstanceStatusResponse.fromJson(
              (wa as Map).cast<String, dynamic>()
                ..putIfAbsent('exists', () => true),
            )
          : null,
    );
  }
}
