import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/cash_drawer/cash_drawer_command.dart';
import 'package:daleventa_pos/core/printing/cash_drawer/cash_drawer_service.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/printing/raw_printer_transport.dart';
import 'package:daleventa_pos/core/printing/thermal_printer_service.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'drawer disabled: eligible cash print does NOT trigger any drawer command',
    () async {
      final ticketRaw = _RecordingRawTransport();
      final drawerRaw = _RecordingRawTransport();
      final container = _container(
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'POS-80',
          copies: 1,
          autoCut: true,
          windowsPrinterMode: WindowsPrinterMode.escPosRaw,
          autoOpenCashDrawer: false,
        ),
        ticketRaw: ticketRaw,
        drawerRaw: drawerRaw,
      );
      addTearDown(container.dispose);
      final printer = container.read(unifiedTicketPrinterProvider);

      final result = await printer.printSaleTicket(sale: _cashSale());

      expect(result.success, isTrue);
      expect(result.warning, isNull);
      expect(ticketRaw.calls, hasLength(1)); // ticket printed normally
      expect(drawerRaw.calls, isEmpty); // drawer untouched
    },
  );

  test(
    'drawer enabled + eligible cash print -> exactly one drawer command '
    'after a successful receipt',
    () async {
      final ticketRaw = _RecordingRawTransport();
      final drawerRaw = _RecordingRawTransport();
      final container = _container(
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'POS-80',
          copies: 2,
          autoCut: true,
          windowsPrinterMode: WindowsPrinterMode.escPosRaw,
          autoOpenCashDrawer: true,
        ),
        ticketRaw: ticketRaw,
        drawerRaw: drawerRaw,
      );
      addTearDown(container.dispose);
      final printer = container.read(unifiedTicketPrinterProvider);

      final result = await printer.printSaleTicket(sale: _cashSale());

      expect(result.success, isTrue);
      expect(result.warning, isNull);
      expect(ticketRaw.calls, hasLength(1)); // one print action (copies inside)
      expect(drawerRaw.calls, hasLength(1)); // one drawer command, no duplicates
      expect(drawerRaw.calls.single.bytes, CashDrawerCommand.pulseBytes());
    },
  );

  test('failed print never opens the drawer (success gate)', () async {
    final ticketRaw = _RecordingRawTransport(
      error: const RawPrinterException('printer offline'),
    );
    final drawerRaw = _RecordingRawTransport();
    final container = _container(
      settings: const PrinterSettingsModel(
        selectedPrinterName: 'POS-80',
        copies: 1,
        autoCut: true,
        windowsPrinterMode: WindowsPrinterMode.escPosRaw,
        autoOpenCashDrawer: true,
      ),
      ticketRaw: ticketRaw,
      drawerRaw: drawerRaw,
    );
    addTearDown(container.dispose);
    final printer = container.read(unifiedTicketPrinterProvider);

    final result = await printer.printSaleTicket(sale: _cashSale());

    expect(result.success, isFalse);
    expect(drawerRaw.calls, isEmpty);
  });

  test('reprint never opens the drawer', () async {
    final ticketRaw = _RecordingRawTransport();
    final drawerRaw = _RecordingRawTransport();
    final container = _container(
      settings: const PrinterSettingsModel(
        selectedPrinterName: 'POS-80',
        copies: 1,
        autoCut: true,
        windowsPrinterMode: WindowsPrinterMode.escPosRaw,
        autoOpenCashDrawer: true,
      ),
      ticketRaw: ticketRaw,
      drawerRaw: drawerRaw,
    );
    addTearDown(container.dispose);
    final printer = container.read(unifiedTicketPrinterProvider);

    final result = await printer.reprintSale(sale: _cashSale());

    expect(result.success, isTrue);
    expect(ticketRaw.calls, hasLength(1)); // reprint still prints the document
    expect(drawerRaw.calls, isEmpty); // but never opens the drawer
  });

  test(
    'drawer failure does NOT roll back the completed sale: result stays '
    'successful and carries only a professional warning',
    () async {
      final ticketRaw = _RecordingRawTransport();
      final drawerRaw = _RecordingRawTransport(
        error: const RawPrinterException('RAW drawer failed'),
      );
      final container = _container(
        settings: const PrinterSettingsModel(
          selectedPrinterName: 'POS-80',
          copies: 1,
          autoCut: true,
          windowsPrinterMode: WindowsPrinterMode.escPosRaw,
          autoOpenCashDrawer: true,
        ),
        ticketRaw: ticketRaw,
        drawerRaw: drawerRaw,
      );
      addTearDown(container.dispose);
      final printer = container.read(unifiedTicketPrinterProvider);

      final result = await printer.printSaleTicket(sale: _cashSale());

      // La venta y su impresión siguen siendo exitosas.
      expect(result.success, isTrue);
      expect(result.warning, isNotNull);
      expect(result.warning, contains('La venta se completó'));
      expect(ticketRaw.calls, hasLength(1));
    },
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

SaleModel _cashSale() {
  const item = SaleItemModel(
    id: 'item-1',
    productId: 'p-1',
    productNameSnapshot: 'CABLE USB',
    productImageSnapshot: null,
    qty: 1,
    priceSoldUnit: 100,
    costUnitSnapshot: 50,
    subtotalSold: 100,
    subtotalCost: 50,
    profit: 50,
    category: null,
    unitCodeSnapshot: 'UNIT',
    unitNameSnapshot: 'Unidad',
    unitSymbolSnapshot: 'u',
  );
  return SaleModel(
    id: 'sale-81472316',
    userId: 'u1',
    userName: 'Cajero Uno',
    customerId: null,
    customerName: null,
    customerPhone: null,
    saleDate: DateTime(2026, 8, 20, 19, 30),
    note: null,
    totalSold: 100,
    totalCost: 50,
    totalProfit: 50,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 100,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    items: const [item],
  );
}

ProviderContainer _container({
  required PrinterSettingsModel settings,
  required _RecordingRawTransport ticketRaw,
  required _RecordingRawTransport drawerRaw,
}) {
  return ProviderContainer(
    overrides: [
      companyInfoRepositoryProvider.overrideWith(
        _FakeCompanyInfoRepository.new,
      ),
      printerSettingsRepositoryProvider.overrideWith(
        (_) => _FakePrinterSettingsRepository(settings),
      ),
      printingPlatformResolverProvider.overrideWithValue(
        const _FakeWindowsPrintingPlatformResolver(),
      ),
      unifiedTicketPrinterProvider.overrideWith(
        (ref) => UnifiedTicketPrinter(
          ref,
          thermalPrinterService: _FakeThermalPrinterService(),
          windowsRawPrinterTransport: ticketRaw,
          useEscPosReceiptRenderer: false,
          htmlToPdfConverter: _FakeHtmlConverter().convert,
        ),
      ),
      cashDrawerServiceProvider.overrideWith(
        (ref) => CashDrawerService(
          ref,
          windowsRawPrinterTransport: drawerRaw,
          kickTimeout: const Duration(milliseconds: 200),
        ),
      ),
    ],
  );
}

class _FakeCompanyInfoRepository extends CompanyInfoRepository {
  _FakeCompanyInfoRepository(super.ref);

  @override
  Future<CompanyInfo> getCurrentCompanyInfo() async {
    return const CompanyInfo(name: 'FULLPOS CLOUD');
  }
}

class _FakeWindowsPrintingPlatformResolver extends PrintingPlatformResolver {
  const _FakeWindowsPrintingPlatformResolver();

  @override
  PrintingPlatform get platform => PrintingPlatform.windows;
}

class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  _FakePrinterSettingsRepository(this.settings);
  final PrinterSettingsModel settings;

  @override
  Future<PrinterSettingsModel> getOrCreate() async => settings;
}

class _FakeThermalPrinterService extends ThermalPrinterService {
  @override
  Future<PrintResult> printDocument({
    required Uint8List bytes,
    required PrinterSettingsModel settings,
    int? copies,
    String documentName = 'Ticket',
  }) async {
    return const PrintResult(success: true, message: 'PDF enviado.');
  }
}

class _FakeHtmlConverter {
  static final pdfBytes = Uint8List.fromList([1, 2, 3, 4]);

  Future<Uint8List> convert(
    ThermalReceiptViewModel receipt,
    double paperWidthMm,
    String warrantyPolicy,
  ) async {
    return pdfBytes;
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
