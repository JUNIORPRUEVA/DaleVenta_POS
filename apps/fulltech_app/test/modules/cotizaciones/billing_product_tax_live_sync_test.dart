import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/tax/product_tax_preview_calculator.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Facturacion crea lineas con fiscalidad del producto vigente', () {
    final item = buildBillingItemFromProduct(_product(taxTreatment: 'EXEMPT'));

    expect(item.taxTreatment, 'EXEMPT');
    expect(item.taxRate, 0);
    expect(item.taxPriceMode, 'NO_TAX');

    final preview = _previewFor(item);
    expect(preview.taxAmount, 0);
    expect(preview.finalAmount, 2500);
    expect(
      shouldShowBillingItbis(
        taxEnabled: preview.taxEnabled,
        taxAmount: preview.taxAmount,
      ),
      isFalse,
    );
  });

  test('Facturacion sincroniza al instante INHERIT a EXEMPT', () {
    final item = buildBillingItemFromProduct(_product(taxTreatment: 'INHERIT'));
    final updated = syncBillingItemFiscalFromProduct(
      item,
      _product(taxTreatment: 'EXEMPT'),
    );

    expect(updated.taxTreatment, 'EXEMPT');
    expect(updated.taxRate, 0);
    expect(updated.taxPriceMode, 'NO_TAX');

    final preview = _previewFor(updated);
    expect(preview.taxAmount, 0);
    expect(preview.finalAmount, 2500);
  });

  test('Facturacion corrige lineas abiertas cuando producto pasa a EXEMPT', () {
    final staleItem = buildBillingItemFromProduct(
      _product(taxTreatment: 'INHERIT'),
    );
    final synced = syncBillingItemsFiscalFromProducts(
      items: [staleItem],
      productsById: {staleItem.productId: _product(taxTreatment: 'EXEMPT')},
    ).single;
    final preview = _previewFor(synced);

    expect(synced.taxTreatment, 'EXEMPT');
    expect(preview.taxAmount, 0);
    expect(preview.finalAmount, 2500);
    expect(
      shouldShowBillingItbis(
        taxEnabled: preview.taxEnabled,
        taxAmount: preview.taxAmount,
      ),
      isFalse,
    );
  });

  test('Facturacion envia EXEMPT en payload de venta', () {
    const item = SaleDraftItem(
      productId: '11111111-1111-4111-8111-111111111111',
      name: 'Producto fiscal',
      imageUrl: null,
      isExternal: false,
      qty: 1,
      priceSoldUnit: 2500,
      costUnitSnapshot: 1000,
      taxTreatment: 'EXEMPT',
      taxRate: null,
      taxPriceMode: 'NO_TAX',
    );

    final payload = item.toPayload();

    expect(payload['taxTreatment'], 'EXEMPT');
    expect(payload.containsKey('taxRate'), isFalse);
    expect(payload['taxPriceMode'], 'NO_TAX');
  });

  test('Facturacion INHERIT aplica ITBIS de empresa', () {
    final item = buildBillingItemFromProduct(_product(taxTreatment: 'INHERIT'));
    final preview = _previewFor(item);

    expect(preview.taxAmount, 450);
    expect(preview.finalAmount, 2950);
    expect(
      shouldShowBillingItbis(
        taxEnabled: preview.taxEnabled,
        taxAmount: preview.taxAmount,
      ),
      isTrue,
    );
  });

  test('Facturacion sincroniza TAXABLE con tasa y modo', () {
    final item = buildBillingItemFromProduct(_product(taxTreatment: 'EXEMPT'));
    final updated = syncBillingItemFiscalFromProduct(
      item,
      _product(
        taxTreatment: 'TAXABLE',
        taxRate: 0.18,
        taxPriceMode: 'TAX_ADDED',
      ),
    );

    expect(updated.taxTreatment, 'TAXABLE');
    expect(updated.taxRate, 0.18);
    expect(updated.taxPriceMode, 'TAX_ADDED');

    final preview = _previewFor(updated);
    expect(preview.taxAmount, 450);
    expect(preview.finalAmount, 2950);
  });

  test('Facturacion prorratea descuento general y recalcula ITBIS', () {
    final summary = ProductTaxPreviewCalculator.calculateCart(
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
      globalDiscountAmount: 200,
      lines: const [
        ProductCartTaxLineInput(
          price: 900,
          quantity: 1,
          taxTreatment: 'EXEMPT',
          taxPriceMode: 'NO_TAX',
        ),
        ProductCartTaxLineInput(
          price: 2500,
          quantity: 1,
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_ADDED',
        ),
      ],
    );

    expect(summary.subtotal, 3400);
    expect(summary.generalDiscountAmount, 200);
    expect(summary.lines[0].generalDiscountAmount, 52.94);
    expect(summary.lines[0].preview.taxAmount, 0);
    expect(summary.lines[1].generalDiscountAmount, 147.06);
    expect(summary.taxableBase, 2352.94);
    expect(summary.taxAmount, 423.53);
    expect(summary.exemptAmount, 847.06);
    expect(summary.total, 3623.53);
  });
}

ProductTaxPreview _previewFor(CotizacionItem item) {
  return ProductTaxPreviewCalculator.calculate(
    price: item.unitPrice,
    quantity: item.qty,
    companyTaxEnabled: true,
    companyPricesIncludeTax: false,
    companyDefaultTaxRate: 0.18,
    taxTreatment: item.taxTreatment,
    taxRate: item.taxRate > 0 ? item.taxRate : null,
    taxPriceMode: item.taxPriceMode,
  );
}

ProductModel _product({
  required String taxTreatment,
  double? taxRate,
  String? taxPriceMode,
}) {
  return ProductModel(
    id: '11111111-1111-4111-8111-111111111111',
    nombre: 'Producto fiscal',
    precio: 2500,
    costo: 1000,
    stock: 10,
    taxTreatment: taxTreatment,
    taxRate: taxRate,
    taxPriceMode: taxPriceMode,
  );
}
