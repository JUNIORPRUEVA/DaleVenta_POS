import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/cash_drawer/cash_drawer_command.dart';
import 'package:daleventa_pos/core/printing/cash_drawer/cash_drawer_service.dart';
import 'package:daleventa_pos/core/printing/mobile_print_service.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/printing/raw_printer_transport.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/mobile_printer_settings_repository.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('CashDrawerService · testOpenDrawer', () {
    test(
      'Windows: sends ONLY the kick pulse once, never a receipt',
      () async {
        final raw = _RecordingRawTransport();
        final container = _windowsContainer(
          settings: const PrinterSettingsModel(
            selectedPrinterName: 'POS-80',
            autoOpenCashDrawer: true,
          ),
          raw: raw,
        );
        addTearDown(container.dispose);

        final result = await container
            .read(cashDrawerServiceProvider)
            .testOpenDrawer();

        expect(result.success, isTrue);
        expect(result.skipped, isFalse);
        expect(raw.calls, hasLength(1));
        expect(raw.calls.single.printerName, 'POS-80');
        expect(raw.calls.single.copies, 1);
        expect(raw.calls.single.bytes, CashDrawerCommand.pulseBytes());
        // Única llamada → nunca se imprime ticket ni se duplica el pulso.
        expect(raw.calls, hasLength(1));
      },
    );

    test('Windows: no configured printer -> friendly error, no transport call',
        () async {
      final raw = _RecordingRawTransport();
      final container = _windowsContainer(
        settings: const PrinterSettingsModel(),
        raw: raw,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .testOpenDrawer();

      expect(result.success, isFalse);
      expect(result.title, 'Configura una impresora');
      expect(raw.calls, isEmpty);
    });

    test('Windows: transport failure -> friendly error (no raw exception)',
        () async {
      final raw = _RecordingRawTransport(
        error: const RawPrinterException('RAW boom code 0x00000005'),
      );
      final container = _windowsContainer(
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'POS-80',
        ),
        raw: raw,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .testOpenDrawer();

      expect(result.success, isFalse);
      expect(result.shouldWarn, isTrue);
      expect(result.title, 'No se pudo abrir');
      expect(result.message, isNot(contains('RAW')));
      expect(result.message, isNot(contains('Exception')));
      expect(result.message, isNot(contains('0x')));
    });

    test('Web: reports unsupported, never crashes and sends nothing',
        () async {
      final raw = _RecordingRawTransport();
      final container = _webContainer(raw: raw);
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .testOpenDrawer();

      expect(result.success, isFalse);
      expect(result.unsupported, isTrue);
      expect(raw.calls, isEmpty);
    });

    test('Android network: sends drawer pulse through mobile transport',
        () async {
      final mobileRaw = _RecordingRawTransport();
      final mobileService = _FakeMobilePrintService(
        result: const MobilePrintServiceResult(
          success: true,
          message: 'Orden de apertura de caja enviada por LAN.',
        ),
      );
      final container = _androidContainer(
        mobileSettings: const MobilePrinterSettingsModel(
          printingEnabled: true,
          connectionType: MobilePrinterConnectionType.network,
          networkIp: '192.168.1.50',
          networkPort: 9100,
        ),
        mobileService: mobileService,
        windowsRaw: mobileRaw,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .testOpenDrawer();

      expect(result.success, isTrue);
      expect(mobileService.sendDrawerPulseCalls, 1);
      // El transporte Windows nunca se toca desde Android.
      expect(mobileRaw.calls, isEmpty);
    });

    test('Android pdfOnly/systemPrinter -> unsupported friendly message',
        () async {
      final mobileService = _FakeMobilePrintService();
      final container = _androidContainer(
        mobileSettings: const MobilePrinterSettingsModel(
          printingEnabled: true,
          connectionType: MobilePrinterConnectionType.pdfOnly,
        ),
        mobileService: mobileService,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .testOpenDrawer();

      expect(result.success, isFalse);
      expect(result.unsupported, isTrue);
      expect(mobileService.sendDrawerPulseCalls, 0);
    });
  });

  group('CashDrawerService · automatic opening', () {
    test('disabled -> skipped, never opens drawer (print does nothing)',
        () async {
      final raw = _RecordingRawTransport();
      final container = _windowsContainer(
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'POS-80',
          autoOpenCashDrawer: false,
        ),
        raw: raw,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .openDrawerAfterEligibleSalePrint(
            sale: _cashSale(),
          );

      expect(result.success, isFalse);
      expect(result.skipped, isTrue);
      expect(raw.calls, isEmpty);
    });

    test('enabled + eligible cash sale -> exactly one drawer command', () async {
      final raw = _RecordingRawTransport();
      final container = _windowsContainer(
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'POS-80',
          autoOpenCashDrawer: true,
        ),
        raw: raw,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .openDrawerAfterEligibleSalePrint(
            sale: _cashSale(paymentMethod: 'mixed', cashAmount: 40),
          );

      expect(result.success, isTrue);
      expect(raw.calls, hasLength(1));
      expect(raw.calls.single.bytes, CashDrawerCommand.pulseBytes());
    });

    test('enabled but no cash involved -> skipped', () async {
      final raw = _RecordingRawTransport();
      final container = _windowsContainer(
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'POS-80',
          autoOpenCashDrawer: true,
        ),
        raw: raw,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .openDrawerAfterEligibleSalePrint(
            sale: _cashSale(paymentMethod: 'transfer', cashAmount: 0),
          );

      expect(result.success, isFalse);
      expect(result.skipped, isTrue);
      expect(raw.calls, isEmpty);
    });

    test('enabled + cash sale but no printer -> skipped silently', () async {
      final raw = _RecordingRawTransport();
      final container = _windowsContainer(
        settings: const PrinterSettingsModel(autoOpenCashDrawer: true),
        raw: raw,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .openDrawerAfterEligibleSalePrint(
            sale: _cashSale(),
          );

      expect(result.skipped, isTrue);
      expect(raw.calls, isEmpty);
    });

    test(
      'reprint (isCopy) never opens the drawer even when enabled + cash',
      () async {
        final raw = _RecordingRawTransport();
        final container = _windowsContainer(
          settings: const PrinterSettingsModel(
            selectedPrinterName: 'POS-80',
            autoOpenCashDrawer: true,
          ),
          raw: raw,
        );
        addTearDown(container.dispose);

        final result = await container
            .read(cashDrawerServiceProvider)
            .openDrawerAfterEligibleSalePrint(
              sale: _cashSale(),
              isCopy: true,
            );

        expect(result.success, isFalse);
        expect(result.skipped, isTrue);
        expect(raw.calls, isEmpty);
      },
    );

    test(
      'drawer failure does NOT invalidate the completed sale (professional '
      'warning)', () async {
        final raw = _RecordingRawTransport(
          error: const RawPrinterException('printer offline'),
        );
        final container = _windowsContainer(
          settings: const PrinterSettingsModel(
            selectedPrinterName: 'POS-80',
            autoOpenCashDrawer: true,
          ),
          raw: raw,
        );
        addTearDown(container.dispose);

        final result = await container
            .read(cashDrawerServiceProvider)
            .openDrawerAfterEligibleSalePrint(
              sale: _cashSale(),
            );

        // El pulso se intentó (no skipped) pero falló -> warning accionable.
        expect(result.success, isFalse);
        expect(result.shouldWarn, isTrue);
        expect(result.message, contains('La venta se completó'));
        expect(
          result.message,
          contains('no fue posible abrir la caja registradora'),
        );
        expect(raw.calls, hasLength(1));
      },
    );

    test('mobile: automatic opening handled by "Abrir gaveta", no double kick',
        () async {
      final mobileService = _FakeMobilePrintService();
      final container = _androidContainer(
        mobileSettings: const MobilePrinterSettingsModel(
          printingEnabled: true,
          connectionType: MobilePrinterConnectionType.bluetooth,
        ),
        mobileService: mobileService,
      );
      addTearDown(container.dispose);

      final result = await container
          .read(cashDrawerServiceProvider)
          .openDrawerAfterEligibleSalePrint(sale: _cashSale());

      expect(result.skipped, isTrue);
      expect(mobileService.sendDrawerPulseCalls, 0);
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SaleModel _cashSale({
  String paymentMethod = 'cash',
  double cashAmount = 100,
}) {
  return SaleModel(
    id: 'sale-81472316',
    userId: 'u1',
    userName: 'Cajero Uno',
    customerId: null,
    customerName: null,
    customerPhone: null,
    saleDate: DateTime(2026, 8, 20, 19, 30),
    note: null,
    totalSold: cashAmount,
    totalCost: 50,
    totalProfit: cashAmount - 50,
    commissionAmount: 0,
    paymentMethod: paymentMethod,
    paymentCashAmount: cashAmount,
    paymentTransferAmount: paymentMethod == 'transfer' ? cashAmount : 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    items: const <SaleItemModel>[],
  );
}

ProviderContainer _windowsContainer({
  required PrinterSettingsModel settings,
  required _RecordingRawTransport raw,
}) {
  return ProviderContainer(
    overrides: [
      printerSettingsRepositoryProvider.overrideWith(
        (_) => _FakePrinterSettingsRepository(settings),
      ),
      printingPlatformResolverProvider.overrideWithValue(
        const _FakePrintingPlatformResolver(PrintingPlatform.windows),
      ),
      cashDrawerServiceProvider.overrideWith(
        (ref) => CashDrawerService(
          ref,
          windowsRawPrinterTransport: raw,
          kickTimeout: const Duration(milliseconds: 200),
        ),
      ),
    ],
  );
}

ProviderContainer _webContainer({required _RecordingRawTransport raw}) {
  return ProviderContainer(
    overrides: [
      printingPlatformResolverProvider.overrideWithValue(
        const _FakePrintingPlatformResolver(PrintingPlatform.web),
      ),
      cashDrawerServiceProvider.overrideWith(
        (ref) => CashDrawerService(
          ref,
          windowsRawPrinterTransport: raw,
        ),
      ),
    ],
  );
}

ProviderContainer _androidContainer({
  required MobilePrinterSettingsModel mobileSettings,
  required _FakeMobilePrintService mobileService,
  _RecordingRawTransport? windowsRaw,
}) {
  return ProviderContainer(
    overrides: [
      mobilePrinterSettingsRepositoryProvider.overrideWith(
        (_) => _FakeMobilePrinterSettingsRepository(mobileSettings),
      ),
      mobilePrintServiceProvider.overrideWithValue(mobileService),
      printingPlatformResolverProvider.overrideWithValue(
        const _FakePrintingPlatformResolver(PrintingPlatform.android),
      ),
      cashDrawerServiceProvider.overrideWith(
        (ref) => CashDrawerService(
          ref,
          windowsRawPrinterTransport:
              windowsRaw ?? _RecordingRawTransport(),
        ),
      ),
    ],
  );
}

class _FakePrintingPlatformResolver extends PrintingPlatformResolver {
  const _FakePrintingPlatformResolver(this.value);
  final PrintingPlatform value;

  @override
  PrintingPlatform get platform => value;
}

class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  _FakePrinterSettingsRepository(this.settings);
  final PrinterSettingsModel settings;

  @override
  Future<PrinterSettingsModel> getOrCreate() async => settings;
}

class _FakeMobilePrinterSettingsRepository
    extends MobilePrinterSettingsRepository {
  _FakeMobilePrinterSettingsRepository(this.settings) : super(companyScope: 'test');
  final MobilePrinterSettingsModel settings;

  @override
  Future<MobilePrinterSettingsModel> getOrCreate() async => settings;
}

class _FakeMobilePrintService extends MobilePrintService {
  _FakeMobilePrintService({
    this.result,
  }) : super(_FakeMobilePrinterSettingsRepository(const MobilePrinterSettingsModel()));

  final MobilePrintServiceResult? result;
  int sendDrawerPulseCalls = 0;

  @override
  Future<MobilePrintServiceResult> sendDrawerPulse() async {
    sendDrawerPulseCalls++;
    return result ??
        const MobilePrintServiceResult(
          success: true,
          message: 'Orden de apertura de caja enviada.',
        );
  }
}

class _RecordingRawTransport implements RawPrinterTransport {
  _RecordingRawTransport({this.error});

  final RawPrinterException? error;
  final calls = <_RawCall>[];

  @override
  Future<RawPrintResult> printRaw({
    required String printerName,
    required Uint8List bytes,
    String documentName = 'FullPOS ESC/POS Ticket',
    int copies = 1,
  }) async {
    calls.add(
      _RawCall(
        printerName: printerName,
        bytes: Uint8List.fromList(bytes),
        documentName: documentName,
        copies: copies,
      ),
    );
    final error = this.error;
    if (error != null) throw error;
    return RawPrintResult(
      success: true,
      message: 'RAW ok.',
      printerName: printerName,
      bytesWritten: bytes.length,
      datatype: 'RAW',
    );
  }
}

class _RawCall {
  const _RawCall({
    required this.printerName,
    required this.bytes,
    required this.documentName,
    required this.copies,
  });

  final String printerName;
  final Uint8List bytes;
  final String documentName;
  final int copies;
}
