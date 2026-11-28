/// Presentation only: combine identical electronic subtotal/base rows.
bool combinesElectronicSubtotal({
  required bool electronic,
  required double subtotal,
  required double taxableBase,
  required double exemptAmount,
  required Iterable<double> discounts,
}) =>
    electronic &&
    taxableBase > 0 &&
    exemptAmount == 0 &&
    discounts.every((amount) => amount == 0) &&
    subtotal.toStringAsFixed(2) == taxableBase.toStringAsFixed(2);
