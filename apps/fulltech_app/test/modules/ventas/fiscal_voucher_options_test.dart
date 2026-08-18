import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/modules/ventas/fiscal_voucher_options.dart';

void main() {
  group('fiscal voucher POS options', () {
    test('hides fiscal voucher control when taxes are disabled', () {
      expect(
        shouldShowFiscalVoucherControl(taxEnabled: false, ncfEnabled: true),
        isFalse,
      );
      expect(
        fiscalVoucherOptionsFromConfiguredTypes(
          taxEnabled: false,
          ncfEnabled: true,
          configuredTypes: const ['B01', 'B02'],
        ),
        isEmpty,
      );
    });

    test('hides fiscal voucher control when NCF is disabled', () {
      expect(
        shouldShowFiscalVoucherControl(taxEnabled: true, ncfEnabled: false),
        isFalse,
      );
      expect(
        fiscalVoucherOptionsFromConfiguredTypes(
          taxEnabled: true,
          ncfEnabled: false,
          configuredTypes: const ['B01', 'B02'],
        ),
        isEmpty,
      );
    });

    test('only exposes configured B01 and B02 voucher types', () {
      final options = fiscalVoucherOptionsFromConfiguredTypes(
        taxEnabled: true,
        ncfEnabled: true,
        configuredTypes: const ['B02', 'B99', 'b01'],
      );

      expect(options.map((option) => option.type), ['B01', 'B02']);
    });

    test('resets selected voucher when it is no longer permitted', () {
      final options = fiscalVoucherOptionsFromConfiguredTypes(
        taxEnabled: true,
        ncfEnabled: true,
        configuredTypes: const ['B02'],
      );

      expect(
        shouldResetFiscalVoucherSelection(
          selectedType: 'B01',
          options: options,
        ),
        isTrue,
      );
      expect(
        shouldResetFiscalVoucherSelection(
          selectedType: 'B02',
          options: options,
        ),
        isFalse,
      );
    });

    test('B01 requires a fiscal customer id with at least 9 digits', () {
      expect(isB01FiscalClientValid(null), isFalse);
      expect(isB01FiscalClientValid(''), isFalse);
      expect(isB01FiscalClientValid('12345678'), isFalse);
      expect(isB01FiscalClientValid('101-01010-1'), isTrue);
    });
  });
}
