import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daleventa_pos/modules/compras/data/purchase_order_draft_storage.dart';
import 'package:daleventa_pos/modules/compras/purchase_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores purchase drafts with a company-scoped v2 key', () async {
    const storage = PurchaseOrderDraftStorage();
    await storage.save(companyId: 'company-a', draft: _draft('A'));
    await storage.save(companyId: 'company-b', draft: _draft('B'));

    final a = await storage.restore(companyId: 'company-a');
    final b = await storage.restore(companyId: 'company-b');

    expect(a?.items.single.productName, 'A');
    expect(b?.items.single.productName, 'B');
  });

  test(
    'preserves unsafe legacy draft without restoring it to a company',
    () async {
      SharedPreferences.setMockInitialValues({
        PurchaseOrderDraftStorage.legacyKey: jsonEncode({
          'supplierId': 's-1',
          'items': [_item('legacy').toDraftJson()],
        }),
      });
      const storage = PurchaseOrderDraftStorage();

      expect(await storage.restore(companyId: 'company-a'), isNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PurchaseOrderDraftStorage.legacyKey), isNotNull);
    },
  );

  test('copies legacy draft only when its companyId matches', () async {
    SharedPreferences.setMockInitialValues({
      PurchaseOrderDraftStorage.legacyKey: jsonEncode({
        'companyId': 'company-a',
        'supplierId': 's-1',
        'items': [_item('legacy-a').toDraftJson()],
      }),
    });
    const storage = PurchaseOrderDraftStorage();

    final restored = await storage.restore(companyId: 'company-a');
    final prefs = await SharedPreferences.getInstance();

    expect(restored?.items.single.productName, 'legacy-a');
    expect(
      prefs.getString(PurchaseOrderDraftStorage.keyForCompany('company-a')),
      isNotNull,
    );
    expect(prefs.getString(PurchaseOrderDraftStorage.legacyKey), isNotNull);
  });
}

PurchaseOrderDraftData _draft(String name) {
  return PurchaseOrderDraftData(
    supplierId: 's-1',
    notes: '',
    instructions: '',
    discount: '0',
    shipping: '0',
    additional: '0',
    tax: '0',
    showPurchaseExtras: false,
    items: [_item(name)],
  );
}

PurchaseDraftItem _item(String name) {
  return PurchaseDraftItem(
    productId: 'p-1',
    productName: name,
    quantity: 1,
    unitCost: 10,
  );
}
