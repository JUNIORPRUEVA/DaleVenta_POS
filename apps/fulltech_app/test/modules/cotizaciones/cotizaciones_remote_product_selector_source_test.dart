import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/modules/cotizaciones/cotizaciones_screen.dart',
    ).readAsStringSync();
  });

  test(
    'Cotizaciones usa ProductSearchController para selector interactivo',
    () {
      expect(
        source,
        contains('late final ProductSearchController _productSearch'),
      );
      expect(source, contains('_productSearch.loadInitial()'));
      expect(source, contains('_productSearch.loadMore()'));
      expect(source, contains('_productSearch.setQuery(_searchCtrl.text)'));
      expect(source, contains('_productSearch.findByCode(code)'));
      expect(source, contains("'categories'"));
    },
  );

  test('Cotizaciones no usa fetchProducts completo en carga ni barcode', () {
    final loadProducts = _methodBody(source, '_loadProducts');
    final barcode = _methodBody(source, '_resolveProductByBarcode');

    expect(loadProducts, isNot(contains('.fetchProducts(')));
    expect(barcode, isNot(contains('.fetchProducts(')));
    expect(loadProducts, isNot(contains('loadAllProductPages')));
    expect(barcode, isNot(contains('loadAllProductPages')));
  });

  test('Cotizaciones conserva fallback offline explícito y avisado', () {
    expect(source, contains('offlineSnapshot: ()'));
    expect(
      source,
      contains(
        'Sin conexión: mostrando productos guardados en este dispositivo',
      ),
    );
  });
}

String _methodBody(String source, String methodName) {
  final signature = source.indexOf(methodName);
  expect(signature, isNonNegative, reason: 'No se encontró $methodName');
  final open = source.indexOf('{', signature);
  expect(open, isNonNegative, reason: 'No se encontró cuerpo de $methodName');

  var depth = 0;
  for (var index = open; index < source.length; index += 1) {
    final char = source[index];
    if (char == '{') depth += 1;
    if (char == '}') depth -= 1;
    if (depth == 0) {
      return source.substring(open, index + 1);
    }
  }
  fail('No se pudo cerrar el cuerpo de $methodName');
}
