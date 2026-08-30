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
  final bool costAvailable;
  final double? stock;
  final String stockDecimal;
  final String unitOfMeasureId;
  final UnitOfMeasureModel unitOfMeasure;
  final String? fotoUrl;
  final String? originalFotoUrl;
  final String? imageKey;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? categoria;
  final bool activo;
  final String? imageVersion;
  final String taxTreatment;
  final double? taxRate;
  final String? taxPriceMode;

  ProductModel({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.codigo,
    required this.precio,
    required this.costo,
    this.costAvailable = true,
    this.stock,
    String? stockDecimal,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
    this.categoria,
    this.fotoUrl,
    this.originalFotoUrl,
    this.imageKey,
    this.createdAt,
    this.updatedAt,
    this.activo = true,
    this.imageVersion,
    this.taxTreatment = 'INHERIT',
    this.taxRate,
    this.taxPriceMode,
  }) : stockDecimal = stockDecimal ?? (stock?.toString() ?? '0'),
       unitOfMeasureId = unitOfMeasureId ?? UnitOfMeasureModel.unit.id,
       unitOfMeasure = unitOfMeasure ?? UnitOfMeasureModel.unit;

  ProductModel copyWith({
    String? id,
    String? nombre,
    String? descripcion,
    String? codigo,
    double? precio,
    double? costo,
    bool? costAvailable,
    double? stock,
    String? stockDecimal,
    String? unitOfMeasureId,
    UnitOfMeasureModel? unitOfMeasure,
    String? categoria,
    String? fotoUrl,
    String? originalFotoUrl,
    String? imageKey,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? activo,
    String? imageVersion,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
  }) {
    return ProductModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      descripcion: descripcion ?? this.descripcion,
      codigo: codigo ?? this.codigo,
      precio: precio ?? this.precio,
      costo: costo ?? this.costo,
      costAvailable: costAvailable ?? this.costAvailable,
      stock: stock ?? this.stock,
      stockDecimal: stockDecimal ?? this.stockDecimal,
      unitOfMeasureId: unitOfMeasureId ?? this.unitOfMeasureId,
      unitOfMeasure: unitOfMeasure ?? this.unitOfMeasure,
      categoria: categoria ?? this.categoria,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      originalFotoUrl: originalFotoUrl ?? this.originalFotoUrl,
      imageKey: imageKey ?? this.imageKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      activo: activo ?? this.activo,
      imageVersion: imageVersion ?? this.imageVersion,
      taxTreatment: taxTreatment ?? this.taxTreatment,
      taxRate: taxRate ?? this.taxRate,
      taxPriceMode: taxPriceMode ?? this.taxPriceMode,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    final rawStock =
        json['stockDecimal'] ??
        json['stock'] ??
        json['cantidadDisponible'] ??
        json['cantidad'];
    final parsedUnit = UnitOfMeasureModel.fromJson(json['unitOfMeasure']);
    final unitId =
        _asNullableString(
          json['unitOfMeasureId'] ?? json['unit_of_measure_id'],
        ) ??
        parsedUnit.id;
    final hasCost = json['costAvailable'] is bool
        ? json['costAvailable'] == true
        : json.containsKey('costo');
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
    final imageKey = _asNullableString(json['imageKey'] ?? json['image_key']);
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
      imageUrl: kIsWeb && imageKey != null ? imageKey : foto,
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
      costAvailable: hasCost,
      stock: _asNullableDouble(rawStock),
      stockDecimal: _asNullableString(json['stockDecimal']) ?? '$rawStock',
      unitOfMeasureId: unitId,
      unitOfMeasure: parsedUnit.copyWith(id: unitId),
      categoria: categoria,
      fotoUrl: normalizedFotoUrl.isEmpty ? null : normalizedFotoUrl,
      originalFotoUrl: foto,
      imageKey: imageKey,
      createdAt: createdAt,
      updatedAt: updatedAt,
      activo: activo,
      imageVersion: imageVersion,
      taxTreatment: _asNullableString(json['taxTreatment']) ?? 'INHERIT',
      taxRate: _asNullableDouble(json['taxRate']),
      taxPriceMode: _asNullableString(json['taxPriceMode']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'descripcion': descripcion,
      'codigo': codigo,
      'code': codigo,
      'sku': codigo,
      'barcode': codigo,
      'precio': precio,
      if (costAvailable) 'costo': costo,
      'costAvailable': costAvailable,
      'stock': stock,
      'stockDecimal': stockDecimal,
      'unitOfMeasureId': unitOfMeasureId,
      'unitOfMeasure': unitOfMeasure.toJson(),
      'categoria': categoria,
      'fotoUrl': fotoUrl,
      'originalFotoUrl': originalFotoUrl,
      'imageKey': imageKey,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'activo': activo,
      'imageVersion': imageVersion,
      'taxTreatment': taxTreatment,
      'taxRate': taxRate,
      'taxPriceMode': taxPriceMode,
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

class UnitOfMeasureModel {
  static const unit = UnitOfMeasureModel(
    id: 'UNIT',
    code: 'UNIT',
    name: 'Unidad',
    symbol: 'u',
    category: 'COUNT',
    allowDecimals: false,
    precision: 0,
  );

  final String id;
  final String code;
  final String name;
  final String symbol;
  final String category;
  final bool allowDecimals;
  final int precision;

  const UnitOfMeasureModel({
    required this.id,
    required this.code,
    required this.name,
    required this.symbol,
    required this.category,
    required this.allowDecimals,
    required this.precision,
  });

  bool get isUnit => code == 'UNIT';
  bool get isMeasured => !isUnit && allowDecimals;

  UnitOfMeasureModel copyWith({
    String? id,
    String? code,
    String? name,
    String? symbol,
    String? category,
    bool? allowDecimals,
    int? precision,
  }) {
    return UnitOfMeasureModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      symbol: symbol ?? this.symbol,
      category: category ?? this.category,
      allowDecimals: allowDecimals ?? this.allowDecimals,
      precision: precision ?? this.precision,
    );
  }

  factory UnitOfMeasureModel.fromJson(dynamic value) {
    if (value is! Map) return unit;
    final map = value.cast<String, dynamic>();
    final code = _asNullableString(map['code']) ?? unit.code;
    return UnitOfMeasureModel(
      id: _asNullableString(map['id']) ?? code,
      code: code,
      name: _asNullableString(map['name']) ?? unit.name,
      symbol: _asNullableString(map['symbol']) ?? unit.symbol,
      category: _asNullableString(map['category']) ?? unit.category,
      allowDecimals:
          map['allowDecimals'] == true || map['allow_decimals'] == true,
      precision: (map['precision'] as num?)?.toInt() ?? unit.precision,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'symbol': symbol,
    'category': category,
    'allowDecimals': allowDecimals,
    'precision': precision,
  };
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
