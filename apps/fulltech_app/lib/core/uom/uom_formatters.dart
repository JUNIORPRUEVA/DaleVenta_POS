import '../models/product_model.dart';

double? parseDecimalInput(String raw) {
  var value = raw
      .trim()
      .replaceAll('\ufeff', '')
      .replaceAll('RD\$', '')
      .replaceAll('rd\$', '')
      .replaceAll(' ', '');
  if (value.isEmpty) return null;
  if (value.contains(',') && value.contains('.')) {
    value = value.replaceAll(',', '');
  } else {
    value = value.replaceAll(',', '.');
  }
  return double.tryParse(value);
}

String formatQuantityValue(
  num? value, {
  UnitOfMeasureModel unit = UnitOfMeasureModel.unit,
}) {
  if (value == null) {
    return '0';
  }
  final number = value.toDouble();
  if (!unit.allowDecimals || unit.precision <= 0) {
    return number.toStringAsFixed(0);
  }
  return number
      .toStringAsFixed(unit.precision)
      .replaceFirst(RegExp(r'\.?0+$'), '');
}

String formatQuantityWithUnit(
  num? value, {
  required UnitOfMeasureModel unit,
  bool includeUnitForUnit = false,
}) {
  final quantity = formatQuantityValue(value, unit: unit);
  if (!includeUnitForUnit && unit.isUnit) return quantity;
  return '$quantity ${unit.symbol}';
}

String formatQuantityForFeature(
  num? value, {
  required UnitOfMeasureModel unit,
  required bool showMeasurementUnit,
  bool includeUnitForUnit = false,
}) {
  if (!showMeasurementUnit) return formatQuantityValue(value, unit: unit);
  return formatQuantityWithUnit(
    value,
    unit: unit,
    includeUnitForUnit: includeUnitForUnit,
  );
}

String formatStockLabel(ProductModel product, {bool compact = false}) {
  final stock = product.stock;
  if (stock == null) return compact ? '--' : 'Disp. --';
  if (stock <= 0) return compact ? '0' : 'Sin stock';
  final value = formatQuantityWithUnit(
    stock,
    unit: product.unitOfMeasure,
    includeUnitForUnit: false,
  );
  return compact ? value : 'Disp. $value';
}

String? validateQuantityForUnit(
  num quantity, {
  required UnitOfMeasureModel unit,
  String label = 'La cantidad',
  bool allowZero = false,
}) {
  final value = quantity.toDouble();
  if (allowZero ? value < 0 : value <= 0) {
    return '$label debe ser mayor que cero.';
  }
  if (!unit.allowDecimals && value % 1 != 0) {
    return '$label debe ser entera para ${unit.name}.';
  }
  final text = value.toString();
  final decimals = text.contains('.')
      ? text.split('.').last.replaceFirst(RegExp(r'0+$'), '').length
      : 0;
  if (decimals > unit.precision) {
    return '$label admite máximo ${unit.precision} decimales.';
  }
  return null;
}

/// Redondea un valor a la precisión permitida por la unidad de medida.
///
/// Devuelve un [double] cuya representación decimal más corta no excede la
/// precisión de la unidad. Evita que artefactos de punto flotante
/// (p. ej. `2.3500000000000005` al restar 5.5 - 3.15) lleguen al backend al
/// ajustar stock de productos con unidades decimales (Libra, Yarda, Kilogramo,
/// Metro...), respetando las reglas de precisión ya existentes.
double quantizeQuantityToUnit(num value, UnitOfMeasureModel unit) {
  if (!unit.allowDecimals || unit.precision <= 0) {
    return value.toDouble().roundToDouble();
  }
  return double.parse(value.toDouble().toStringAsFixed(unit.precision));
}

bool quantityExceedsStock(num quantity, ProductModel product) {
  if (product.itemType == 'SERVICE' || !product.trackInventory) return false;
  final stock = product.stock;
  if (stock == null) return false;
  return quantity.toDouble() > stock;
}
