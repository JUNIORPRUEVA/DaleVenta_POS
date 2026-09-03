import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/printing/models/models.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/features/settings/ui/printer_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePrintingPlatformResolver extends PrintingPlatformResolver {
  const _FakePrintingPlatformResolver();

  @override
  PrintingPlatform get platform => PrintingPlatform.windows;
}

class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  PrinterSettingsModel _settings = const PrinterSettingsModel(
    selectedPrinterName: 'POS-80',
  );

  PrinterSettingsModel get settings => _settings;

  @override
  Future<PrinterSettingsModel?> getSettings() async => _settings;

  @override
  Future<PrinterSettingsModel> getOrCreate() async => _settings;

  @override
  Future<void> updateSettings(PrinterSettingsModel settings) async {
    _settings = settings;
  }
}

class _FakeUnifiedTicketPrinter extends UnifiedTicketPrinter {
  _FakeUnifiedTicketPrinter(super.ref);

  @override
  Future<List<Printer>> getAvailablePrinters() async => const <Printer>[];

  @override
  Future<String> generatePreviewText({TicketData? data}) async =>
      'Ticket de prueba\nTOTAL RD\$ 0.00';
}

void main() {
  testWidgets(
    'Windows settings render the Caja registradora section with toggle and '
    'test button, and the toggle saves autoOpenCashDrawer',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final printerRepository = _FakePrinterSettingsRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            printingPlatformResolverProvider.overrideWithValue(
              const _FakePrintingPlatformResolver(),
            ),
            printerSettingsRepositoryProvider.overrideWithValue(
              printerRepository,
            ),
            unifiedTicketPrinterProvider.overrideWith(
              _FakeUnifiedTicketPrinter.new,
            ),
          ],
          child: const MaterialApp(home: PrinterSettingsPage(embedded: true)),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      // La sección de caja registradora existe y está por defecto OFF.
      expect(find.text('Caja registradora'), findsOneWidget);
      expect(find.text('Abrir caja automáticamente'), findsOneWidget);
      expect(find.text('Probar apertura de caja'), findsOneWidget);
      expect(printerRepository.settings.autoOpenCashDrawer, isFalse);

      // Cambiar el toggle guarda la preferencia.
      final switchRow = find
          .ancestor(
            of: find.text('Abrir caja automáticamente'),
            matching: find.byType(Row),
          )
          .first;
      expect(switchRow, findsOneWidget);
      final drawerSwitch = find.descendant(
        of: switchRow,
        matching: find.byType(Switch),
      );
      expect(drawerSwitch, findsOneWidget);
      await tester.tap(drawerSwitch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(printerRepository.settings.autoOpenCashDrawer, isTrue);
    },
  );
}
