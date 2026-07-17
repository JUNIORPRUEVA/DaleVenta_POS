class WebsiteProductModel {
  const WebsiteProductModel({
    required this.id,
    required this.name,
    required this.baseName,
    required this.description,
    required this.baseDescription,
    required this.category,
    required this.baseCategory,
    required this.price,
    required this.stock,
    required this.image,
    required this.baseImage,
    required this.visible,
    required this.featured,
    required this.sortOrder,
    this.code,
    this.seoTitle,
    this.seoDescription,
    this.extraImages = const [],
  });

  final String id;
  final String name;
  final String baseName;
  final String description;
  final String baseDescription;
  final String category;
  final String baseCategory;
  final double price;
  final double? stock;
  final String? image;
  final String? baseImage;
  final bool visible;
  final bool featured;
  final int sortOrder;
  final String? code;
  final String? seoTitle;
  final String? seoDescription;
  final List<String> extraImages;

  factory WebsiteProductModel.fromJson(Map<String, dynamic> json) {
    double number(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse('${value ?? 0}'.replaceAll(',', '.')) ?? 0;
    }

    double? nullableNumber(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse('$value'.replaceAll(',', '.'));
    }

    String? nullableText(dynamic value) {
      final text = '${value ?? ''}'.trim();
      return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
    }

    return WebsiteProductModel(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      baseName: '${json['baseName'] ?? json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      baseDescription:
          '${json['baseDescription'] ?? json['description'] ?? ''}',
      category: '${json['category'] ?? 'Sin categoría'}',
      baseCategory:
          '${json['baseCategory'] ?? json['category'] ?? 'Sin categoría'}',
      price: number(json['price']),
      stock: nullableNumber(json['stock']),
      image: nullableText(json['image']),
      baseImage: nullableText(json['baseImage']),
      visible: json['visible'] != false,
      featured: json['featured'] == true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      code: nullableText(json['code']),
      seoTitle: nullableText(json['seoTitle']),
      seoDescription: nullableText(json['seoDescription']),
      extraImages:
          (json['extraImages'] as List?)
              ?.map((item) => '$item'.trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}
