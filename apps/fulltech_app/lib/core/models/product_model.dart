import 'package:flutter/foundation.dart';

import '../api/env.dart';
import '../utils/product_image_url.dart';

String? _asNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  final normalized = value.toString().trim().replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}

double? _asNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final normalized = value.toString().trim().replaceAll(',', '.');
  return double.tryParse(normalized);
}

DateTime? _parseDateTimeCandidate(dynamic value) {
  final text = _asNullableString(value);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

DateTime? _firstParsedDate(Iterable<dynamic> values) {
  for (final value in values) {
    final parsed = _parseDateTimeCandidate(value);
    if (parsed != null) return parsed;
  }
  return null;
}

String? _versionFromDate(DateTime? value) {
  if (value == null) return null;
  return value.toUtc().millisecondsSinceEpoch.toString();
}

class ProductModel {
  final String id;
  final String nombre;
  final String? descripcion;
  final String? codigo;
  final double precio;
  final double costo;
  final double? stock;
  final String? fotoUrl;
  final String? originalFotoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? categoria;
  final bool activo;
  final String? imageVersion;

  ProductModel({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.codigo,
    required this.precio,
    required this.costo,
    this.stock,
    this.categoria,
    this.fotoUrl,
    this.originalFotoUrl,
    this.createdAt,
    this.updatedAt,
    this.activo = true,
    this.imageVersion,
  });

  ProductModel copyWith({
    String? id,
    String? nombre,
    String? descripcion,
    String? codigo,
    double? precio,
    double? costo,
    double? stock,
    String? categoria,
    String? fotoUrl,
    String? originalFotoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? activo,
    String? imageVersion,
  }) {
    return ProductModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      codigo: codigo ?? this.codigo,
      precio: precio ?? this.precio,
      costo: costo ?? this.costo,
      stock: stock ?? this.stock,
      categoria: categoria ?? this.categoria,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      originalFotoUrl: originalFotoUrl ?? this.originalFotoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      activo: activo ?? this.activo,
      imageVersion: imageVersion ?? this.imageVersion,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final rawStock =
        json['stock'] ?? json['cantidadDisponible'] ?? json['cantidad'];
    final categoria = _asNullableString(
      json['categoria'] ?? json['categoriaNombre'],
    );
    final descripcion = _asNullableString(
      json['descripcion'] ?? json['description'] ?? json['detalle'],
    );
    final codigo = _asNullableString(
      json['codigo'] ?? json['sku'] ?? json['barcode'] ?? json['code'],
    );
    final foto = _asNullableString(
      json['fotoUrl'] ??
          json['imagen'] ??
          json['imageUrl'] ??
          json['image_url'] ??
          json['originalFotoUrl'],
    );
    final createdAt = _firstParsedDate([json['createdAt'], json['created_at']]);
    final updatedAt = _firstParsedDate([
      json['updatedAt'],
      json['updated_at'],
      json['modifiedAt'],
      json['modified_at'],
      json['fechaActualizacion'],
      json['lastUpdate'],
    ]);
    final imageUpdatedAt = _firstParsedDate([
      json['imageUpdatedAt'],
      json['image_updated_at'],
    ]);
    final explicitImageVersion = _asNullableString(
      json['imageVersion'] ??
          json['catalogSyncVersion'] ??
          json['catalogRefreshVersion'] ??
          json['_catalogSyncVersion'],
    );
    final activoValue = json['activo'];
    final activo = activoValue is bool
        ? activoValue
        : (json['estado']?.toString().toLowerCase() != 'inactivo');
    final normalizedFotoUrl = normalizeProductImageUrl(
      imageUrl: foto,
      baseUrl: Env.apiBaseUrl,
      proxyUploadsOnWeb: kIsWeb,
    );
    final imageVersion =
        _versionFromDate(imageUpdatedAt ?? updatedAt) ?? explicitImageVersion;
    final finalImageUrl = buildProductImageUrl(
      imageUrl: normalizedFotoUrl,
      version: imageVersion,
    );
    final productId = _asNullableString(json['id']) ?? '';
    final productName = _asNullableString(json['nombre']) ?? '';

    debugLogProductImageResolution(
      productId: productId,
      productName: productName,
      originalUrl: foto,
      finalUrl: finalImageUrl,
    );

    return ProductModel(
      id: productId,
      nombre: productName,
      descripcion: descripcion,
      codigo: codigo,
      precio: _asDouble(json['precio']),
      costo: _asDouble(json['costo']),
      stock: _asNullableDouble(rawStock),
      categoria: categoria,
      fotoUrl: normalizedFotoUrl.isEmpty ? null : normalizedFotoUrl,
      originalFotoUrl: foto,
      createdAt: createdAt,
      updatedAt: updatedAt,
      activo: activo,
      imageVersion: imageVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'codigo': codigo,
      'precio': precio,
      'costo': costo,
      'stock': stock,
      'categoria': categoria,
      'fotoUrl': fotoUrl,
      'originalFotoUrl': originalFotoUrl,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'activo': activo,
      'imageVersion': imageVersion,
    };
  }

  String? get displayFotoUrl {
    final sourceImageUrl = fotoUrl ?? originalFotoUrl;
    final url = buildProductImageUrl(
      imageUrl: sourceImageUrl,
      version: imageVersion,
      baseUrl: Env.apiBaseUrl,
      proxyUploadsOnWeb: kIsWeb,
    );
    return url.isEmpty ? null : url;
  }

  String get categoriaLabel =>
      (categoria == null || categoria!.isEmpty) ? 'Sin categoría' : categoria!;
}

String buildCatalogSyncVersion(List<ProductModel> items) {
  DateTime? latest;
  for (final item in items) {
    final candidate = item.updatedAt;
    if (candidate == null) continue;
    if (latest == null || candidate.isAfter(latest)) {
      latest = candidate;
    }
  }
  return _versionFromDate(latest) ??
      DateTime.now().toUtc().millisecondsSinceEpoch.toString();
}

List<ProductModel> applyCatalogSyncVersion(
  List<ProductModel> items,
  String syncVersion,
) {
  return items
      .map(
        (item) => (item.imageVersion?.trim().isNotEmpty ?? false)
            ? item
            : item.copyWith(imageVersion: syncVersion),
      )
      .toList(growable: false);
}
