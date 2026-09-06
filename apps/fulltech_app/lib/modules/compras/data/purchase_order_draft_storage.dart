import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../purchase_models.dart';

class PurchaseOrderDraftData {
  const PurchaseOrderDraftData({
    required this.supplierId,
    required this.notes,
    required this.instructions,
    required this.discount,
    required this.shipping,
    required this.additional,
    required this.tax,
    required this.showPurchaseExtras,
    required this.items,
  });

  final String? supplierId;
  final String notes;
  final String instructions;
  final String discount;
  final String shipping;
  final String additional;
  final String tax;
  final bool showPurchaseExtras;
  final List<PurchaseDraftItem> items;
}

class PurchaseOrderDraftStorage {
  static const legacyKey = 'purchase_order_draft_v1';
  static const _keyPrefix = 'purchase_order_draft_v2';

  const PurchaseOrderDraftStorage();

  Future<void> save({
    required String companyId,
    required PurchaseOrderDraftData draft,
  }) async {
    final scope = _normalizeCompanyId(companyId);
    if (scope.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      keyForCompany(scope),
      jsonEncode({
        'companyId': scope,
        'supplierId': draft.supplierId,
        'notes': draft.notes,
        'instructions': draft.instructions,
        'discount': draft.discount,
        'shipping': draft.shipping,
        'additional': draft.additional,
        'tax': draft.tax,
        'showPurchaseExtras': draft.showPurchaseExtras,
        'items': draft.items.map((item) => item.toDraftJson()).toList(),
      }),
    );
  }

  Future<PurchaseOrderDraftData?> restore({required String companyId}) async {
    final scope = _normalizeCompanyId(companyId);
    if (scope.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyForCompany(scope));
    if (raw != null && raw.trim().isNotEmpty) {
      return _decode(raw, expectedCompanyId: scope);
    }

    final legacyRaw = prefs.getString(legacyKey);
    if (legacyRaw == null || legacyRaw.trim().isEmpty) return null;
    final decoded = _decode(legacyRaw, expectedCompanyId: scope);
    if (decoded != null) {
      await prefs.setString(keyForCompany(scope), legacyRaw);
    }
    return decoded;
  }

  Future<void> clear({required String companyId}) async {
    final scope = _normalizeCompanyId(companyId);
    if (scope.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyForCompany(scope));
  }

  static String keyForCompany(String companyId) {
    final scope = _normalizeCompanyId(
      companyId,
    ).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${_keyPrefix}_$scope';
  }

  static String _normalizeCompanyId(String companyId) => companyId.trim();

  PurchaseOrderDraftData? _decode(
    String raw, {
    required String expectedCompanyId,
  }) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return null;
      final storedCompanyId = (data['companyId'] ?? '').toString().trim();
      if (storedCompanyId.isEmpty || storedCompanyId != expectedCompanyId) {
        return null;
      }
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                PurchaseDraftItem.fromDraftJson(Map<String, dynamic>.from(row)),
          )
          .where((item) => item.productName.trim().isNotEmpty)
          .toList();
      return PurchaseOrderDraftData(
        supplierId: data['supplierId'] is String
            ? data['supplierId'] as String
            : null,
        notes: '${data['notes'] ?? ''}',
        instructions: '${data['instructions'] ?? ''}',
        discount: '${data['discount'] ?? '0'}',
        shipping: '${data['shipping'] ?? '0'}',
        additional: '${data['additional'] ?? '0'}',
        tax: '${data['tax'] ?? '0'}',
        showPurchaseExtras: data['showPurchaseExtras'] is bool
            ? data['showPurchaseExtras'] as bool
            : false,
        items: items,
      );
    } catch (_) {
      return null;
    }
  }
}
