class ProductTaxPreview {
  const ProductTaxPreview({
    required this.taxEnabled,
    required this.taxable,
    required this.exempt,
    required this.priceIncludesTax,
    required this.inputPrice,
    required this.baseAmount,
    required this.taxAmount,
    required this.exemptAmount,
    required this.finalAmount,
    required this.rate,
  });

  final bool taxEnabled;
  final bool taxable;
  final bool exempt;
  final bool priceIncludesTax;
  final double inputPrice;
  final double baseAmount;
  final double taxAmount;
  final double exemptAmount;
  final double finalAmount;
  final double rate;

  String get mode => !taxEnabled || exempt
      ? 'NO_TAX'
      : priceIncludesTax
      ? 'TAX_INCLUDED'
      : 'TAX_ADDED';
}

class ProductTaxPreviewCalculator {
  const ProductTaxPreviewCalculator._();

  static ProductTaxPreview calculate({
    required double price,
    required bool companyTaxEnabled,
    required bool companyPricesIncludeTax,
    required double companyDefaultTaxRate,
    double quantity = 1,
    double discountAmount = 0,
    String taxTreatment = 'INHERIT',
    double? taxRate,
    String? taxPriceMode,
  }) {
    final qty = quantity <= 0 ? 1 : quantity;
    final gross = (price < 0 ? 0.0 : price) * qty;
    final discount =
        (discountAmount < 0
                ? 0.0
                : discountAmount > gross
                ? gross
                : discountAmount)
            .toDouble();
    final input = _roundMoney(gross - discount);
    if (!companyTaxEnabled) {
      return _noTax(input, taxEnabled: false);
    }

    final treatment = taxTreatment.trim().toUpperCase();
    if (treatment == 'EXEMPT') {
      return _noTax(input, taxEnabled: true);
    }

    final effectiveRate = taxRate ?? companyDefaultTaxRate;
    if (effectiveRate <= 0) {
      return _noTax(input, taxEnabled: true);
    }

    final priceMode = (taxPriceMode ?? '').trim().toUpperCase();
    final includesTax = priceMode == 'TAX_INCLUDED'
        ? true
        : priceMode == 'TAX_ADDED'
        ? false
        : companyPricesIncludeTax;

    if (includesTax) {
      final base = _roundMoney(input / (1 + effectiveRate));
      final tax = _roundMoney(input - base);
      return ProductTaxPreview(
        taxEnabled: true,
        taxable: true,
        exempt: false,
        priceIncludesTax: true,
        inputPrice: input,
        baseAmount: base,
        taxAmount: tax,
        exemptAmount: 0,
        finalAmount: input,
        rate: effectiveRate,
      );
    }

    final tax = _roundMoney(input * effectiveRate);
    return ProductTaxPreview(
      taxEnabled: true,
      taxable: true,
      exempt: false,
      priceIncludesTax: false,
      inputPrice: input,
      baseAmount: input,
      taxAmount: tax,
      exemptAmount: 0,
      finalAmount: _roundMoney(input + tax),
      rate: effectiveRate,
    );
  }

  static ProductTaxPreview _noTax(double price, {required bool taxEnabled}) {
    return ProductTaxPreview(
      taxEnabled: taxEnabled,
      taxable: false,
      exempt: true,
      priceIncludesTax: false,
      inputPrice: price,
      baseAmount: 0,
      taxAmount: 0,
      exemptAmount: price,
      finalAmount: price,
      rate: 0,
    );
  }

  static double _roundMoney(double value) => (value * 100).round() / 100;
}
