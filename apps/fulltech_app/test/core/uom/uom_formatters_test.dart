import 'dart:convert';

import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/uom/uom_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const unit = UnitOfMeasureModel.unit;
  const pound = UnitOfMeasureModel(
    id: 'POUND',
    code: 'POUND',
    name: 'Libra',
    symbol: 'lb',
    category: 'WEIGHT',
    allowDecimals: true,
    precision: 3,
  );
  const yard = UnitOfMeasureModel(
    id: 'YARD',
    code: 'YARD',
    name: 'Yarda',
    symbol: 'yd',
    category: 'LENGTH',
    allowDecimals: true,
    precision: 3,
  );

  group('parseDecimalInput', () {
    test('parsea enteros, decimales con punto o coma y miles', () {
      expect(parseDecimalInput('10'), 10);
      expect(parseDecimalInput('2.375'), 2.375);
      expect(parseDecimalInput('2,375'), 2.375);
      expect(parseDecimalInput('1,234.56'), 1234.56);
      expect(parseDecimalInput(''), isNull);
    });
  });

  group('formatQuantityValue / formatQuantityWithUnit', () {
    test('UNIT usa representación entera', () {
      expect(formatQuantityValue(15, unit: unit), '15');
      expect(
        formatQuantityWithUnit(15, unit: unit, includeUnitForUnit: true),
        '15 u',
      );
    });

    test('POUND/YARD formatean con precisión y recortan ceros finales', () {
      expect(
        formatQuantityWithUnit(10, unit: pound, includeUnitForUnit: true),
        '10 lb',
      );
      expect(formatQuantityWithUnit(12.375, unit: pound), '12.375 lb');
      expect(
        formatQuantityWithUnit(25.5, unit: yard, includeUnitForUnit: true),
        '25.5 yd',
      );
      expect(formatQuantityWithUnit(15.500, unit: yard), '15.5 yd');
    });
  });

  group('validateQuantityForUnit', () {
    test('UNIT rechaza decimales y acepta enteros', () {
      expect(validateQuantityForUnit(1.5, unit: unit), isNotNull);
      expect(validateQuantityForUnit(15, unit: unit), isNull);
    });

    test('POUND/YARD aceptan decimales válidos y rechazan exceso', () {
      expect(validateQuantityForUnit(2.375, unit: pound), isNull);
      expect(validateQuantityForUnit(5.5, unit: yard), isNull);
      expect(validateQuantityForUnit(0.5, unit: pound), isNull);
      expect(validateQuantityForUnit(2.3759, unit: pound), isNotNull);
    });
  });

  group('quantizeQuantityToUnit', () {
    test('UNIT cuantiza a entero', () {
      expect(quantizeQuantityToUnit(8.0000001, unit), 8);
      expect(quantizeQuantityToUnit(15.0, unit), 15);
    });

    test('elimina artefactos de punto flotante para unidades medidas', () {
      // 5.5 - 3.15 en IEEE-754 no es exactamente 2.35.
      final rawDelta = 5.5 - 3.15;
      expect(quantizeQuantityToUnit(rawDelta, pound), 2.35);
      expect(jsonEncode(quantizeQuantityToUnit(rawDelta, pound)), '2.35');
    });

    test('10 lb + 2.375 lb y 20 yd + 5.500 yd conservan decimales', () {
      expect(quantizeQuantityToUnit(10 + 2.375, pound), 12.375);
      expect(jsonEncode(quantizeQuantityToUnit(10 + 2.375, pound)), '12.375');

      expect(quantizeQuantityToUnit(20 + 5.5, yard), 25.5);
      expect(jsonEncode(quantizeQuantityToUnit(20 + 5.5, yard)), '25.5');
    });

    test('mantiene sin cambios valores ya limpios', () {
      expect(quantizeQuantityToUnit(12.375, pound), 12.375);
      expect(quantizeQuantityToUnit(0.5, pound), 0.5);
      expect(quantizeQuantityToUnit(2.375, pound), 2.375);
    });
  });
}
