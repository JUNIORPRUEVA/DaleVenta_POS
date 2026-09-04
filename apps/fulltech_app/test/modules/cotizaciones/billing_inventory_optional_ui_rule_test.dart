import 'dart:io';

import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Facturacion muestra stock solo con inventario empresa y producto tracked',
    () {
      final trackedProduct = _product(trackInventory: true);
      final untrackedProduct = _product(trackInventory: false);
      final service = _product(itemType: 'SERVICE', trackInventory: true);

      expect(
        shouldShowBillingStockState(
          companyInventoryEnabled: true,
          product: trackedProduct,
        ),
        isTrue,
      );
      expect(
        shouldShowBillingStockState(
          companyInventoryEnabled: false,
          product: trackedProduct,
        ),
        isFalse,
      );
      expect(
        shouldShowBillingStockState(
          companyInventoryEnabled: true,
          product: untrackedProduct,
        ),
        isFalse,
      );
      expect(
        shouldShowBillingStockState(
          companyInventoryEnabled: true,
          product: service,
        ),
        isFalse,
      );
    },
  );

  test(
    'Facturacion moderna refresca settings al volver y oculta controles stock',
    () {
      final source = File(
        'lib/modules/cotizaciones/cotizaciones_screen.dart',
      ).readAsStringSync();

      expect(source, contains('ref.invalidate(companySettingsProvider);'));
      expect(source, contains('if (widget.inventoryEnabled) ...['));
      expect(source, contains('required this.showStockState'));
      expect(source, contains('if (widget.showStockState)'));
    },
  );
}

ProductModel _product({
  String itemType = 'PRODUCT',
  required bool trackInventory,
}) {
  return ProductModel(
    id: 'product-$itemType-$trackInventory',
    nombre: 'Producto prueba',
    precio: 100,
    costo: 50,
    stock: 0,
    itemType: itemType,
    trackInventory: trackInventory,
  );
}
