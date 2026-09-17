import 'dart:io';

import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  await initializeDateFormatting('es_DO');

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

  test('Facturacion ordena productos fijados primero sin reordenar el resto', () {
    final agua = _product(id: 'agua', trackInventory: true);
    final cafe = _product(id: 'cafe', trackInventory: true);
    final pan = _product(id: 'pan', trackInventory: true);
    final sorted = sortBillingProductsWithPinnedFirst(
      [agua, cafe, pan],
      {'pan'},
    );

    expect(sorted, [pan, agua, cafe]);
  });

  test('Ventas recientes muestra fecha en zona de negocio, no UTC futura', () {
    final label = formatRecentSaleDateLabel(
      DateTime.utc(2026, 9, 17, 2, 35),
    );

    expect(label, '16/09/2026 22:35');
  });
}

ProductModel _product({
  String? id,
  String itemType = 'PRODUCT',
  required bool trackInventory,
}) {
  return ProductModel(
    id: id ?? 'product-$itemType-$trackInventory',
    nombre: 'Producto prueba',
    precio: 100,
    costo: 50,
    stock: 0,
    itemType: itemType,
    trackInventory: trackInventory,
  );
}
