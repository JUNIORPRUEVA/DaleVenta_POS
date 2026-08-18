import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/tax/product_tax_preview_calculator.dart';

void main() {
  test('extrae ITBIS incluido desde 1180 al 18%', () {
    final preview = ProductTaxPreviewCalculator.calculate(
      price: 1180,
      companyTaxEnabled: true,
      companyPricesIncludeTax: true,
      companyDefaultTaxRate: 0.18,
    );

    expect(preview.baseAmount, 1000);
    expect(preview.taxAmount, 180);
    expect(preview.finalAmount, 1180);
    expect(preview.priceIncludesTax, isTrue);
  });

  test('agrega ITBIS sobre precio base 1000 al 18%', () {
    final preview = ProductTaxPreviewCalculator.calculate(
      price: 1000,
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
    );

    expect(preview.baseAmount, 1000);
    expect(preview.taxAmount, 180);
    expect(preview.finalAmount, 1180);
    expect(preview.priceIncludesTax, isFalse);
  });

  test('producto exento mantiene final igual al precio', () {
    final preview = ProductTaxPreviewCalculator.calculate(
      price: 500,
      companyTaxEnabled: true,
      companyPricesIncludeTax: true,
      companyDefaultTaxRate: 0.18,
      taxTreatment: 'EXEMPT',
    );

    expect(preview.taxable, isFalse);
    expect(preview.exemptAmount, 500);
    expect(preview.taxAmount, 0);
    expect(preview.finalAmount, 500);
  });

  test('redondea a centavos en precio incluido', () {
    final preview = ProductTaxPreviewCalculator.calculate(
      price: 99.99,
      companyTaxEnabled: true,
      companyPricesIncludeTax: true,
      companyDefaultTaxRate: 0.18,
    );

    expect(preview.baseAmount, 84.74);
    expect(preview.taxAmount, 15.25);
    expect(preview.finalAmount, 99.99);
  });

  test('calcula cantidad mayor a 1 con precio incluido', () {
    final preview = ProductTaxPreviewCalculator.calculate(
      price: 118,
      quantity: 3,
      companyTaxEnabled: true,
      companyPricesIncludeTax: true,
      companyDefaultTaxRate: 0.18,
    );

    expect(preview.baseAmount, 300);
    expect(preview.taxAmount, 54);
    expect(preview.finalAmount, 354);
  });

  test('aplica descuento antes del impuesto agregado', () {
    final preview = ProductTaxPreviewCalculator.calculate(
      price: 118,
      discountAmount: 18,
      companyTaxEnabled: true,
      companyPricesIncludeTax: false,
      companyDefaultTaxRate: 0.18,
    );

    expect(preview.baseAmount, 100);
    expect(preview.taxAmount, 18);
    expect(preview.finalAmount, 118);
  });

  test('aplica descuento antes de extraer impuesto incluido', () {
    final preview = ProductTaxPreviewCalculator.calculate(
      price: 118,
      discountAmount: 18,
      companyTaxEnabled: true,
      companyPricesIncludeTax: true,
      companyDefaultTaxRate: 0.18,
    );

    expect(preview.baseAmount, 84.75);
    expect(preview.taxAmount, 15.25);
    expect(preview.finalAmount, 100);
  });
}
