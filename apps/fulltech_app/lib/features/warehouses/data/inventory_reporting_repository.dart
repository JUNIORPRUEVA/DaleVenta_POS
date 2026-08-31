import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';

final inventoryReportingRepositoryProvider =
    Provider<InventoryReportingRepository>((ref) {
      return InventoryReportingRepository(ref.watch(dioProvider));
    });

final inventoryMovementsProvider =
    FutureProvider.family<InventoryMovementsPage, InventoryMovementFilters>((
      ref,
      filters,
    ) {
      return ref
          .watch(inventoryReportingRepositoryProvider)
          .fetchMovements(filters);
    });

final inventoryStockReportProvider = FutureProvider<InventoryStockReport>((
  ref,
) {
  return ref.watch(inventoryReportingRepositoryProvider).fetchStockReport();
});

final inventoryReconciliationProvider = FutureProvider<InventoryReconciliation>(
  (ref) {
    return ref
        .watch(inventoryReportingRepositoryProvider)
        .fetchReconciliation();
  },
);

String compactDecimal(String value) {
  final normalized = value.trim().replaceAll(',', '.');
  if (!normalized.contains('.')) return normalized.isEmpty ? '0' : normalized;
  return normalized
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

bool _asBool(dynamic value) => value == true || value?.toString() == 'true';

class InventoryMovementFilters {
  const InventoryMovementFilters({
    this.productId,
    this.warehouseId,
    this.type,
    this.sourceType,
    this.userId,
    this.search,
    this.from,
    this.to,
    this.take = 25,
    this.skip = 0,
  });

  final String? productId;
  final String? warehouseId;
  final String? type;
  final String? sourceType;
  final String? userId;
  final String? search;
  final DateTime? from;
  final DateTime? to;
  final int take;
  final int skip;

  InventoryMovementFilters copyWith({
    String? productId,
    String? warehouseId,
    String? type,
    String? sourceType,
    String? userId,
    String? search,
    DateTime? from,
    DateTime? to,
    int? take,
    int? skip,
    bool clearProduct = false,
    bool clearWarehouse = false,
    bool clearType = false,
  }) {
    return InventoryMovementFilters(
      productId: clearProduct ? null : (productId ?? this.productId),
      warehouseId: clearWarehouse ? null : (warehouseId ?? this.warehouseId),
      type: clearType ? null : (type ?? this.type),
      sourceType: sourceType ?? this.sourceType,
      userId: userId ?? this.userId,
      search: search ?? this.search,
      from: from ?? this.from,
      to: to ?? this.to,
      take: take ?? this.take,
      skip: skip ?? this.skip,
    );
  }

  Map<String, dynamic> toQuery() {
    return {
      'take': take,
      'skip': skip,
      if ((productId ?? '').trim().isNotEmpty) 'productId': productId!.trim(),
      if ((warehouseId ?? '').trim().isNotEmpty)
        'warehouseId': warehouseId!.trim(),
      if ((type ?? '').trim().isNotEmpty) 'type': type!.trim(),
      if ((sourceType ?? '').trim().isNotEmpty)
        'sourceType': sourceType!.trim(),
      if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
      if ((search ?? '').trim().isNotEmpty) 'search': search!.trim(),
      if (from != null) 'from': from!.toUtc().toIso8601String(),
      if (to != null) 'to': to!.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is InventoryMovementFilters &&
        other.productId == productId &&
        other.warehouseId == warehouseId &&
        other.type == type &&
        other.sourceType == sourceType &&
        other.userId == userId &&
        other.search == search &&
        other.from == from &&
        other.to == to &&
        other.take == take &&
        other.skip == skip;
  }

  @override
  int get hashCode => Object.hash(
    productId,
    warehouseId,
    type,
    sourceType,
    userId,
    search,
    from,
    to,
    take,
    skip,
  );
}

class InventoryMovementsPage {
  const InventoryMovementsPage({
    required this.source,
    required this.readOnly,
    required this.total,
    required this.take,
    required this.skip,
    required this.hasMore,
    required this.items,
    this.externalInventory = false,
    this.message,
  });

  final String source;
  final bool readOnly;
  final int total;
  final int take;
  final int skip;
  final bool hasMore;
  final bool externalInventory;
  final String? message;
  final List<InventoryMovementModel> items;

  factory InventoryMovementsPage.fromJson(Map<String, dynamic> json) {
    final rows = json['items'] is List ? json['items'] as List : const [];
    return InventoryMovementsPage(
      source: (json['source'] ?? 'LOCAL').toString(),
      readOnly: _asBool(json['readOnly']),
      total: _asInt(json['total']),
      take: _asInt(json['take']),
      skip: _asInt(json['skip']),
      hasMore: _asBool(json['hasMore']),
      externalInventory: _asBool(json['externalInventory']),
      message: json['message']?.toString(),
      items: rows
          .whereType<Map>()
          .map((row) => InventoryMovementModel.fromJson(row.cast()))
          .toList(growable: false),
    );
  }
}

class InventoryMovementModel {
  const InventoryMovementModel({
    required this.id,
    required this.createdAt,
    required this.type,
    required this.label,
    required this.direction,
    required this.productName,
    required this.productSku,
    required this.warehouseName,
    required this.warehouseCode,
    required this.warehouseActive,
    required this.quantityDeltaDecimal,
    required this.previousQuantityDecimal,
    required this.resultingQuantityDecimal,
    required this.unitSymbol,
    required this.referenceLabel,
    this.sourceWarehouseName,
    this.destinationWarehouseName,
    this.reason,
    this.createdByName,
  });

  final String id;
  final DateTime? createdAt;
  final String type;
  final String label;
  final String direction;
  final String productName;
  final String productSku;
  final String warehouseName;
  final String warehouseCode;
  final bool warehouseActive;
  final String quantityDeltaDecimal;
  final String previousQuantityDecimal;
  final String resultingQuantityDecimal;
  final String unitSymbol;
  final String referenceLabel;
  final String? sourceWarehouseName;
  final String? destinationWarehouseName;
  final String? reason;
  final String? createdByName;

  bool get isInbound => direction == 'IN';
  String get deltaText =>
      '${isInbound ? '+' : ''}${compactDecimal(quantityDeltaDecimal)} $unitSymbol';
  String get balanceText =>
      '${compactDecimal(previousQuantityDecimal)} -> ${compactDecimal(resultingQuantityDecimal)} $unitSymbol';
  bool get isTransfer => type == 'TRANSFER_OUT' || type == 'TRANSFER_IN';

  factory InventoryMovementModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'] is Map
        ? Map<String, dynamic>.from(json['product'] as Map)
        : const <String, dynamic>{};
    final warehouse = json['warehouse'] is Map
        ? Map<String, dynamic>.from(json['warehouse'] as Map)
        : const <String, dynamic>{};
    final sourceWarehouse = json['sourceWarehouse'] is Map
        ? Map<String, dynamic>.from(json['sourceWarehouse'] as Map)
        : const <String, dynamic>{};
    final destinationWarehouse = json['destinationWarehouse'] is Map
        ? Map<String, dynamic>.from(json['destinationWarehouse'] as Map)
        : const <String, dynamic>{};
    final unit = json['unit'] is Map
        ? Map<String, dynamic>.from(json['unit'] as Map)
        : const <String, dynamic>{};
    final reference = json['reference'] is Map
        ? Map<String, dynamic>.from(json['reference'] as Map)
        : const <String, dynamic>{};
    final createdBy = json['createdBy'] is Map
        ? Map<String, dynamic>.from(json['createdBy'] as Map)
        : const <String, dynamic>{};
    return InventoryMovementModel(
      id: (json['id'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
      type: (json['type'] ?? '').toString(),
      label: (json['label'] ?? json['type'] ?? '').toString(),
      direction: (json['direction'] ?? '').toString(),
      productName: (product['name'] ?? '').toString(),
      productSku: (product['sku'] ?? '').toString(),
      warehouseName: (warehouse['name'] ?? '').toString(),
      warehouseCode: (warehouse['code'] ?? '').toString(),
      warehouseActive: _asBool(warehouse['isActive']),
      quantityDeltaDecimal:
          (json['quantityDeltaDecimal'] ?? json['quantityDelta'] ?? '0')
              .toString(),
      previousQuantityDecimal:
          (json['previousQuantityDecimal'] ?? json['previousQuantity'] ?? '0')
              .toString(),
      resultingQuantityDecimal:
          (json['resultingQuantityDecimal'] ?? json['resultingQuantity'] ?? '0')
              .toString(),
      unitSymbol: (unit['symbol'] ?? 'u').toString(),
      referenceLabel: (reference['label'] ?? '').toString(),
      sourceWarehouseName: sourceWarehouse['name']?.toString(),
      destinationWarehouseName: destinationWarehouse['name']?.toString(),
      reason: json['reason']?.toString(),
      createdByName: createdBy['name']?.toString(),
    );
  }
}

class InventoryStockReport {
  const InventoryStockReport({
    required this.source,
    required this.readOnly,
    required this.warehouseCount,
    required this.productCount,
    required this.incompatibleUnitsSummed,
    required this.warehouses,
    required this.quantityBuckets,
    required this.rows,
    this.externalInventory = false,
    this.message,
  });

  final String source;
  final bool readOnly;
  final int warehouseCount;
  final int productCount;
  final bool incompatibleUnitsSummed;
  final bool externalInventory;
  final String? message;
  final List<InventoryReportWarehouse> warehouses;
  final List<InventoryQuantityBucket> quantityBuckets;
  final List<InventoryStockReportRow> rows;

  factory InventoryStockReport.fromJson(Map<String, dynamic> json) {
    final warehouses = json['warehouses'] is List
        ? json['warehouses'] as List
        : const [];
    final buckets = json['quantityBuckets'] is List
        ? json['quantityBuckets'] as List
        : const [];
    final rows = json['rows'] is List ? json['rows'] as List : const [];
    return InventoryStockReport(
      source: (json['source'] ?? 'LOCAL').toString(),
      readOnly: _asBool(json['readOnly']),
      warehouseCount: _asInt(json['warehouseCount']),
      productCount: _asInt(json['productCount']),
      incompatibleUnitsSummed: _asBool(json['incompatibleUnitsSummed']),
      externalInventory: _asBool(json['externalInventory']),
      message: json['message']?.toString(),
      warehouses: warehouses
          .whereType<Map>()
          .map((row) => InventoryReportWarehouse.fromJson(row.cast()))
          .toList(growable: false),
      quantityBuckets: buckets
          .whereType<Map>()
          .map((row) => InventoryQuantityBucket.fromJson(row.cast()))
          .toList(growable: false),
      rows: rows
          .whereType<Map>()
          .map((row) => InventoryStockReportRow.fromJson(row.cast()))
          .toList(growable: false),
    );
  }
}

class InventoryReportWarehouse {
  const InventoryReportWarehouse({
    required this.id,
    required this.name,
    required this.code,
    required this.isDefault,
    required this.isActive,
  });

  final String id;
  final String name;
  final String code;
  final bool isDefault;
  final bool isActive;

  factory InventoryReportWarehouse.fromJson(Map<String, dynamic> json) {
    return InventoryReportWarehouse(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      isDefault: _asBool(json['isDefault']),
      isActive: _asBool(json['isActive']),
    );
  }
}

class InventoryQuantityBucket {
  const InventoryQuantityBucket({
    required this.unitSymbol,
    required this.productCount,
  });

  final String unitSymbol;
  final int productCount;

  factory InventoryQuantityBucket.fromJson(Map<String, dynamic> json) {
    return InventoryQuantityBucket(
      unitSymbol: (json['unitSymbol'] ?? 'u').toString(),
      productCount: _asInt(json['productCount']),
    );
  }
}

class InventoryStockReportRow {
  const InventoryStockReportRow({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.unitSymbol,
    required this.companyTotalDecimal,
    required this.compatibilityStockDecimal,
    required this.reconciled,
    required this.warehouses,
  });

  final String productId;
  final String productName;
  final String sku;
  final String unitSymbol;
  final String companyTotalDecimal;
  final String compatibilityStockDecimal;
  final bool reconciled;
  final List<InventoryStockByWarehouse> warehouses;

  factory InventoryStockReportRow.fromJson(Map<String, dynamic> json) {
    final unit = json['unit'] is Map
        ? Map<String, dynamic>.from(json['unit'] as Map)
        : const <String, dynamic>{};
    final warehouses = json['warehouses'] is List
        ? json['warehouses'] as List
        : const [];
    return InventoryStockReportRow(
      productId: (json['productId'] ?? '').toString(),
      productName: (json['productName'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      unitSymbol: (unit['symbol'] ?? 'u').toString(),
      companyTotalDecimal: (json['companyTotalDecimal'] ?? '0').toString(),
      compatibilityStockDecimal: (json['compatibilityStockDecimal'] ?? '0')
          .toString(),
      reconciled: json['reconciled'] != false,
      warehouses: warehouses
          .whereType<Map>()
          .map((row) => InventoryStockByWarehouse.fromJson(row.cast()))
          .toList(growable: false),
    );
  }
}

class InventoryStockByWarehouse {
  const InventoryStockByWarehouse({
    required this.warehouseId,
    required this.warehouseName,
    required this.warehouseCode,
    required this.isActive,
    required this.quantityDecimal,
  });

  final String warehouseId;
  final String warehouseName;
  final String warehouseCode;
  final bool isActive;
  final String quantityDecimal;

  factory InventoryStockByWarehouse.fromJson(Map<String, dynamic> json) {
    return InventoryStockByWarehouse(
      warehouseId: (json['warehouseId'] ?? '').toString(),
      warehouseName: (json['warehouseName'] ?? '').toString(),
      warehouseCode: (json['warehouseCode'] ?? '').toString(),
      isActive: _asBool(json['isActive']),
      quantityDecimal: (json['quantityDecimal'] ?? '0').toString(),
    );
  }
}

class InventoryReconciliation {
  const InventoryReconciliation({
    required this.source,
    required this.readOnly,
    required this.totalProducts,
    required this.driftCount,
    required this.items,
    this.externalInventory = false,
    this.message,
  });

  final String source;
  final bool readOnly;
  final int totalProducts;
  final int driftCount;
  final bool externalInventory;
  final String? message;
  final List<InventoryReconciliationRow> items;

  factory InventoryReconciliation.fromJson(Map<String, dynamic> json) {
    final rows = json['items'] is List ? json['items'] as List : const [];
    return InventoryReconciliation(
      source: (json['source'] ?? 'LOCAL').toString(),
      readOnly: _asBool(json['readOnly']),
      totalProducts: _asInt(json['totalProducts']),
      driftCount: _asInt(json['driftCount']),
      externalInventory: _asBool(json['externalInventory']),
      message: json['message']?.toString(),
      items: rows
          .whereType<Map>()
          .map((row) => InventoryReconciliationRow.fromJson(row.cast()))
          .toList(growable: false),
    );
  }
}

class InventoryReconciliationRow {
  const InventoryReconciliationRow({
    required this.productName,
    required this.sku,
    required this.unitSymbol,
    required this.productStockDecimal,
    required this.warehouseTotalDecimal,
    required this.differenceDecimal,
    required this.reconciled,
  });

  final String productName;
  final String sku;
  final String unitSymbol;
  final String productStockDecimal;
  final String warehouseTotalDecimal;
  final String differenceDecimal;
  final bool reconciled;

  factory InventoryReconciliationRow.fromJson(Map<String, dynamic> json) {
    return InventoryReconciliationRow(
      productName: (json['productName'] ?? '').toString(),
      sku: (json['sku'] ?? '').toString(),
      unitSymbol: (json['unitSymbol'] ?? 'u').toString(),
      productStockDecimal: (json['productStockDecimal'] ?? '0').toString(),
      warehouseTotalDecimal: (json['warehouseTotalDecimal'] ?? '0').toString(),
      differenceDecimal: (json['differenceDecimal'] ?? '0').toString(),
      reconciled: json['reconciled'] != false,
    );
  }
}

class InventoryReportingRepository {
  const InventoryReportingRepository(this._dio);

  final Dio _dio;

  Future<InventoryMovementsPage> fetchMovements(
    InventoryMovementFilters filters,
  ) async {
    try {
      final res = await _dio.get(
        ApiRoutes.inventoryMovements,
        queryParameters: filters.toQuery(),
      );
      return InventoryMovementsPage.fromJson(
        Map<String, dynamic>.from((res.data as Map?) ?? const {}),
      );
    } on DioException catch (e) {
      throw ApiException(_message(e, 'No se pudo cargar el Kardex'));
    }
  }

  Future<InventoryStockReport> fetchStockReport() async {
    try {
      final res = await _dio.get(ApiRoutes.inventoryStockReport);
      return InventoryStockReport.fromJson(
        Map<String, dynamic>.from((res.data as Map?) ?? const {}),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e, 'No se pudo cargar el reporte de inventario'),
      );
    }
  }

  Future<InventoryReconciliation> fetchReconciliation() async {
    try {
      final res = await _dio.get(ApiRoutes.inventoryReconciliation);
      return InventoryReconciliation.fromJson(
        Map<String, dynamic>.from((res.data as Map?) ?? const {}),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e, 'No se pudo cargar la conciliacion de inventario'),
      );
    }
  }

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map && data['message'] != null) {
      final message = data['message'];
      if (message is List) return message.join('\n');
      return message.toString();
    }
    return fallback;
  }
}
