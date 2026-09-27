import 'package:daleventa_pos/features/contabilidad/contabilidad_init.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  setUp(() {
    Intl.defaultLocale = 'C.UTF-8';
  });

  test('ensureContabilidadLocale ignores invalid browser locale values', () async {
    final localeFuture = ensureContabilidadLocale(locale: 'C.UTF-8');

    expect(Intl.defaultLocale, 'es_DO');
    expect(DateFormat('yyyy-MM-dd').format(DateTime(2026, 9, 27)), '2026-09-27');

    await localeFuture;

    expect(Intl.defaultLocale, 'es_DO');
  });
}
