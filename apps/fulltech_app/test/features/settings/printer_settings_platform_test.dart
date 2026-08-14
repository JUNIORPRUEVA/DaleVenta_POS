import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/printing/models/models.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_repository.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/features/settings/ui/printer_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePrintingPlatformResolver extends PrintingPlatformResolver {
  const _FakePrintingPlatformResolver(this._platform);

  final PrintingPlatform _platform;

  @override
  PrintingPlatform get platform => _platform;
}

class _FakeMobilePrinterSettingsRepository
    extends MobilePrinterSettingsRepository {
  _FakeMobilePrinterSettingsRepository()
    : _settings = const MobilePrinterSettingsModel(
        companyScope: 'test',
        connectionType: MobilePrinterConnectionType.systemPrinter,
      ),
      super(companyScope: 'test');

  MobilePrinterSettingsModel _settings;

  @override
  Future<MobilePrinterSettingsModel> getOrCreate() async => _settings;

  @override
  Future<void> update(MobilePrinterSettingsModel settings) async {
    _settings = settings.copyWith(companyScope: companyScope);
  }

  @override
  Future<void> reset() async {
    _settings = const MobilePrinterSettingsModel(companyScope: 'test');
  }
}

class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  PrinterSettingsModel _settings = const PrinterSettingsModel();

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

Future<void> _pump(
  WidgetTester tester,
  PrintingPlatform platform, {
  Size size = const Size(390, 844),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        printingPlatformResolverProvider.overrideWithValue(
          _FakePrintingPlatformResolver(platform),
        ),
        mobilePrinterSettingsRepositoryProvider.overrideWithValue(
          _FakeMobilePrinterSettingsRepository(),
        ),
        printerSettingsRepositoryProvider.overrideWithValue(
          _FakePrinterSettingsRepository(),
        ),
        unifiedTicketPrinterProvider.overrideWith(_FakeUnifiedTicketPrinter.new),
      ],
      child: const MaterialApp(home: PrinterSettingsPage(embedded: true)),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('mobile device displays MobilePrinterSettingsView', (
    tester,
  ) async {
    await _pump(tester, PrintingPlatform.android);

    expect(find.byType(MobilePrinterSettingsView), findsOneWidget);
    expect(find.byType(WindowsPrinterSettingsView), findsNothing);
    expect(
      find.byType(DropdownButtonFormField<MobilePrinterConnectionType>),
      findsOneWidget,
    );
  });

  testWidgets('Windows displays WindowsPrinterSettingsView', (tester) async {
    await _pump(tester, PrintingPlatform.windows, size: const Size(1366, 768));

    expect(find.byType(WindowsPrinterSettingsView), findsOneWidget);
    expect(find.byType(MobilePrinterSettingsView), findsNothing);
  });

  testWidgets('mobile printer settings do not render Windows-only controls', (
    tester,
  ) async {
    await _pump(tester, PrintingPlatform.ios);

    expect(find.text('Usar dialogo del sistema'), findsNothing);
    expect(
      find.byType(DropdownButtonFormField<MobilePrinterConnectionType>),
      findsOneWidget,
    );
    expect(
      find.textContaining('Bluetooth directo funciona en Android'),
      findsOneWidget,
    );
  });
}
