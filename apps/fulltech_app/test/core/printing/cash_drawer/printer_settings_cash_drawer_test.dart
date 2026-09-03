import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrinterSettingsModel · autoOpenCashDrawer', () {
    test('defaults to OFF (safe/backward compatible)', () {
      const model = PrinterSettingsModel();
      expect(model.autoOpenCashDrawer, isFalse);
    });

    test('copyWith keeps the previous value', () {
      const model = PrinterSettingsModel(autoOpenCashDrawer: true);
      final updated = model.copyWith(autoPrintOnPayment: false);
      expect(updated.autoOpenCashDrawer, isTrue);
    });

    test('copyWith toggles the value', () {
      const model = PrinterSettingsModel();
      expect(model.copyWith(autoOpenCashDrawer: true).autoOpenCashDrawer,
          isTrue);
    });

    test('toMap/fromMap round-trip preserves the value', () {
      const model = PrinterSettingsModel(
        selectedPrinterName: 'POS-80',
        autoOpenCashDrawer: true,
      );
      final restored = PrinterSettingsModel.fromMap(model.toMap());
      expect(restored.autoOpenCashDrawer, isTrue);
      expect(restored.selectedPrinterName, 'POS-80');
    });

    test('fromMap treats missing/legacy rows as OFF', () {
      final restored = PrinterSettingsModel.fromMap(const {
        'selectedPrinterName': 'POS-80',
      });
      expect(restored.autoOpenCashDrawer, isFalse);
    });
  });
}
