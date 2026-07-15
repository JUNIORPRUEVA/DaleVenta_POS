import '../../modules/service_orders/service_order_models.dart';

enum MediaGalleryAssetType { image, video }

enum MediaGalleryUploadedByRole { creator, technician }

enum MediaGalleryTypeFilter { all, image, video }

enum MediaGalleryInstallationFilter { all, completed, pending }

class MediaGalleryItem {
  const MediaGalleryItem({
    required this.id,
    required this.url,
    required this.type,
    required this.comment,
    required this.orderId,
    required this.createdAt,
    required this.uploadedByRole,
    required this.orderStatus,
    required this.isInstallationCompleted,
    this.forPublicidad = false,
  });

  final String id;
  final String url;
  final MediaGalleryAssetType type;
  final String comment;
  final String orderId;
  final DateTime createdAt;
  final MediaGalleryUploadedByRole uploadedByRole;
  final ServiceOrderStatus orderStatus;
  final bool isInstallationCompleted;
  final bool forPublicidad;

  bool get isImage => type == MediaGalleryAssetType.image;
  bool get isVideo => type == MediaGalleryAssetType.video;

  String get displayComment {
    final value = comment.trim();
    if (value.isNotEmpty) return value;
    return uploadedByRole == MediaGalleryUploadedByRole.creator
        ? 'Referencia del cliente'
        : 'Evidencia técnica';
  }

  String get installationLabel =>
      isInstallationCompleted ? 'Instalado' : 'Pendiente';

  String get orderStatusLabel {
    switch (orderStatus) {
      case ServiceOrderStatus.pendiente:
        return 'Pendiente';
      case ServiceOrderStatus.enProceso:
        return 'En proceso';
      case ServiceOrderStatus.enPausa:
        return 'En pausa';
      case ServiceOrderStatus.pospuesta:
        return 'Pospuesta';
      case ServiceOrderStatus.finalizado:
        return 'Finalizado';
      case ServiceOrderStatus.cancelado:
        return 'Cancelado';
    }
  }

  String get uploadedByLabel =>
      uploadedByRole == MediaGalleryUploadedByRole.creator
      ? 'Creador'
      : 'Técnico';

  String get searchableText {
    return [
      displayComment,
      uploadedByLabel,
      orderStatusLabel,
      installationLabel,
      orderId,
      isImage ? 'imagen' : 'video',
    ].join(' ').toLowerCase();
  }

  String get suggestedFileName {
    final cleanOrderId = orderId.replaceAll('-', '').trim().toUpperCase();
    final orderToken = cleanOrderId.isEmpty
        ? 'MEDIA'
        : (cleanOrderId.length > 8
              ? cleanOrderId.substring(0, 8)
              : cleanOrderId);
    final extension = _inferFileExtension(
      url,
      fallback: isVideo ? 'mp4' : 'jpg',
    );
    final prefix = isVideo ? 'video' : 'imagen';
    return 'fulltech_${prefix}_$orderToken.$extension';
  }

  factory MediaGalleryItem.fromJson(Map<String, dynamic> json) {
    return MediaGalleryItem(
      id: (json['id'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      type: (json['type'] ?? '').toString().trim().toLowerCase() == 'video'
          ? MediaGalleryAssetType.video
          : MediaGalleryAssetType.image,
      comment: (json['comment'] ?? '').toString(),
      orderId: (json['orderId'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      uploadedByRole:
          (json['uploadedByRole'] ?? '').toString().trim().toLowerCase() ==
              'technician'
          ? MediaGalleryUploadedByRole.technician
          : MediaGalleryUploadedByRole.creator,
      orderStatus: serviceOrderStatusFromApi(
        (json['orderStatus'] ?? '').toString(),
      ),
      isInstallationCompleted: json['isInstallationCompleted'] == true,
      forPublicidad: json['forPublicidad'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'url': url,
      'type': isVideo ? 'video' : 'image',
      'comment': comment,
      'orderId': orderId,
      'createdAt': createdAt.toIso8601String(),
      'uploadedByRole': uploadedByRole == MediaGalleryUploadedByRole.creator
          ? 'creator'
          : 'technician',
      'orderStatus': orderStatus.apiValue,
      'isInstallationCompleted': isInstallationCompleted,
      'forPublicidad': forPublicidad,
    };
  }
}

class MediaGalleryPage {
  const MediaGalleryPage({
    required this.items,
    required this.nextCursor,
    required this.limit,
  });

  final List<MediaGalleryItem> items;
  final String? nextCursor;
  final int limit;

  factory MediaGalleryPage.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return MediaGalleryPage(
      items: rawItems
          .whereType<Map>()
          .map((row) => MediaGalleryItem.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false),
      nextCursor: (json['nextCursor'] ?? '').toString().trim().isEmpty
          ? null
          : (json['nextCursor'] ?? '').toString(),
      limit: (json['limit'] as num?)?.toInt() ?? 48,
    );
  }
}

String _inferFileExtension(String rawUrl, {required String fallback}) {
  final uri = Uri.tryParse(rawUrl.trim());
  final lastSegment = uri?.pathSegments.isNotEmpty == true
      ? uri!.pathSegments.last
      : rawUrl.trim().split('/').last;
  final dotIndex = lastSegment.lastIndexOf('.');
  if (dotIndex <= -1 || dotIndex >= lastSegment.length - 1) {
    return fallback;
  }
  final extension = lastSegment.substring(dotIndex + 1).toLowerCase();
  if (extension.isEmpty || extension.length > 5) {
    return fallback;
  }
  return extension;
}
