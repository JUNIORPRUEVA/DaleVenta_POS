import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cotizaciones desktop no mantiene panel fiscal lateral fijo', () {
    final source = File(
      'lib/modules/cotizaciones/cotizaciones_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('fiscalPaneWidth')));
    expect(
      source,
      isNot(
        contains(
          RegExp(
            r'Positioned\([\s\S]*?width:\s*fiscalPaneWidth[\s\S]*?_DesktopFiscalInvoicePanel',
          ),
        ),
      ),
    );
    expect(source, contains('Future<void> _openMobileFiscalInvoicePanel'));
    expect(source, contains("barrierLabel: 'Datos fiscales'"));
  });
}
