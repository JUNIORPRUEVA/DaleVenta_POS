import 'dart:convert';

class CotizacionItem {
  final String productId;
  final String nombre;
  final String? imageUrl;
  final double? originalUnitPrice;
  final double unitPrice;
  final double qty;
  final double? costUnit;
  final double? externalCostUnit;
  final double? subtotalCostSnapshot;
  final double? profitSnapshot;

  const CotizacionItem({
    required this.productId,
    required this.nombre,
    required this.imageUrl,
    this.originalUnitPrice,
    required this.unitPrice,
    required this.qty,
    this.costUnit,
    this.externalCostUnit,
    this.subtotalCostSnapshot,
    this.profitSnapshot,
  });

  bool get isExternal => !_isUuid(productId);

  double get effectiveOriginalUnitPrice => originalUnitPrice ?? unitPrice;

  bool get hasDiscount => unitPrice < effectiveOriginalUnitPrice;

  double get discountUnitAmount {
    final discount = effectiveOriginalUnitPrice - unitPrice;
    return discount > 0 ? discount : 0;
  }

  double get discountAmount => discountUnitAmount * qty;

  double get total => unitPrice * qty;

  double? get tracedCostUnit => costUnit ?? externalCostUnit;

  double get subtotalCost =>
      subtotalCostSnapshot ?? ((tracedCostUnit ?? 0) * qty);

  CotizacionItem copyWith({
    String? productId,
    String? nombre,
    String? imageUrl,
    double? originalUnitPrice,
    double? unitPrice,
    double? qty,
    double? costUnit,
    double? externalCostUnit,
    double? subtotalCostSnapshot,
    double? profitSnapshot,
  }) {
    return CotizacionItem(
      productId: productId ?? this.productId,
      nombre: nombre ?? this.nombre,
      imageUrl: imageUrl ?? this.imageUrl,
      originalUnitPrice: originalUnitPrice ?? this.originalUnitPrice,
      unitPrice: unitPrice ?? this.unitPrice,
      qty: qty ?? this.qty,
      costUnit: costUnit ?? this.costUnit,
      externalCostUnit: externalCostUnit ?? this.externalCostUnit,
      subtotalCostSnapshot: subtotalCostSnapshot ?? this.subtotalCostSnapshot,
      profitSnapshot: profitSnapshot ?? this.profitSnapshot,
    );
  }

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'nombre': nombre,
    'imageUrl': imageUrl,
    'originalUnitPrice': originalUnitPrice,
    'unitPrice': unitPrice,
    'qty': qty,
    'costUnit': costUnit,
    'externalCostUnit': externalCostUnit,
    'subtotalCostSnapshot': subtotalCostSnapshot,
    'profitSnapshot': profitSnapshot,
  };

  Map<String, dynamic> toCreateDto() => {
    if (_isUuid(productId)) 'productId': productId,
    'productName': nombre,
    if (imageUrl != null && imageUrl!.trim().isNotEmpty)
      'productImageSnapshot': imageUrl,
    if (originalUnitPrice != null)
      'originalUnitPriceSnapshot': originalUnitPrice,
    'qty': qty,
    'unitPrice': unitPrice,
    if ((costUnit ?? externalCostUnit) != null)
      'costUnitSnapshot': costUnit ?? externalCostUnit,
  };

  static bool _isUuid(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  factory CotizacionItem.fromMap(Map<String, dynamic> map) {
    return CotizacionItem(
      productId: (map['productId'] ?? '').toString(),
      nombre: (map['nombre'] ?? '').toString(),
      imageUrl: map['imageUrl']?.toString(),
      originalUnitPrice: (map['originalUnitPrice'] as num?)?.toDouble(),
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
      qty: (map['qty'] as num?)?.toDouble() ?? 0,
      costUnit: (map['costUnit'] as num?)?.toDouble(),
      externalCostUnit: (map['externalCostUnit'] as num?)?.toDouble(),
      subtotalCostSnapshot: (map['subtotalCostSnapshot'] as num?)?.toDouble(),
      profitSnapshot: (map['profitSnapshot'] as num?)?.toDouble(),
    );
  }

  static double _asDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed ?? fallback;
  }

  factory CotizacionItem.fromApi(Map<String, dynamic> map) {
    final rawCostSnapshot = map['costUnitSnapshot'];
    final parsedCostSnapshot = rawCostSnapshot == null
        ? null
        : _asDouble(rawCostSnapshot);
    final rawOriginalUnitPrice =
        map['originalUnitPriceSnapshot'] ?? map['originalUnitPrice'];
    final isExternalItem = !_isUuid((map['productId'] ?? '').toString());
    return CotizacionItem(
      productId: (map['productId'] ?? '').toString(),
      nombre:
          (map['productNameSnapshot'] ??
                  map['productName'] ??
                  map['nombre'] ??
                  '')
              .toString(),
      imageUrl:
          (map['productImageSnapshot'] ?? map['imageUrl'] ?? map['image_url'])
              ?.toString(),
      originalUnitPrice: rawOriginalUnitPrice == null
          ? null
          : _asDouble(rawOriginalUnitPrice),
      unitPrice: _asDouble(map['unitPrice']),
      qty: _asDouble(map['qty']),
      costUnit: parsedCostSnapshot,
      externalCostUnit: isExternalItem ? parsedCostSnapshot : null,
      subtotalCostSnapshot: map['subtotalCost'] == null
          ? null
          : _asDouble(map['subtotalCost']),
      profitSnapshot: map['profit'] == null ? null : _asDouble(map['profit']),
    );
  }
}

class CotizacionModel {
  final String id;
  final DateTime createdAt;
  final String? createdByUserId;
  final String? createdByUserName;
  final String? customerId;
  final String customerName;
  final String? customerPhone;
  final String note;
  final bool includeItbis;
  final double itbisRate;
  final double globalDiscountAmount;
  final double? totalCost;
  final double? totalProfit;
  final List<CotizacionItem> items;

  const CotizacionModel({
    required this.id,
    required this.createdAt,
    this.createdByUserId,
    this.createdByUserName,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.note,
    required this.includeItbis,
    required this.itbisRate,
    this.globalDiscountAmount = 0,
    this.totalCost,
    this.totalProfit,
    required this.items,
  });

  double get subtotal => items.fold(0, (sum, item) => sum + item.total);
  double get subtotalBeforeDiscount => items.fold(
    0,
    (sum, item) => sum + (item.effectiveOriginalUnitPrice * item.qty),
  );
  double get lineDiscountAmount =>
      items.fold(0, (sum, item) => sum + item.discountAmount);
  double get discountAmount => lineDiscountAmount + globalDiscountAmount;
  bool get hasDiscount => discountAmount > 0.0001;
  double get itbisAmount => includeItbis ? subtotal * itbisRate : 0;
  double get totalBeforeGeneralDiscount => subtotal + itbisAmount;
  double get total {
    final nextTotal = totalBeforeGeneralDiscount - globalDiscountAmount;
    return nextTotal > 0 ? nextTotal : 0;
  }

  CotizacionModel copyWith({
    String? id,
    DateTime? createdAt,
    String? createdByUserId,
    String? createdByUserName,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? note,
    bool? includeItbis,
    double? itbisRate,
    double? globalDiscountAmount,
    double? totalCost,
    double? totalProfit,
    List<CotizacionItem>? items,
  }) {
    return CotizacionModel(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByUserName: createdByUserName ?? this.createdByUserName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      note: note ?? this.note,
      includeItbis: includeItbis ?? this.includeItbis,
      itbisRate: itbisRate ?? this.itbisRate,
      globalDiscountAmount: globalDiscountAmount ?? this.globalDiscountAmount,
      totalCost: totalCost ?? this.totalCost,
      totalProfit: totalProfit ?? this.totalProfit,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'createdByUserId': createdByUserId,
    'createdByUserName': createdByUserName,
    'customerId': customerId,
    'customerName': customerName,
    'customerPhone': customerPhone,
    'note': note,
    'includeItbis': includeItbis,
    'itbisRate': itbisRate,
    'globalDiscountAmount': globalDiscountAmount,
    'totalCost': totalCost,
    'totalProfit': totalProfit,
    'items': items.map((item) => item.toMap()).toList(),
  };

  factory CotizacionModel.fromMap(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    return CotizacionModel(
      id: (map['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      createdByUserId: map['createdByUserId']?.toString(),
      createdByUserName: map['createdByUserName']?.toString(),
      customerId: map['customerId']?.toString(),
      customerName: (map['customerName'] ?? '').toString(),
      customerPhone: map['customerPhone']?.toString(),
      note: (map['note'] ?? '').toString(),
      includeItbis: map['includeItbis'] == true,
      itbisRate: (map['itbisRate'] as num?)?.toDouble() ?? 0.18,
      globalDiscountAmount:
          (map['globalDiscountAmount'] as num?)?.toDouble() ?? 0,
      totalCost: (map['totalCost'] as num?)?.toDouble(),
      totalProfit: (map['totalProfit'] as num?)?.toDouble(),
      items: rawItems
          .whereType<Map>()
          .map((row) => CotizacionItem.fromMap(row.cast<String, dynamic>()))
          .toList(),
    );
  }

  static double _asDouble(dynamic value, [double fallback = 0]) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString());
    return parsed ?? fallback;
  }

  factory CotizacionModel.fromApi(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    final createdBy = map['createdBy'];
    final user = map['user'];
    final createdByUserId =
        map['createdByUserId']?.toString() ??
        map['createdById']?.toString() ??
        map['userId']?.toString() ??
        (createdBy is Map ? createdBy['id']?.toString() : null) ??
        (user is Map ? user['id']?.toString() : null);
    final createdByUserName =
        map['createdByUserName']?.toString() ??
        (createdBy is Map
            ? (createdBy['nombreCompleto'] ?? createdBy['email'])?.toString()
            : null) ??
        (user is Map
            ? (user['nombreCompleto'] ?? user['email'])?.toString()
            : null);
    return CotizacionModel(
      id: (map['id'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      createdByUserId: createdByUserId,
      createdByUserName: createdByUserName,
      customerId: map['customerId']?.toString(),
      customerName: (map['customerName'] ?? '').toString(),
      customerPhone: map['customerPhone']?.toString(),
      note: (map['note'] ?? '').toString(),
      includeItbis: map['includeItbis'] == true,
      itbisRate: _asDouble(map['itbisRate'], 0.18),
      globalDiscountAmount: _asDouble(map['globalDiscountAmount']),
      totalCost: map['totalCost'] == null ? null : _asDouble(map['totalCost']),
      totalProfit: map['totalProfit'] == null
          ? null
          : _asDouble(map['totalProfit']),
      items: rawItems
          .whereType<Map>()
          .map((row) => CotizacionItem.fromApi(row.cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toCreateDto() => {
    if (customerId != null && customerId!.trim().isNotEmpty)
      'customerId': customerId,
    'customerName': customerName,
    'customerPhone': (customerPhone ?? '').trim(),
    if (note.trim().isNotEmpty) 'note': note.trim(),
    'includeItbis': includeItbis,
    'itbisRate': itbisRate,
    if (globalDiscountAmount > 0) 'globalDiscountAmount': globalDiscountAmount,
    'items': items.map((item) => item.toCreateDto()).toList(),
  };

  String toJsonString() => jsonEncode(toMap());

  factory CotizacionModel.fromJsonString(String source) {
    return CotizacionModel.fromMap(
      (jsonDecode(source) as Map).cast<String, dynamic>(),
    );
  }
}

class CotizacionEditorPayload {
  final CotizacionModel source;
  final bool duplicate;

  const CotizacionEditorPayload({
    required this.source,
    required this.duplicate,
  });
}
