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

class ProductCartTaxLineInput {
  const ProductCartTaxLineInput({
    required this.price,
    required this.quantity,
    this.lineDiscountAmount = 0,
    this.taxTreatment = 'INHERIT',
    this.taxRate,
    this.taxPriceMode,
  });

  final double price;
  final double quantity;
  final double lineDiscountAmount;
  final String taxTreatment;
  final double? taxRate;
  final String? taxPriceMode;
}

class ProductCartTaxLineResult {
  const ProductCartTaxLineResult({
    required this.preview,
    required this.grossAmount,
    required this.lineDiscountAmount,
    required this.generalDiscountAmount,
    required this.discountAmount,
  });

  final ProductTaxPreview preview;
  final double grossAmount;
  final double lineDiscountAmount;
  final double generalDiscountAmount;
  final double discountAmount;
}

class ProductCartTaxSummary {
  const ProductCartTaxSummary({
    required this.lines,
    required this.subtotal,
    required this.discountAmount,
    required this.generalDiscountAmount,
    required this.taxableBase,
    required this.taxAmount,
    required this.exemptAmount,
    required this.total,
    required this.taxEnabled,
  });

  final List<ProductCartTaxLineResult> lines;
  final double subtotal;
  final double discountAmount;
  final double generalDiscountAmount;
  final double taxableBase;
  final double taxAmount;
  final double exemptAmount;
  final double total;
  final bool taxEnabled;
}

class ProductTaxPreviewCalculator {
  const ProductTaxPreviewCalculator._();

  static ProductCartTaxSummary calculateCart({
    required List<ProductCartTaxLineInput> lines,
    required bool companyTaxEnabled,
    required bool companyPricesIncludeTax,
    required double companyDefaultTaxRate,
    double globalDiscountAmount = 0,
  }) {
    final grossAmounts = <double>[];
    final lineDiscounts = <double>[];
    final eligibleNetAmounts = <double>[];
    for (final line in lines) {
      final gross = _roundMoney(
        (line.price < 0 ? 0.0 : line.price) *
            (line.quantity <= 0 ? 1 : line.quantity),
      );
      final lineDiscount = _roundMoney(
        line.lineDiscountAmount < 0
            ? 0
            : line.lineDiscountAmount > gross
            ? gross
            : line.lineDiscountAmount,
      );
      grossAmounts.add(gross);
      lineDiscounts.add(lineDiscount);
      eligibleNetAmounts.add(_roundMoney(gross - lineDiscount));
    }

    final subtotal = _roundMoney(
      grossAmounts.fold<double>(0, (sum, value) => sum + value),
    );
    final eligibleSubtotal = _roundMoney(
      eligibleNetAmounts.fold<double>(0, (sum, value) => sum + value),
    );
    final generalDiscount = _roundMoney(
      globalDiscountAmount <= 0
          ? 0
          : globalDiscountAmount > eligibleSubtotal
          ? eligibleSubtotal
          : globalDiscountAmount,
    );
    final generalDiscounts = _allocateProportionalDiscount(
      amounts: eligibleNetAmounts,
      discount: generalDiscount,
    );

    final results = <ProductCartTaxLineResult>[];
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final discount = _roundMoney(
        lineDiscounts[index] + generalDiscounts[index],
      );
      final preview = calculate(
        price: line.price,
        quantity: line.quantity,
        discountAmount: discount,
        companyTaxEnabled: companyTaxEnabled,
        companyPricesIncludeTax: companyPricesIncludeTax,
        companyDefaultTaxRate: companyDefaultTaxRate,
        taxTreatment: line.taxTreatment,
        taxRate: line.taxRate,
        taxPriceMode: line.taxPriceMode,
      );
      results.add(
        ProductCartTaxLineResult(
          preview: preview,
          grossAmount: grossAmounts[index],
          lineDiscountAmount: lineDiscounts[index],
          generalDiscountAmount: generalDiscounts[index],
          discountAmount: discount,
        ),
      );
    }

    return ProductCartTaxSummary(
      lines: results,
      subtotal: subtotal,
      discountAmount: _roundMoney(
        results.fold<double>(0, (sum, line) => sum + line.discountAmount),
      ),
      generalDiscountAmount: _roundMoney(
        results.fold<double>(
          0,
          (sum, line) => sum + line.generalDiscountAmount,
        ),
      ),
      taxableBase: _roundMoney(
        results.fold<double>(0, (sum, line) => sum + line.preview.baseAmount),
      ),
      taxAmount: _roundMoney(
        results.fold<double>(0, (sum, line) => sum + line.preview.taxAmount),
      ),
      exemptAmount: _roundMoney(
        results.fold<double>(0, (sum, line) => sum + line.preview.exemptAmount),
      ),
      total: _roundMoney(
        results.fold<double>(0, (sum, line) => sum + line.preview.finalAmount),
      ),
      taxEnabled: companyTaxEnabled,
    );
  }

  static double generalDiscountAmountFromPercent({
    required List<ProductCartTaxLineInput> lines,
    required double percent,
  }) {
    if (percent <= 0 || lines.isEmpty) return 0;
    final boundedPercent = percent > 100 ? 100 : percent;
    final base = lines.fold<double>(0, (sum, line) {
      final qty = line.quantity <= 0 ? 1 : line.quantity;
      final gross = _roundMoney((line.price < 0 ? 0.0 : line.price) * qty);
      final lineDiscount = _roundMoney(
        line.lineDiscountAmount < 0
            ? 0
            : line.lineDiscountAmount > gross
            ? gross
            : line.lineDiscountAmount,
      );
      return sum + _roundMoney(gross - lineDiscount);
    });
    return _roundMoney(base * boundedPercent / 100);
  }

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

  static List<double> _allocateProportionalDiscount({
    required List<double> amounts,
    required double discount,
  }) {
    final amountCents = amounts
        .map((value) => (_roundMoney(value) * 100).round())
        .toList(growable: false);
    final totalCents = amountCents.fold<int>(0, (sum, value) => sum + value);
    final discountCents = (_roundMoney(discount) * 100).round().clamp(
      0,
      totalCents,
    );
    if (amountCents.isEmpty || totalCents <= 0 || discountCents <= 0) {
      return List<double>.filled(amounts.length, 0);
    }

    final allocations = List<int>.filled(amountCents.length, 0);
    final remainders = <({int index, int remainder})>[];
    var assigned = 0;
    for (var index = 0; index < amountCents.length; index++) {
      final numerator = amountCents[index] * discountCents;
      final base = numerator ~/ totalCents;
      allocations[index] = base.clamp(0, amountCents[index]);
      assigned += allocations[index];
      remainders.add((index: index, remainder: numerator % totalCents));
    }

    remainders.sort((a, b) => b.remainder.compareTo(a.remainder));
    var remaining = discountCents - assigned;
    while (remaining > 0) {
      var changed = false;
      for (final entry in remainders) {
        if (remaining <= 0) break;
        if (allocations[entry.index] >= amountCents[entry.index]) continue;
        allocations[entry.index] += 1;
        remaining -= 1;
        changed = true;
      }
      if (!changed) break;
    }

    return allocations.map((cents) => cents / 100).toList(growable: false);
  }
}
