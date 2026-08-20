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

  test(
    'descuento general porcentual usa neto despues de descuentos de linea',
    () {
      final generalDiscount =
          ProductTaxPreviewCalculator.generalDiscountAmountFromPercent(
            percent: 10,
            lines: const [
              ProductCartTaxLineInput(
                price: 900,
                quantity: 1,
                lineDiscountAmount: 90,
                taxTreatment: 'EXEMPT',
                taxPriceMode: 'NO_TAX',
              ),
              ProductCartTaxLineInput(
                price: 2500,
                quantity: 1,
                lineDiscountAmount: 250,
                taxTreatment: 'TAXABLE',
                taxRate: 0.18,
                taxPriceMode: 'TAX_ADDED',
              ),
            ],
          );
      final summary = ProductTaxPreviewCalculator.calculateCart(
        companyTaxEnabled: true,
        companyPricesIncludeTax: false,
        companyDefaultTaxRate: 0.18,
        globalDiscountAmount: generalDiscount,
        lines: const [
          ProductCartTaxLineInput(
            price: 900,
            quantity: 1,
            lineDiscountAmount: 90,
            taxTreatment: 'EXEMPT',
            taxPriceMode: 'NO_TAX',
          ),
          ProductCartTaxLineInput(
            price: 2500,
            quantity: 1,
            lineDiscountAmount: 250,
            taxTreatment: 'TAXABLE',
            taxRate: 0.18,
            taxPriceMode: 'TAX_ADDED',
          ),
        ],
      );

      expect(summary.subtotal, 3400);
      expect(summary.discountAmount, 646);
      expect(generalDiscount, 306);
      expect(summary.generalDiscountAmount, 306);
      expect(summary.lines[0].generalDiscountAmount, 81);
      expect(summary.lines[1].generalDiscountAmount, 225);
      expect(summary.exemptAmount, 729);
      expect(summary.taxableBase, 2025);
      expect(summary.taxAmount, 364.5);
      expect(summary.total, 3118.5);
    },
  );

  test('descuento general porcentual solo TAXABLE', () {
    final generalDiscount =
        ProductTaxPreviewCalculator.generalDiscountAmountFromPercent(
          percent: 10,
          lines: const [
            ProductCartTaxLineInput(
              price: 2500,
              quantity: 1,
              taxTreatment: 'TAXABLE',
              taxRate: 0.18,
              taxPriceMode: 'TAX_ADDED',
            ),
          ],
        );
    final summary = ProductTaxPreviewCalculator.calculateCart(
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
      globalDiscountAmount: generalDiscount,
      lines: const [
        ProductCartTaxLineInput(
          price: 2500,
          quantity: 1,
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_ADDED',
        ),
      ],
    );

    expect(generalDiscount, 250);
    expect(summary.taxableBase, 2250);
    expect(summary.taxAmount, 405);
    expect(summary.total, 2655);
  });

  test('descuento general porcentual solo EXEMPT', () {
    final generalDiscount =
        ProductTaxPreviewCalculator.generalDiscountAmountFromPercent(
          percent: 10,
          lines: const [
            ProductCartTaxLineInput(
              price: 900,
              quantity: 1,
              taxTreatment: 'EXEMPT',
              taxPriceMode: 'NO_TAX',
            ),
          ],
        );
    final summary = ProductTaxPreviewCalculator.calculateCart(
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
      globalDiscountAmount: generalDiscount,
      lines: const [
        ProductCartTaxLineInput(
          price: 900,
          quantity: 1,
          taxTreatment: 'EXEMPT',
          taxPriceMode: 'NO_TAX',
        ),
      ],
    );

    expect(generalDiscount, 90);
    expect(summary.taxAmount, 0);
    expect(summary.exemptAmount, 810);
    expect(summary.total, 810);
  });

  test('descuento general porcentual mixto sin descuentos de linea', () {
    final generalDiscount =
        ProductTaxPreviewCalculator.generalDiscountAmountFromPercent(
          percent: 10,
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
    final summary = ProductTaxPreviewCalculator.calculateCart(
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
      globalDiscountAmount: generalDiscount,
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

    expect(generalDiscount, 340);
    expect(summary.lines[0].generalDiscountAmount, 90);
    expect(summary.lines[1].generalDiscountAmount, 250);
    expect(summary.taxableBase, 2250);
    expect(summary.taxAmount, 405);
    expect(summary.total, 3465);
  });

  test('descuento general porcentual cero no altera totales', () {
    final generalDiscount =
        ProductTaxPreviewCalculator.generalDiscountAmountFromPercent(
          percent: 0,
          lines: const [
            ProductCartTaxLineInput(
              price: 2500,
              quantity: 1,
              taxTreatment: 'TAXABLE',
              taxRate: 0.18,
              taxPriceMode: 'TAX_ADDED',
            ),
          ],
        );
    final summary = ProductTaxPreviewCalculator.calculateCart(
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
      globalDiscountAmount: generalDiscount,
      lines: const [
        ProductCartTaxLineInput(
          price: 2500,
          quantity: 1,
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_ADDED',
        ),
      ],
    );

    expect(generalDiscount, 0);
    expect(summary.taxableBase, 2500);
    expect(summary.taxAmount, 450);
    expect(summary.total, 2950);
  });

  test('descuento general porcentual 100 no produce total negativo', () {
    final generalDiscount =
        ProductTaxPreviewCalculator.generalDiscountAmountFromPercent(
          percent: 100,
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
    final summary = ProductTaxPreviewCalculator.calculateCart(
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
      globalDiscountAmount: generalDiscount,
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

    expect(generalDiscount, 3400);
    expect(summary.taxableBase, 0);
    expect(summary.taxAmount, 0);
    expect(summary.exemptAmount, 0);
    expect(summary.total, 0);
  });

  test('descuento general porcentual mantiene centavos por prorrateo', () {
    final generalDiscount =
        ProductTaxPreviewCalculator.generalDiscountAmountFromPercent(
          percent: 12.5,
          lines: const [
            ProductCartTaxLineInput(
              price: 99.99,
              quantity: 2,
              lineDiscountAmount: 10.01,
              taxTreatment: 'EXEMPT',
              taxPriceMode: 'NO_TAX',
            ),
            ProductCartTaxLineInput(
              price: 33.33,
              quantity: 3,
              lineDiscountAmount: 4.44,
              taxTreatment: 'TAXABLE',
              taxRate: 0.18,
              taxPriceMode: 'TAX_ADDED',
            ),
          ],
        );
    final summary = ProductTaxPreviewCalculator.calculateCart(
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
      globalDiscountAmount: generalDiscount,
      lines: const [
        ProductCartTaxLineInput(
          price: 99.99,
          quantity: 2,
          lineDiscountAmount: 10.01,
          taxTreatment: 'EXEMPT',
          taxPriceMode: 'NO_TAX',
        ),
        ProductCartTaxLineInput(
          price: 33.33,
          quantity: 3,
          lineDiscountAmount: 4.44,
          taxTreatment: 'TAXABLE',
          taxRate: 0.18,
          taxPriceMode: 'TAX_ADDED',
        ),
      ],
    );

    expect(generalDiscount, 35.69);
    expect(summary.generalDiscountAmount, 35.69);
    expect(
      summary.lines.fold<double>(
        0,
        (sum, line) => sum + line.generalDiscountAmount,
      ),
      35.69,
    );
    expect(summary.taxableBase, 83.61);
    expect(summary.taxAmount, 15.05);
    expect(summary.total, 264.88);
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
