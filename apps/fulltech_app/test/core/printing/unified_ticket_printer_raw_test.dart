import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/printing/thermal_printer_service.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/core/printing/windows_raw_printer_transport.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows sale ticket uses HTML renderer instead of RAW or legacy PDF',
    () async {
      final raw = _FakeRawTransport();
      final thermal = _FakeThermalPrinterService();
      final html = _FakeHtmlConverter();
      final container = _container();
      addTearDown(container.dispose);
      final printer = container.read(
        _printerProvider(
          raw: raw,
          thermal: thermal,
          useEscPosReceiptRenderer: true,
          html: html,
        ),
      );

      final result = await printer.printTicket(_saleTicket());

      expect(result.success, isTrue);
      expect(raw.calls, isEmpty);
      expect(html.calls, 1);
      expect(html.lastReceipt?.ticketNumber, '81472316');
      expect(html.lastReceipt?.items.single.name, 'CABLE USB');
      expect(html.lastPaperWidthMm, 80);
      expect(html.lastWarrantyPolicy, 'Garantía según política.');
      expect(thermal.printDocumentCalls, 1);
      expect(thermal.lastBytes, _FakeHtmlConverter.pdfBytes);
    },
  );

  test(
    'Windows sale ticket still uses HTML when ESC/POS flag is false',
    () async {
      final raw = _FakeRawTransport();
      final thermal = _FakeThermalPrinterService();
      final html = _FakeHtmlConverter();
      final container = _container();
      addTearDown(container.dispose);
      final printer = container.read(
        _printerProvider(
          raw: raw,
          thermal: thermal,
          useEscPosReceiptRenderer: false,
          html: html,
        ),
      );

      final result = await printer.printTicket(_saleTicket());

      expect(result.success, isTrue);
      expect(raw.calls, isEmpty);
      expect(html.calls, 1);
      expect(html.lastReceipt?.company.name, 'FULLPOS CLOUD');
      expect(thermal.printDocumentCalls, 1);
    },
  );

  test(
    'Windows sale ticket does not touch RAW transport even if RAW would fail',
    () async {
      final raw = _FakeRawTransport(
        error: const RawPrinterException('RAW boom'),
      );
      final thermal = _FakeThermalPrinterService();
      final html = _FakeHtmlConverter();
      final container = _container();
      addTearDown(container.dispose);
      final printer = container.read(
        _printerProvider(
          raw: raw,
          thermal: thermal,
          useEscPosReceiptRenderer: true,
          html: html,
        ),
      );

      final result = await printer.printTicket(_saleTicket());

      expect(result.success, isTrue);
      expect(raw.calls, isEmpty);
      expect(html.calls, 1);
      expect(thermal.printDocumentCalls, 1);
    },
  );

  test(
    'test ticket button path uses the same HTML ticket renderer on Windows',
    () async {
      final raw = _FakeRawTransport();
      final thermal = _FakeThermalPrinterService();
      final html = _FakeHtmlConverter();
      final container = _container();
      addTearDown(container.dispose);
      final printer = container.read(
        _printerProvider(
          raw: raw,
          thermal: thermal,
          useEscPosReceiptRenderer: true,
          html: html,
        ),
      );

      final result = await printer.printTestTicket();

      expect(result.success, isTrue);
      expect(raw.calls, isEmpty);
      expect(html.calls, 1);
      expect(html.lastReceipt?.items, isNotEmpty);
      expect(thermal.printDocumentCalls, 1);
    },
  );
}

Provider<UnifiedTicketPrinter> _printerProvider({
  required _FakeRawTransport raw,
  required _FakeThermalPrinterService thermal,
  required bool useEscPosReceiptRenderer,
  required _FakeHtmlConverter html,
}) {
  return Provider<UnifiedTicketPrinter>(
    (ref) => UnifiedTicketPrinter(
      ref,
      thermalPrinterService: thermal,
      windowsRawPrinterTransport: raw,
      useEscPosReceiptRenderer: useEscPosReceiptRenderer,
      htmlToPdfConverter: html.convert,
    ),
  );
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      companyInfoRepositoryProvider.overrideWith(
        _FakeCompanyInfoRepository.new,
      ),
      printerSettingsRepositoryProvider.overrideWith(
        (_) => _FakePrinterSettingsRepository(),
      ),
      printingPlatformResolverProvider.overrideWithValue(
        const _WindowsPrintingPlatformResolver(),
      ),
    ],
  );
}

TicketData _saleTicket() {
  return TicketData(
    ticketNumber: '81472316',
    dateTime: DateTime(2026, 8, 20, 19, 29),
    client: const ClientInfo(name: 'Consumidor Final'),
    cashierName: 'Juan Perez',
    paymentMethod: 'Efectivo',
    items: const [
      TicketItemData(name: 'CABLE USB', qty: 1, unitPrice: 100, total: 100),
    ],
    subtotal: 100,
    total: 100,
  );
}

class _FakeCompanyInfoRepository extends CompanyInfoRepository {
  _FakeCompanyInfoRepository(super.ref);

  @override
  Future<CompanyInfo> getCurrentCompanyInfo() async {
    return const CompanyInfo(name: 'FULLPOS CLOUD');
  }
}

class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  @override
  Future<PrinterSettingsModel> getOrCreate() async {
    return const PrinterSettingsModel(
      selectedPrinterName: 'POS-80',
      copies: 1,
      autoCut: true,
      warrantyPolicy: 'Garantía según política.',
    );
  }
}

class _WindowsPrintingPlatformResolver extends PrintingPlatformResolver {
  const _WindowsPrintingPlatformResolver();

  @override
  PrintingPlatform get platform => PrintingPlatform.windows;
}

class _FakeThermalPrinterService extends ThermalPrinterService {
  var printDocumentCalls = 0;
  Uint8List? lastBytes;

  @override
  Future<PrintResult> printDocument({
    required Uint8List bytes,
    required PrinterSettingsModel settings,
    int? copies,
    String documentName = 'Ticket',
  }) async {
    printDocumentCalls++;
    lastBytes = Uint8List.fromList(bytes);
    return const PrintResult(success: true, message: 'PDF enviado.');
  }
}

class _FakeHtmlConverter {
  static final pdfBytes = Uint8List.fromList([1, 2, 3, 4]);

  var calls = 0;
  ThermalReceiptViewModel? lastReceipt;
  double? lastPaperWidthMm;
  String? lastWarrantyPolicy;

  Future<Uint8List> convert(
    ThermalReceiptViewModel receipt,
    double paperWidthMm,
    String warrantyPolicy,
  ) async {
    calls++;
    lastReceipt = receipt;
    lastPaperWidthMm = paperWidthMm;
    lastWarrantyPolicy = warrantyPolicy;
    return pdfBytes;
  }
}

class _FakeRawTransport implements RawPrinterTransport {
  _FakeRawTransport({this.error});

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
