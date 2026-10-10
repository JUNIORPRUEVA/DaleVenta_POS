import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('historial de cotizaciones no descarga catalogo completo', () {
    final source = File(
      'lib/modules/cotizaciones/cotizaciones_historial_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('fetchProducts(')));
    expect(source, isNot(contains('loadAllProductPages')));
    expect(source, isNot(contains('ventasRepositoryProvider')));
    expect(source, contains('listClients('));
  });
}
