import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'keeps device printer global and receipt identity per company',
    () async {
      final dbName =
          'printer_tenant_${DateTime.now().microsecondsSinceEpoch}.db';
      final companyA = PrinterSettingsRepository(
        companyId: 'company-a',
        databaseFileName: dbName,
      );
      final companyB = PrinterSettingsRepository(
        companyId: 'company-b',
        databaseFileName: dbName,
      );

      await companyA.updateSettings(
        const PrinterSettingsModel(
          selectedPrinterName: 'EPSON TM-T20',
          headerBusinessName: 'Empresa A',
          headerRnc: '101',
          footerMessage: 'Gracias A',
          showItbis: false,
        ),
      );
      await companyB.updateSettings(
        const PrinterSettingsModel(
          selectedPrinterName: 'EPSON TM-T20',
          headerBusinessName: 'Empresa B',
          headerRnc: '202',
          footerMessage: 'Gracias B',
          showItbis: true,
        ),
      );

      final settingsA = await companyA.getOrCreate();
      final settingsB = await companyB.getOrCreate();

      expect(settingsA.selectedPrinterName, 'EPSON TM-T20');
      expect(settingsB.selectedPrinterName, 'EPSON TM-T20');
      expect(settingsA.headerBusinessName, 'Empresa A');
      expect(settingsB.headerBusinessName, 'Empresa B');
      expect(settingsA.headerRnc, '101');
      expect(settingsB.headerRnc, '202');
      expect(settingsA.showItbis, isFalse);
      expect(settingsB.showItbis, isTrue);
    },
  );
}
