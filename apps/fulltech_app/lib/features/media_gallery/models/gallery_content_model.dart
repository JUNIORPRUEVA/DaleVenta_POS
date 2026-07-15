// Gallery Content Models for Publicidad Hub
// Complete metadata for AI-driven content generation

enum ContentType { imagen, video }

enum ContentOrigin { producto, manual, galeria_global, ia }

enum ContentUsage { estados, campanas, marketplace, general }

class GalleryContentItem {
  const GalleryContentItem({
    required this.id,
    required this.type,
    required this.categoria,
    required this.descripcion,
    required this.tags,
    required this.fecha,
    required this.origen,
    required this.usadoEn,
    required this.publicado,
    required this.aprobado,
    required this.favorito,
    required this.url,
    required this.thumbnailUrl,
    this.referenciaProductoId,
    this.referenciaProductoNombre,
    this.metadataAI,
  });

  final String id;
  final ContentType type;
  final String categoria;
  final String descripcion;
  final List<String> tags;
  final DateTime fecha;
  final ContentOrigin origen;
  final List<ContentUsage> usadoEn;
  final bool publicado;
  final bool aprobado;
  final bool favorito;
  final String url;
  final String? thumbnailUrl;

  // Para referencias inteligentes de productos
  final String? referenciaProductoId;
  final String? referenciaProductoNombre;

  // Metadata enriched para IA
  final Map<String, dynamic>? metadataAI;

  bool get isImage => type == ContentType.imagen;
  bool get isVideo => type == ContentType.video;

  String get originLabel {
    switch (origen) {
      case ContentOrigin.producto:
        return 'Producto';
      case ContentOrigin.manual:
        return 'Manual';
      case ContentOrigin.galeria_global:
        return 'Galería Global';
      case ContentOrigin.ia:
        return 'IA';
    }
  }

  List<String> get usadoEnLabels => usadoEn.map((u) {
    switch (u) {
      case ContentUsage.estados:
        return 'Estados';
      case ContentUsage.campanas:
        return 'Campañas';
      case ContentUsage.marketplace:
        return 'Marketplace';
      case ContentUsage.general:
        return 'General';
    }
  }).toList();

  factory GalleryContentItem.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['tipo'] as String? ?? 'imagen').toLowerCase();
    final origenStr = (json['origen'] as String? ?? 'manual').toLowerCase();
    final usadoEnList = (json['usado_en'] is List)
        ? (json['usado_en'] as List)
              .map((e) => e.toString().toLowerCase())
              .toList()
        : <String>[];

    ContentType type = typeStr.contains('video')
        ? ContentType.video
        : ContentType.imagen;
    ContentOrigin origen = _parseOrigin(origenStr);
    List<ContentUsage> usadoEn = _parseUsages(usadoEnList);

    return GalleryContentItem(
      id: json['id'] as String? ?? '',
      type: type,
      categoria: json['categoria'] as String? ?? '',
      descripcion: json['descripcion'] as String? ?? '',
      tags: (json['tags'] is List)
          ? (json['tags'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList()
          : const [],
      fecha: json['fecha'] is String
          ? DateTime.tryParse(json['fecha'] as String) ?? DateTime.now()
          : json['fecha'] as DateTime? ?? DateTime.now(),
      origen: origen,
      usadoEn: usadoEn,
      publicado: json['publicado'] == true,
      aprobado: json['aprobado'] == true,
      favorito: json['favorito'] == true,
      url: json['url'] as String? ?? '',
      thumbnailUrl: (json['thumbnail_url'] as String? ?? '').isEmpty
          ? null
          : json['thumbnail_url'],
      referenciaProductoId: json['referencia_producto_id'] as String?,
      referenciaProductoNombre: json['referencia_producto_nombre'] as String?,
      metadataAI: json['metadata_ai'] is Map
          ? json['metadata_ai'] as Map<String, dynamic>
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tipo': type == ContentType.video ? 'video' : 'imagen',
      'categoria': categoria,
      'descripcion': descripcion,
      'tags': tags,
      'fecha': fecha.toIso8601String(),
      'origen': _originToString(origen),
      'usado_en': usadoEn.map((u) => _usageToString(u)).toList(),
      'publicado': publicado,
      'aprobado': aprobado,
      'favorito': favorito,
      'url': url,
      'thumbnail_url': thumbnailUrl,
      'referencia_producto_id': referenciaProductoId,
      'referencia_producto_nombre': referenciaProductoNombre,
      'metadata_ai': metadataAI,
    };
  }

  GalleryContentItem copyWith({
    String? id,
    ContentType? type,
    String? categoria,
    String? descripcion,
    List<String>? tags,
    DateTime? fecha,
    ContentOrigin? origen,
    List<ContentUsage>? usadoEn,
    bool? publicado,
    bool? aprobado,
    bool? favorito,
    String? url,
    String? thumbnailUrl,
    String? referenciaProductoId,
    String? referenciaProductoNombre,
    Map<String, dynamic>? metadataAI,
  }) {
    return GalleryContentItem(
      id: id ?? this.id,
      type: type ?? this.type,
      categoria: categoria ?? this.categoria,
      descripcion: descripcion ?? this.descripcion,
      tags: tags ?? this.tags,
      fecha: fecha ?? this.fecha,
      origen: origen ?? this.origen,
      usadoEn: usadoEn ?? this.usadoEn,
      publicado: publicado ?? this.publicado,
      aprobado: aprobado ?? this.aprobado,
      favorito: favorito ?? this.favorito,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      referenciaProductoId: referenciaProductoId ?? this.referenciaProductoId,
      referenciaProductoNombre:
          referenciaProductoNombre ?? this.referenciaProductoNombre,
      metadataAI: metadataAI ?? this.metadataAI,
    );
  }

  @override
  String toString() =>
      'GalleryContentItem(id: $id, type: $type, categoria: $categoria, origen: $origen)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GalleryContentItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

// Filter categories for sidebar
class GalleryFilter {
  const GalleryFilter({required this.id, required this.label, this.icon});

  final String id;
  final String label;
  final String? icon;

  static const List<GalleryFilter> allFilters = [
    GalleryFilter(id: 'todo', label: 'Todo', icon: '📋'),
    GalleryFilter(id: 'imagenes', label: 'Imágenes', icon: '🖼️'),
    GalleryFilter(id: 'videos', label: 'Videos', icon: '🎥'),
    GalleryFilter(id: 'productos', label: 'Productos', icon: '📦'),
    GalleryFilter(
      id: 'instalaciones',
      label: 'Instalaciones reales',
      icon: '🏗️',
    ),
    GalleryFilter(
      id: 'estados_publicados',
      label: 'Estados publicados',
      icon: '✅',
    ),
    GalleryFilter(
      id: 'campanas_publicadas',
      label: 'Campañas publicadas',
      icon: '📢',
    ),
    GalleryFilter(
      id: 'marketplace_publicado',
      label: 'Marketplace publicado',
      icon: '🛒',
    ),
    GalleryFilter(id: 'favoritos', label: 'Favoritos', icon: '⭐'),
    GalleryFilter(id: 'recientes', label: 'Recientes', icon: '⏱️'),
  ];

  static GalleryFilter? byId(String id) {
    try {
      return allFilters.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }
}

// Content import model
class ContentImportSource {
  const ContentImportSource({
    required this.id,
    required this.name,
    required this.descripcion,
    required this.icon,
  });

  final String id;
  final String name;
  final String descripcion;
  final String icon;

  static const List<ContentImportSource> sources = [
    ContentImportSource(
      id: 'productos',
      name: 'Agregar desde Productos',
      descripcion: 'Importa imágenes y videos del catálogo de productos',
      icon: '📦',
    ),
    ContentImportSource(
      id: 'manual',
      name: 'Subir Contenido',
      descripcion: 'Carga manualmente imágenes y videos',
      icon: '⬆️',
    ),
    ContentImportSource(
      id: 'galeria_global',
      name: 'Galería General de Contenido',
      descripcion: 'Importa de todas las imágenes/videos de la app',
      icon: '🌍',
    ),
  ];
}

// Helpers
ContentOrigin _parseOrigin(String str) {
  switch (str.toLowerCase()) {
    case 'producto':
      return ContentOrigin.producto;
    case 'galeria_global':
      return ContentOrigin.galeria_global;
    case 'ia':
      return ContentOrigin.ia;
    case 'manual':
    default:
      return ContentOrigin.manual;
  }
}

List<ContentUsage> _parseUsages(List<String> list) {
  return list.map((item) {
    switch (item.toLowerCase().trim()) {
      case 'estados':
        return ContentUsage.estados;
      case 'campanas':
        return ContentUsage.campanas;
      case 'marketplace':
        return ContentUsage.marketplace;
      case 'general':
      default:
        return ContentUsage.general;
    }
  }).toList();
}

String _originToString(ContentOrigin origin) {
  switch (origin) {
    case ContentOrigin.producto:
      return 'producto';
    case ContentOrigin.galeria_global:
      return 'galeria_global';
    case ContentOrigin.ia:
      return 'ia';
    case ContentOrigin.manual:
      return 'manual';
  }
}

String _usageToString(ContentUsage usage) {
  switch (usage) {
    case ContentUsage.estados:
      return 'estados';
    case ContentUsage.campanas:
      return 'campanas';
    case ContentUsage.marketplace:
      return 'marketplace';
    case ContentUsage.general:
      return 'general';
  }
}
