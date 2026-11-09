import 'package:daleventa_pos/modules/ventas/fiscal_voucher_options.dart';
import 'package:flutter_test/flutter_test.dart';

// El motor NCF se retiró: ninguna venta nueva lleva talón B01/B02. Pero las
// ventas históricas SÍ conservan `fiscalVoucherType`, así que la etiqueta debe
// seguir describiéndolas igual y nunca inventar un comprobante.
void main() {
  group('fiscalVoucherLabel conserva el histórico', () {
    test('describe B01 y B02 como se facturaron', () {
      expect(fiscalVoucherLabel('B01'), 'B01 - Credito Fiscal');
      expect(fiscalVoucherLabel('B02'), 'B02 - Consumo');
    });

    test('tolera minúsculas y espacios del dato histórico', () {
      expect(fiscalVoucherLabel(' b01 '), 'B01 - Credito Fiscal');
      expect(fiscalVoucherLabel('b02'), 'B02 - Consumo');
    });

    test('sin comprobante devuelve la etiqueta de "Sin comprobante"', () {
      expect(fiscalVoucherLabel(null), fiscalVoucherNoneLabel);
      expect(fiscalVoucherLabel(''), fiscalVoucherNoneLabel);
      expect(fiscalVoucherLabel('   '), fiscalVoucherNoneLabel);
    });

    test('un valor desconocido se muestra literal, nunca se adivina', () {
      expect(fiscalVoucherLabel('E310000000001'), 'E310000000001');
      expect(fiscalVoucherLabel('B99'), 'B99');
    });
  });

  group('normalizeTaxId (RNC/Cédula)', () {
    test('compara solo dígitos', () {
      expect(normalizeTaxId('133020253'), '133020253');
      expect(normalizeTaxId('1-33-02025-3'), '133020253');
      expect(normalizeTaxId('1 33 02025 3'), '133020253');
    });

    test('vacío o nulo no produce una identidad falsa', () {
      expect(normalizeTaxId(null), '');
      expect(normalizeTaxId(''), '');
      expect(normalizeTaxId('   '), '');
    });

    test('documentos distintos no colapsan al mismo valor', () {
      expect(normalizeTaxId('133020253'), isNot(normalizeTaxId('133020254')));
    });
  });
}
