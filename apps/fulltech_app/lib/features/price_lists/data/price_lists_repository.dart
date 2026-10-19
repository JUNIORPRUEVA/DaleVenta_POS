import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';

final priceListsRepositoryProvider = Provider<PriceListsRepository>((ref) {
  return PriceListsRepository(ref.watch(dioProvider));
});

final priceListsProvider = FutureProvider<List<PriceListModel>>((ref) {
  return ref.watch(priceListsRepositoryProvider).fetchPriceLists();
});

class PriceListsRepository {
  PriceListsRepository(this._dio);

  final Dio _dio;

  Future<List<PriceListModel>> fetchPriceLists() async {
    final response = await _dio.get(ApiRoutes.priceLists);
    final data = response.data;
    final rows = data is List ? data : const [];
    return rows
        .whereType<Map>()
        .map((row) => PriceListModel.fromMap(row.cast<String, dynamic>()))
        .toList();
  }

  Future<PriceListModel> createPriceList({
    required String name,
    String description = '',
  }) async {
    final response = await _dio.post(
      ApiRoutes.priceLists,
      data: {'name': name.trim(), 'description': description.trim()},
    );
    return PriceListModel.fromMap((response.data as Map).cast());
  }

  Future<PriceListModel> updatePriceList({
    required String id,
    String? name,
    String? description,
    bool? active,
  }) async {
    final response = await _dio.patch(
      ApiRoutes.priceList(id),
      data: {
        if (name != null) 'name': name.trim(),
        if (description != null) 'description': description.trim(),
        if (active != null) 'active': active,
      },
    );
    return PriceListModel.fromMap((response.data as Map).cast());
  }

  Future<PriceListRuleModel> upsertRule({
    required String priceListId,
    required String productId,
    required String mode,
    double? fixedPrice,
    double? discountPercent,
    double minQuantity = 1,
    List<PriceListTierDraft> tiers = const [],
  }) async {
    final response = await _dio.post(
      ApiRoutes.priceListRules(priceListId),
      data: {
        'productId': productId,
        'mode': mode,
        'minQuantity': minQuantity,
        if (fixedPrice != null) 'fixedPrice': fixedPrice,
        if (discountPercent != null) 'discountPercent': discountPercent,
        'tiers': tiers.map((tier) => tier.toMap()).toList(),
      },
    );
    return PriceListRuleModel.fromMap((response.data as Map).cast());
  }

  Future<ResolvedPriceLine> resolveLine({
    required String productId,
    required double qty,
    String? priceListId,
    String? clientId,
  }) async {
    final response = await _dio.post(
      ApiRoutes.priceListResolveLine,
      data: {
        'productId': productId,
        'qty': qty,
        if (priceListId != null && priceListId.trim().isNotEmpty)
          'priceListId': priceListId.trim(),
        if (clientId != null && clientId.trim().isNotEmpty)
          'clientId': clientId.trim(),
      },
    );
    return ResolvedPriceLine.fromMap((response.data as Map).cast());
  }

  Future<void> assignClientPriceList({
    required String clientId,
    String? priceListId,
  }) async {
    await _dio.patch(
      ApiRoutes.clientPriceList(clientId),
      data: {'priceListId': priceListId},
    );
  }
}

class PriceListModel {
  const PriceListModel({
    required this.id,
    required this.name,
    required this.active,
    required this.priority,
    this.description = '',
    this.rules = const [],
    this.ruleCount = 0,
    this.clientCount = 0,
  });

  final String id;
  final String name;
  final String description;
  final bool active;
  final int priority;
  final List<PriceListRuleModel> rules;
  final int ruleCount;
  final int clientCount;

  factory PriceListModel.fromMap(Map<String, dynamic> map) {
    final count = map['_count'];
    final rulesRaw = map['productRules'];
    return PriceListModel(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      active: map['active'] != false,
      priority: _int(map['priority']),
      rules: rulesRaw is List
          ? rulesRaw
                .whereType<Map>()
                .map((row) => PriceListRuleModel.fromMap(row.cast()))
                .toList()
          : const [],
      ruleCount: count is Map ? _int(count['productRules']) : 0,
      clientCount: count is Map ? _int(count['clients']) : 0,
    );
  }
}

class PriceListRuleModel {
  const PriceListRuleModel({
    required this.id,
    required this.productId,
    required this.productName,
    required this.referencePrice,
    required this.mode,
    required this.minQuantity,
    this.fixedPrice,
    this.discountPercent,
    this.tiers = const [],
  });

  final String id;
  final String productId;
  final String productName;
  final double referencePrice;
  final String mode;
  final double minQuantity;
  final double? fixedPrice;
  final double? discountPercent;
  final List<PriceListTierModel> tiers;

  factory PriceListRuleModel.fromMap(Map<String, dynamic> map) {
    final product = map['product'];
    final tiersRaw = map['tiers'];
    return PriceListRuleModel(
      id: (map['id'] ?? '').toString(),
      productId: (map['productId'] ?? map['product_id'] ?? '').toString(),
      productName: product is Map
          ? (product['nombre'] ?? '').toString()
          : 'Producto',
      referencePrice: product is Map ? _double(product['precio']) : 0,
      mode: (map['mode'] ?? 'FIXED_PRICE').toString(),
      minQuantity: _double(map['minQuantity'] ?? map['min_quantity'] ?? 1),
      fixedPrice: _nullableDouble(map['fixedPrice'] ?? map['fixed_price']),
      discountPercent: _nullableDouble(
        map['discountPercent'] ?? map['discount_percent'],
      ),
      tiers: tiersRaw is List
          ? tiersRaw
                .whereType<Map>()
                .map((row) => PriceListTierModel.fromMap(row.cast()))
                .toList()
          : const [],
    );
  }
}

class PriceListTierModel {
  const PriceListTierModel({
    required this.minQuantity,
    this.mode,
    this.fixedPrice,
    this.discountPercent,
  });

  final double minQuantity;
  final String? mode;
  final double? fixedPrice;
  final double? discountPercent;

  factory PriceListTierModel.fromMap(Map<String, dynamic> map) {
    return PriceListTierModel(
      minQuantity: _double(map['minQuantity'] ?? map['min_quantity']),
      mode: map['mode']?.toString(),
      fixedPrice: _nullableDouble(map['fixedPrice'] ?? map['fixed_price']),
      discountPercent: _nullableDouble(
        map['discountPercent'] ?? map['discount_percent'],
      ),
    );
  }
}

class PriceListTierDraft {
  const PriceListTierDraft({
    required this.minQuantity,
    this.mode,
    this.fixedPrice,
    this.discountPercent,
  });

  final double minQuantity;
  final String? mode;
  final double? fixedPrice;
  final double? discountPercent;

  Map<String, dynamic> toMap() => {
    'minQuantity': minQuantity,
    if (mode != null) 'mode': mode,
    if (fixedPrice != null) 'fixedPrice': fixedPrice,
    if (discountPercent != null) 'discountPercent': discountPercent,
  };
}

class ResolvedPriceLine {
  const ResolvedPriceLine({
    required this.applied,
    required this.unitPrice,
    required this.originalUnitPrice,
    required this.reason,
  });

  final bool applied;
  final double unitPrice;
  final double originalUnitPrice;
  final String reason;

  factory ResolvedPriceLine.fromMap(Map<String, dynamic> map) {
    return ResolvedPriceLine(
      applied: map['applied'] == true,
      unitPrice: _double(map['unitPrice']),
      originalUnitPrice: _double(map['originalUnitPrice']),
      reason: (map['reason'] ?? '').toString(),
    );
  }
}

int _int(dynamic value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _double(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

double? _nullableDouble(dynamic value) {
  if (value == null) return null;
  return _double(value);
}
