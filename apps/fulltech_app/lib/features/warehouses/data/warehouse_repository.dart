import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';

final warehouseRepositoryProvider = Provider<WarehouseRepository>((ref) {
  return WarehouseRepository(ref.watch(dioProvider));
});

final warehousesProvider = FutureProvider<List<WarehouseModel>>((ref) {
  return ref.watch(warehouseRepositoryProvider).fetchWarehouses();
});

final warehouseTerminalsProvider = FutureProvider<List<TerminalWarehouseModel>>(
  (ref) {
    return ref.watch(warehouseRepositoryProvider).fetchTerminals();
  },
);

final productWarehouseStockProvider =
    FutureProvider.family<ProductWarehouseStockBreakdown, String>((
      ref,
      productId,
    ) {
      return ref
          .watch(warehouseRepositoryProvider)
          .fetchProductStockBreakdown(productId);
    });

final warehouseTransfersProvider = FutureProvider<List<WarehouseTransferModel>>(
  (ref) {
    return ref.watch(warehouseRepositoryProvider).fetchTransfers();
  },
);

final warehouseProductsProvider = FutureProvider<List<ProductModel>>((ref) {
  return ref.watch(warehouseRepositoryProvider).fetchProducts();
});

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse((value ?? '').toString()) ?? 0;
}

bool _asBool(dynamic value) => value == true || value?.toString() == 'true';

class WarehouseModel {
  const WarehouseModel({
    required this.id,
    required this.name,
    required this.code,
    required this.isDefault,
    required this.isActive,
    required this.terminalCount,
    required this.stockRowCount,
  });

  final String id;
  final String name;
  final String code;
  final bool isDefault;
  final bool isActive;
  final int terminalCount;
  final int stockRowCount;

  factory WarehouseModel.fromJson(Map<String, dynamic> json) {
    return WarehouseModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      isDefault: _asBool(json['isDefault']),
      isActive: _asBool(json['isActive']),
      terminalCount: _asInt(json['terminalCount']),
      stockRowCount: _asInt(json['stockRowCount']),
    );
  }
}

class TerminalWarehouseModel {
  const TerminalWarehouseModel({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
    required this.isDefault,
    required this.defaultWarehouseId,
    required this.defaultWarehouseName,
    required this.defaultWarehouseCode,
    required this.deviceBound,
  });

  final String id;
  final String name;
  final String code;
  final bool isActive;
  final bool isDefault;
  final String defaultWarehouseId;
  final String defaultWarehouseName;
  final String defaultWarehouseCode;
  final bool deviceBound;

  factory TerminalWarehouseModel.fromJson(Map<String, dynamic> json) {
    final warehouse = json['defaultWarehouse'] is Map
        ? Map<String, dynamic>.from(json['defaultWarehouse'] as Map)
        : const <String, dynamic>{};
    return TerminalWarehouseModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      code: (json['code'] ?? '').toString(),
      isActive: _asBool(json['isActive']),
      isDefault: _asBool(json['isDefault']),
      defaultWarehouseId: (json['defaultWarehouseId'] ?? '').toString(),
      defaultWarehouseName: (warehouse['name'] ?? '').toString(),
      defaultWarehouseCode: (warehouse['code'] ?? '').toString(),
      deviceBound: _asBool(json['deviceBound']),
    );
  }
}

class WarehouseStockLine {
  const WarehouseStockLine({
    required this.warehouseId,
    required this.warehouseName,
    required this.warehouseCode,
    required this.isDefault,
    required this.isActive,
    required this.quantity,
    required this.quantityDecimal,
  });

  final String warehouseId;
  final String warehouseName;
  final String warehouseCode;
  final bool isDefault;
  final bool isActive;
  final double quantity;
  final String quantityDecimal;

  factory WarehouseStockLine.fromJson(Map<String, dynamic> json) {
    return WarehouseStockLine(
      warehouseId: (json['warehouseId'] ?? '').toString(),
      warehouseName: (json['warehouseName'] ?? '').toString(),
      warehouseCode: (json['warehouseCode'] ?? '').toString(),
      isDefault: _asBool(json['isDefault']),
      isActive: _asBool(json['isActive']),
      quantity: _asDouble(json['quantity']),
      quantityDecimal: (json['quantityDecimal'] ?? json['quantity'] ?? '0')
          .toString(),
    );
  }
}

class ProductWarehouseStockBreakdown {
  const ProductWarehouseStockBreakdown({
    required this.productId,
    required this.source,
    required this.readOnly,
    required this.reconciled,
    required this.total,
    required this.warehouseTotal,
    required this.warehouses,
    this.message,
  });

  final String productId;
  final String source;
  final bool readOnly;
  final bool reconciled;
  final double? total;
  final double? warehouseTotal;
  final List<WarehouseStockLine> warehouses;
  final String? message;

  bool get hasMultipleActiveWarehouses =>
      warehouses.where((warehouse) => warehouse.isActive).length > 1;

  WarehouseStockLine? lineFor(String id) {
    for (final line in warehouses) {
      if (line.warehouseId == id) return line;
    }
    return null;
  }

  factory ProductWarehouseStockBreakdown.fromJson(Map<String, dynamic> json) {
    final rows = json['warehouses'] is List
        ? (json['warehouses'] as List)
        : const [];
    return ProductWarehouseStockBreakdown(
      productId: (json['productId'] ?? '').toString(),
      source: (json['source'] ?? 'LOCAL').toString(),
      readOnly: _asBool(json['readOnly']),
      reconciled: json['reconciled'] != false,
      total: json['total'] == null ? null : _asDouble(json['total']),
      warehouseTotal: json['warehouseTotal'] == null
          ? null
          : _asDouble(json['warehouseTotal']),
      warehouses: rows
          .whereType<Map>()
          .map((row) => WarehouseStockLine.fromJson(row.cast()))
          .toList(growable: false),
      message: json['message']?.toString(),
    );
  }
}

class WarehouseInventoryOverview {
  const WarehouseInventoryOverview({
    required this.warehouses,
    required this.terminals,
  });

  final List<WarehouseModel> warehouses;
  final List<TerminalWarehouseModel> terminals;

  List<WarehouseModel> get activeWarehouses =>
      warehouses.where((warehouse) => warehouse.isActive).toList();

  bool get hasMultipleActiveWarehouses => activeWarehouses.length > 1;
}

class WarehouseTransferItemDraft {
  const WarehouseTransferItemDraft({
    required this.productId,
    required this.quantity,
  });

  final String productId;
  final String quantity;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'quantity': quantity,
  };
}

class WarehouseTransferItemModel {
  const WarehouseTransferItemModel({
    required this.productId,
    required this.productName,
    required this.productCode,
    required this.quantity,
    required this.quantityDecimal,
    required this.unitSymbolSnapshot,
  });

  final String productId;
  final String productName;
  final String productCode;
  final double quantity;
  final String quantityDecimal;
  final String unitSymbolSnapshot;

  factory WarehouseTransferItemModel.fromJson(Map<String, dynamic> json) {
    return WarehouseTransferItemModel(
      productId: (json['productId'] ?? '').toString(),
      productName: (json['productName'] ?? '').toString(),
      productCode: (json['productCode'] ?? '').toString(),
      quantity: _asDouble(json['quantity']),
      quantityDecimal: (json['quantityDecimal'] ?? json['quantity'] ?? '0')
          .toString(),
      unitSymbolSnapshot: (json['unitSymbolSnapshot'] ?? 'u').toString(),
    );
  }
}

class WarehouseTransferModel {
  const WarehouseTransferModel({
    required this.id,
    required this.status,
    required this.sourceWarehouseName,
    required this.sourceWarehouseCode,
    required this.destinationWarehouseName,
    required this.destinationWarehouseCode,
    required this.itemCount,
    required this.items,
    this.notes,
    this.createdAt,
  });

  final String id;
  final String status;
  final String sourceWarehouseName;
  final String sourceWarehouseCode;
  final String destinationWarehouseName;
  final String destinationWarehouseCode;
  final int itemCount;
  final List<WarehouseTransferItemModel> items;
  final String? notes;
  final DateTime? createdAt;

  factory WarehouseTransferModel.fromJson(Map<String, dynamic> json) {
    final source = json['sourceWarehouse'] is Map
        ? Map<String, dynamic>.from(json['sourceWarehouse'] as Map)
        : const <String, dynamic>{};
    final destination = json['destinationWarehouse'] is Map
        ? Map<String, dynamic>.from(json['destinationWarehouse'] as Map)
        : const <String, dynamic>{};
    final rows = json['items'] is List ? json['items'] as List : const [];
    return WarehouseTransferModel(
      id: (json['id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      sourceWarehouseName: (source['name'] ?? '').toString(),
      sourceWarehouseCode: (source['code'] ?? '').toString(),
      destinationWarehouseName: (destination['name'] ?? '').toString(),
      destinationWarehouseCode: (destination['code'] ?? '').toString(),
      itemCount: _asInt(json['itemCount']),
      items: rows
          .whereType<Map>()
          .map((row) => WarehouseTransferItemModel.fromJson(row.cast()))
          .toList(growable: false),
      notes: json['notes']?.toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
    );
  }
}

final warehouseInventoryOverviewProvider =
    FutureProvider<WarehouseInventoryOverview>((ref) async {
      final repo = ref.watch(warehouseRepositoryProvider);
      final values = await Future.wait([
        repo.fetchWarehouses(),
        repo.fetchTerminals(),
      ]);
      return WarehouseInventoryOverview(
        warehouses: values[0] as List<WarehouseModel>,
        terminals: values[1] as List<TerminalWarehouseModel>,
      );
    });

class WarehouseRepository {
  const WarehouseRepository(this._dio);

  final Dio _dio;

  Future<List<WarehouseModel>> fetchWarehouses() async {
    final data = await _getList(ApiRoutes.warehouses);
    return data
        .whereType<Map>()
        .map((row) => WarehouseModel.fromJson(row.cast()))
        .toList(growable: false);
  }

  Future<List<TerminalWarehouseModel>> fetchTerminals() async {
    final data = await _getList(ApiRoutes.warehouseTerminals);
    return data
        .whereType<Map>()
        .map((row) => TerminalWarehouseModel.fromJson(row.cast()))
        .toList(growable: false);
  }

  Future<ProductWarehouseStockBreakdown> fetchProductStockBreakdown(
    String productId,
  ) async {
    try {
      final res = await _dio.get(ApiRoutes.productWarehouseStock(productId));
      return ProductWarehouseStockBreakdown.fromJson(
        Map<String, dynamic>.from((res.data as Map?) ?? const {}),
      );
    } on DioException catch (e) {
      throw ApiException(_message(e, 'No se pudo cargar el stock por almacén'));
    }
  }

  Future<List<ProductModel>> fetchProducts() async {
    try {
      final res = await _dio.get(ApiRoutes.products);
      final rows = res.data is List
          ? res.data as List
          : res.data is Map && (res.data as Map)['items'] is List
          ? (res.data as Map)['items'] as List
          : const [];
      return rows
          .whereType<Map>()
          .map((row) => ProductModel.fromJson(row.cast()))
          .where((product) => product.productSource == 'LOCAL')
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(_message(e, 'No se pudieron cargar los productos'));
    }
  }

  Future<List<WarehouseTransferModel>> fetchTransfers() async {
    final data = await _getList(ApiRoutes.warehouseTransfers);
    return data
        .whereType<Map>()
        .map((row) => WarehouseTransferModel.fromJson(row.cast()))
        .toList(growable: false);
  }

  Future<WarehouseTransferModel> createTransfer({
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required List<WarehouseTransferItemDraft> items,
    String? notes,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.warehouseTransfers,
        data: {
          'sourceWarehouseId': sourceWarehouseId,
          'destinationWarehouseId': destinationWarehouseId,
          'clientRequestId': DateTime.now().microsecondsSinceEpoch.toString(),
          if ((notes ?? '').trim().isNotEmpty) 'notes': notes!.trim(),
          'items': items.map((item) => item.toJson()).toList(),
        },
      );
      return WarehouseTransferModel.fromJson(
        Map<String, dynamic>.from((res.data as Map?) ?? const {}),
      );
    } on DioException catch (e) {
      throw ApiException(_message(e, 'No se pudo ejecutar la transferencia'));
    }
  }

  Future<void> createWarehouse({required String name, required String code}) {
    return _write(
      () => _dio.post(ApiRoutes.warehouses, data: {'name': name, 'code': code}),
    );
  }

  Future<void> updateWarehouse({
    required String id,
    required String name,
    required String code,
  }) {
    return _write(
      () => _dio.patch(
        ApiRoutes.warehouse(id),
        data: {'name': name, 'code': code},
      ),
    );
  }

  Future<void> setDefault(String id) {
    return _write(() => _dio.patch(ApiRoutes.warehouseDefault(id)));
  }

  Future<void> activate(String id) {
    return _write(() => _dio.patch(ApiRoutes.warehouseActivate(id)));
  }

  Future<void> deactivate(String id) {
    return _write(() => _dio.patch(ApiRoutes.warehouseDeactivate(id)));
  }

  Future<void> updateTerminalWarehouse({
    required String terminalId,
    required String warehouseId,
  }) {
    return _write(
      () => _dio.patch(
        ApiRoutes.terminalWarehouse(terminalId),
        data: {'warehouseId': warehouseId},
      ),
    );
  }

  Future<List<dynamic>> _getList(String path) async {
    try {
      final res = await _dio.get(path);
      if (res.data is List) return res.data as List;
      if (res.data is Map && (res.data as Map)['items'] is List) {
        return (res.data as Map)['items'] as List;
      }
      return const [];
    } on DioException catch (e) {
      throw ApiException(_message(e, 'No se pudieron cargar los almacenes'));
    }
  }

  Future<void> _write(Future<Response<dynamic>> Function() action) async {
    try {
      await action();
    } on DioException catch (e) {
      throw ApiException(_message(e, 'No se pudo guardar el almacén'));
    }
  }

  String _message(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message.trim();
      }
      if (message is List && message.isNotEmpty) {
        return message.first.toString();
      }
    }
    return fallback;
  }
}
