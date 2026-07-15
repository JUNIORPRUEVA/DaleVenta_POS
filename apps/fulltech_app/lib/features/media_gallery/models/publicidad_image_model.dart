class PublicidadImage {
  final String id;
  final String url;
  final String? caption;
  final UserReference uploadedBy;
  final DateTime createdAt;

  PublicidadImage({
    required this.id,
    required this.url,
    this.caption,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory PublicidadImage.fromJson(Map<String, dynamic> json) {
    return PublicidadImage(
      id: json['id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      caption: json['caption'] as String?,
      uploadedBy: UserReference.fromJson(
        json['uploadedBy'] as Map<String, dynamic>? ?? {},
      ),
      createdAt: json['createdAt'] is String
          ? DateTime.parse(json['createdAt'] as String)
          : json['createdAt'] as DateTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'caption': caption,
      'uploadedBy': uploadedBy.toJson(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  PublicidadImage copyWith({
    String? id,
    String? url,
    String? caption,
    UserReference? uploadedBy,
    DateTime? createdAt,
  }) {
    return PublicidadImage(
      id: id ?? this.id,
      url: url ?? this.url,
      caption: caption ?? this.caption,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'PublicidadImage(id: $id, url: $url, caption: $caption, uploadedBy: $uploadedBy, createdAt: $createdAt)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicidadImage &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          url == other.url &&
          caption == other.caption &&
          uploadedBy == other.uploadedBy &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^
      url.hashCode ^
      caption.hashCode ^
      uploadedBy.hashCode ^
      createdAt.hashCode;
}

class UserReference {
  final String id;
  final String nombreCompleto;

  UserReference({required this.id, required this.nombreCompleto});

  factory UserReference.fromJson(Map<String, dynamic> json) {
    return UserReference(
      id: json['id'] as String? ?? '',
      nombreCompleto: json['nombreCompleto'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'nombreCompleto': nombreCompleto};
  }

  @override
  String toString() =>
      'UserReference(id: $id, nombreCompleto: $nombreCompleto)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserReference &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          nombreCompleto == other.nombreCompleto;

  @override
  int get hashCode => id.hashCode ^ nombreCompleto.hashCode;
}
