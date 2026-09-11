import 'package:daleventa_pos/core/printing/cash_drawer/cash_drawer_command.dart';
import 'package:daleventa_pos/core/storage/local_database_path.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
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

  group('PrinterSettingsModel · cashDrawerChannel', () {
    test('defaults to automatic (historical Pin 2 behaviour)', () {
      const model = PrinterSettingsModel();
      expect(model.cashDrawerChannel, CashDrawerChannel.automatic);
      expect(model.cashDrawerChannel.resolvedPin, CashDrawerPin.pin2);
      expect(
        CashDrawerCommand.pulseBytesForChannel(model.cashDrawerChannel),
        CashDrawerCommand.defaultPulseBytes,
      );
    });

    test('copyWith keeps the previous channel', () {
      const model = PrinterSettingsModel(
        cashDrawerChannel: CashDrawerChannel.pin5,
      );
      final updated = model.copyWith(autoOpenCashDrawer: true);
      expect(updated.cashDrawerChannel, CashDrawerChannel.pin5);
    });

    test('copyWith changes the channel', () {
      const model = PrinterSettingsModel();
      final updated =
          model.copyWith(cashDrawerChannel: CashDrawerChannel.pin5);
      expect(updated.cashDrawerChannel, CashDrawerChannel.pin5);
    });

    test('toMap/fromMap round-trip preserves the channel', () {
      const model = PrinterSettingsModel(
        selectedPrinterName: 'SEWOO SLK-TS100',
        autoOpenCashDrawer: true,
        cashDrawerChannel: CashDrawerChannel.pin5,
      );
      final restored = PrinterSettingsModel.fromMap(model.toMap());
      expect(restored.cashDrawerChannel, CashDrawerChannel.pin5);
      expect(restored.autoOpenCashDrawer, isTrue);
    });

    test('legacy rows without the column fall back to automatic', () {
      final restored = PrinterSettingsModel.fromMap(const {
        'selectedPrinterName': 'SEWOO SLK-TS100',
        'autoOpenCashDrawer': 1,
      });
      expect(restored.cashDrawerChannel, CashDrawerChannel.automatic);
      expect(
        CashDrawerCommand.pulseBytesForChannel(restored.cashDrawerChannel),
        [0x1B, 0x70, 0x00, 0x19, 0xFA],
      );
    });

    test('an unknown/corrupted stored value falls back to automatic', () {
      final restored = PrinterSettingsModel.fromMap(const {
        'selectedPrinterName': 'SEWOO SLK-TS100',
        'cashDrawerChannel': 'something-else',
      });
      expect(restored.cashDrawerChannel, CashDrawerChannel.automatic);
    });

    test(
      'persists and recovers channel + auto-open from a real database',
      () async {
        final dbName =
            'printer_cash_drawer_${DateTime.now().microsecondsSinceEpoch}.db';
        final repo = PrinterSettingsRepository(
          companyId: 'company-a',
          databaseFileName: dbName,
        );

        await repo.updateSettings(
          const PrinterSettingsModel(
            selectedPrinterName: 'SEWOO SLK-TS100',
            autoOpenCashDrawer: true,
            cashDrawerChannel: CashDrawerChannel.pin5,
          ),
        );

        // Nueva instancia = simula reinicio de la app (no hay estado en memoria).
        final reopened = PrinterSettingsRepository(
          companyId: 'company-a',
          databaseFileName: dbName,
        );
        final restored = await reopened.getOrCreate();

        expect(restored.selectedPrinterName, 'SEWOO SLK-TS100');
        expect(restored.autoOpenCashDrawer, isTrue);
        expect(restored.cashDrawerChannel, CashDrawerChannel.pin5);
      },
    );

    test(
      'an existing installation without the column keeps working (automatic)',
      () async {
        final dbName =
            'printer_legacy_${DateTime.now().microsecondsSinceEpoch}.db';
        final repo = PrinterSettingsRepository(
          companyId: 'company-a',
          databaseFileName: dbName,
        );
        // Primera lectura crea el esquema con defaults.
        final created = await repo.getOrCreate();
        expect(created.cashDrawerChannel, CashDrawerChannel.automatic);

        final again = await PrinterSettingsRepository(
          companyId: 'company-a',
          databaseFileName: dbName,
        ).getOrCreate();
        expect(again.cashDrawerChannel, CashDrawerChannel.automatic);
        expect(again.autoOpenCashDrawer, isFalse);
      },
    );

    test(
      'LOCAL SETTINGS UPGRADE: legacy schema without the column migrates in '
      'place without losing or resetting configuration',
      () async {
        final dbName =
            'printer_legacy_schema_${DateTime.now().microsecondsSinceEpoch}.db';
        final path = await resolveLocalDatabasePath(dbName);

        // Esquema ANTERIOR al hardening (sin cashDrawerChannel) con un cliente
        // existente que YA tenía impresora, modo y auto-open configurados.
        final legacyDb = await databaseFactory.openDatabase(path);
        await legacyDb.execute('''
          CREATE TABLE printer_settings (
            id INTEGER PRIMARY KEY,
            selectedPrinterName TEXT,
            windowsPrinterMode TEXT NOT NULL DEFAULT 'automatic',
            paperWidthMm INTEGER NOT NULL DEFAULT 80,
            autoOpenCashDrawer INTEGER NOT NULL DEFAULT 0,
            autoCut INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await legacyDb.insert('printer_settings', {
          'id': 1,
          'selectedPrinterName': 'EPSON TM-T20',
          'windowsPrinterMode': 'escPosRaw',
          'paperWidthMm': 58,
          'autoOpenCashDrawer': 1,
          'autoCut': 0,
        });
        await legacyDb.close();

        // La app actualizada abre la MISMA base: migración en sitio.
        final upgraded = await PrinterSettingsRepository(
          companyId: 'company-a',
          databaseFileName: dbName,
        ).getOrCreate();

        // Nueva capacidad con default seguro = comportamiento histórico.
        expect(upgraded.cashDrawerChannel, CashDrawerChannel.automatic);
        expect(
          CashDrawerCommand.pulseBytesForChannel(upgraded.cashDrawerChannel),
          [0x1B, 0x70, 0x00, 0x19, 0xFA],
        );
        // Nada de la configuración del cliente se pierde ni se resetea.
        expect(upgraded.selectedPrinterName, 'EPSON TM-T20');
        expect(upgraded.autoOpenCashDrawer, isTrue);
        expect(upgraded.paperWidthMm, 58);
        expect(upgraded.windowsPrinterMode, WindowsPrinterMode.escPosRaw);
        expect(upgraded.autoCut, isFalse);

        // Idempotente: reabrir la app no pierde ni cambia nada.
        final reopened = await PrinterSettingsRepository(
          companyId: 'company-a',
          databaseFileName: dbName,
        ).getOrCreate();
        expect(reopened.cashDrawerChannel, CashDrawerChannel.automatic);
        expect(reopened.selectedPrinterName, 'EPSON TM-T20');
        expect(reopened.autoOpenCashDrawer, isTrue);
        expect(reopened.paperWidthMm, 58);
        expect(reopened.windowsPrinterMode, WindowsPrinterMode.escPosRaw);
        expect(reopened.autoCut, isFalse);
      },
    );
  });
}
