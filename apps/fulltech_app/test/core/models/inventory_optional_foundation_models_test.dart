import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

void main() {
  group('INVENTORY-OPTIONAL-02 model compatibility', () {
    test('old company settings cache defaults inventoryEnabled to true', () {
      final settings = CompanySettings.fromMap(const {
        'companyName': 'FullPOS Cloud',
      });

      expect(settings.inventoryEnabled, isTrue);
      expect(settings.toMap(), containsPair('inventoryEnabled', true));
    });

    test('old product JSON defaults to PRODUCT and trackInventory=true', () {
      final product = ProductModel.fromJson(const {
        'id': 'product-1',
        'nombre': 'Laptop',
        'precio': 100,
        'costo': 70,
        'stock': 3,
        'categoria': 'Equipos',
      });

      expect(product.itemType, 'PRODUCT');
      expect(product.trackInventory, isTrue);
      expect(product.toJson(), containsPair('itemType', 'PRODUCT'));
      expect(product.toJson(), containsPair('trackInventory', true));
    });

    test('new product JSON parses SERVICE and trackInventory=false', () {
      final product = ProductModel.fromJson(const {
        'id': 'service-1',
        'nombre': 'Instalacion',
        'precio': 100,
        'costo': 0,
        'stock': 0,
        'categoria': 'Servicios',
        'item_type': 'SERVICE',
        'track_inventory': false,
      });

      expect(product.itemType, 'SERVICE');
      expect(product.trackInventory, isFalse);
    });

    test('legacy sale items derive inventory snapshot from old semantics', () {
      final local = SaleItemModel.fromJson(const {
        'id': 'item-1',
        'productId': 'product-1',
        'productSource': 'LOCAL',
        'productNameSnapshot': 'Laptop',
        'productImageSnapshot': null,
      });
      final manual = SaleItemModel.fromJson(const {
        'id': 'item-2',
        'productNameSnapshot': 'Servicio manual',
        'productImageSnapshot': null,
      });
      final external = SaleItemModel.fromJson(const {
        'id': 'item-3',
        'productId': 'external-1',
        'productSource': 'FULLPOS',
        'productNameSnapshot': 'Externo',
        'productImageSnapshot': null,
      });

      expect(local.inventoryTrackedSnapshot, isTrue);
      expect(manual.inventoryTrackedSnapshot, isFalse);
      expect(external.inventoryTrackedSnapshot, isFalse);
    });

    test('sale draft captures effective inventory decision once', () {
      final trackedProduct = ProductModel.fromJson(const {
        'id': '11111111-1111-4111-8111-111111111111',
        'nombre': 'Tela',
        'precio': 100,
        'costo': 20,
        'stock': 3,
        'itemType': 'PRODUCT',
        'trackInventory': true,
      });
      final service = trackedProduct.copyWith(
        id: '22222222-2222-4222-8222-222222222222',
        itemType: 'SERVICE',
        trackInventory: false,
      );

      final tracked = SaleDraftItem(
        product: trackedProduct,
        productId: trackedProduct.id,
        productSource: 'LOCAL',
        sourceProductId: trackedProduct.id,
        name: trackedProduct.nombre,
        imageUrl: null,
        isExternal: false,
        qty: 2,
        priceSoldUnit: 100,
        costUnitSnapshot: 20,
      ).captureInventoryDecision(inventoryEnabled: true);
      final companyOff = tracked.captureInventoryDecision(
        inventoryEnabled: false,
      );
      final serviceItem = SaleDraftItem(
        product: service,
        productId: service.id,
        productSource: 'LOCAL',
        sourceProductId: service.id,
        name: service.nombre,
        imageUrl: null,
        isExternal: false,
        qty: 1,
        priceSoldUnit: 100,
        costUnitSnapshot: 0,
      ).captureInventoryDecision(inventoryEnabled: true);

      expect(tracked.inventoryTrackedSnapshot, isTrue);
      expect(
        tracked.toPayload(),
        containsPair('inventoryTrackedSnapshot', true),
      );
      expect(companyOff.inventoryTrackedSnapshot, isFalse);
      expect(serviceItem.inventoryTrackedSnapshot, isFalse);
    });

    test('legacy sale draft payload without snapshot remains compatible', () {
      final item = SaleDraftItem.fromPayload(const {
        'productId': 'product-1',
        'productName': 'Legacy',
        'qty': 1,
        'priceSoldUnit': 100,
        'costUnitSnapshot': 20,
      });

      expect(item.inventoryTrackedSnapshot, isNull);
      expect(item.toPayload().containsKey('inventoryTrackedSnapshot'), isFalse);
    });
  });
}
