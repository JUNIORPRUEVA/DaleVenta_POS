import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_shift_close_renderer.dart';
import 'package:daleventa_pos/core/printing/esc_pos/shift_close_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/printing_platform_resolver.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/modules/cash/cash_close_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows close ticket tries RAW professional first and skips PDF on success',
    () async {
      final recorder = _Recorder();
      final container = _container(recorder: recorder);
      addTearDown(container.dispose);

      final result = await container
          .read(cashCloseTicketPrinterProvider)
          .printCloseTicket(_snapshot());

      expect(result.success, isTrue);
      expect(recorder.rawCalls.length, 1);
      expect(recorder.pdfCalls, isEmpty);
      // Uses the professional renderer output (not the legacy PDF).
      expect(_containsText(recorder.rawCalls.single.bytes, 'CIERRE DE TURNO'), isTrue);
    },
  );

  test('Windows close uses FullPosEscPosShiftCloseRenderer bytes', () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder);
    addTearDown(container.dispose);

    await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());

    final bytes = recorder.rawCalls.single.bytes;
    expect(_containsText(bytes, 'VENTAS Y EFECTIVO'), isTrue);
    expect(_containsText(bytes, 'CUADRE FINAL'), isTrue);
    expect(_cutCommandCount(bytes), 1);
  });

  test('RAW transport receives the exact bytes produced by the renderer',
      () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder);
    addTearDown(container.dispose);

    await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());

    final company = const CompanyInfo(
      name: 'FULLTECH, SRL',
      address: 'Higüey',
      phone: '809-000-0000',
      rnc: '131000000',
    );
    final expected = await FullPosEscPosShiftCloseRenderer(
      cutPaper: true,
    ).render(_expectedCloseVm(company));
    expect(recorder.rawCalls.single.bytes, expected);
  });

  test('RAW is attempted only when a Windows printer is configured', () async {
    final configured = _Recorder();
    final withPrinter = _container(recorder: configured);
    addTearDown(withPrinter.dispose);
    await withPrinter
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());
    expect(configured.rawCalls.length, 1);

    final noPrinter = _Recorder();
    final withoutPrinter = _container(recorder: noPrinter, printerName: '');
    addTearDown(withoutPrinter.dispose);
    await withoutPrinter
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());
    expect(noPrinter.rawCalls, isEmpty);
    expect(noPrinter.pdfCalls.length, 1);
  });

  test('falls back to PDF exactly once when RAW fails', () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder, rawFails: true);
    addTearDown(container.dispose);

    final result = await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());

    expect(result.success, isTrue);
    expect(recorder.rawCalls.length, 1);
    expect(recorder.pdfCalls.length, 1);
    expect(recorder.pdfCalls.single, contains('Cierre de turno'));
  });

  test('reprint history uses the same professional RAW renderer on Windows',
      () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder);
    addTearDown(container.dispose);

    final result = await container
        .read(cashCloseTicketPrinterProvider)
        .printHistoryTicket(_historyRow());

    expect(result.success, isTrue);
    expect(recorder.rawCalls.length, 1);
    expect(recorder.pdfCalls, isEmpty);
    expect(
      _containsText(recorder.rawCalls.single.bytes, 'REIMPRESION CIERRE'),
      isTrue,
    );
  });

  test('print current (automatic: false) follows the same RAW policy', () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder);
    addTearDown(container.dispose);

    final result = await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot(), automatic: false);

    expect(result.success, isTrue);
    expect(recorder.rawCalls.length, 1);
    expect(recorder.pdfCalls, isEmpty);
  });

  test('professional close does not depend on the FULLPOS_ESC_POS_RECEIPT define',
      () async {
    // This test runs without `--dart-define=FULLPOS_ESC_POS_RECEIPT=true`
    // (default false) and the close still routes through RAW professional.
    final recorder = _Recorder();
    final container = _container(recorder: recorder);
    addTearDown(container.dispose);

    await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());

    expect(recorder.rawCalls.length, 1);
    expect(_containsText(recorder.rawCalls.single.bytes, 'CIERRE DE TURNO'), isTrue);
  });

  test('close ticket does not print the warranty policy', () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder);
    addTearDown(container.dispose);

    await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());

    expect(
      _containsText(recorder.rawCalls.single.bytes, 'POLITICA DE GARANTIA'),
      isFalse,
    );
  });

  test('close ticket prints the real cashier snapshot', () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder);
    addTearDown(container.dispose);

    await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());

    expect(_containsText(recorder.rawCalls.single.bytes, 'Yunior López'), isTrue);
    expect(
      _containsText(recorder.rawCalls.single.bytes, 'PENDIENTE DE SINCRONIZAR'),
      isFalse,
    );
  });

  test('non-Windows platforms keep using the PDF path (no RAW)', () async {
    final recorder = _Recorder();
    final container = _container(recorder: recorder, android: true);
    addTearDown(container.dispose);

    final result = await container
        .read(cashCloseTicketPrinterProvider)
        .printCloseTicket(_snapshot());

    expect(result.success, isTrue);
    expect(recorder.rawCalls, isEmpty);
    expect(recorder.pdfCalls.length, 1);
  });
}

// ---------------------------------------------------------------------------
// Fakes / infraestructura
// ---------------------------------------------------------------------------

class _RawCall {
  const _RawCall({
    required this.bytes,
    required this.ticketNumber,
    required this.documentName,
  });

  final Uint8List bytes;
  final String ticketNumber;
  final String documentName;
}

class _Recorder {
  final rawCalls = <_RawCall>[];
  final pdfCalls = <String>[];
}

class _RecordingUnifiedTicketPrinter extends UnifiedTicketPrinter {
  _RecordingUnifiedTicketPrinter(
    super.ref, {
    required this.recorder,
    this.rawFails = false,
  });

  final _Recorder recorder;
  final bool rawFails;

  @override
  Future<PrintTicketResult> printWindowsRawEscPosBytes({
    required Uint8List bytes,
    required String ticketNumber,
    required String documentName,
    int? copies,
    String? printerName,
  }) async {
    recorder.rawCalls.add(
      _RawCall(
        bytes: Uint8List.fromList(bytes),
        ticketNumber: ticketNumber,
        documentName: documentName,
      ),
    );
    if (rawFails) {
      return const PrintTicketResult(success: false, message: 'RAW ERROR: boom');
    }
    return PrintTicketResult(
      success: true,
      message: 'RAW OK',
      ticketNumber: ticketNumber,
    );
  }

  @override
  Future<List<Printer>> getAvailablePrinters() async => const [];

  @override
  Future<PrintTicketResult> printPdfBytes({
    required Uint8List bytes,
    required String ticketNumber,
    required String documentName,
    List<String> fallbackLines = const <String>[],
    int? overrideCopies,
    bool showSystemDialogIfNoPrinter = true,
  }) async {
    recorder.pdfCalls.add(documentName);
    return PrintTicketResult(
      success: true,
      message: 'PDF OK',
      ticketNumber: ticketNumber,
    );
  }
}

class _FakeCompanyInfoRepository extends CompanyInfoRepository {
  _FakeCompanyInfoRepository(super.ref);

  @override
  Future<CompanyInfo> getCurrentCompanyInfo() async {
    return const CompanyInfo(
      name: 'FULLTECH, SRL',
      address: 'Higüey',
      phone: '809-000-0000',
      rnc: '131000000',
    );
  }
}

class _FakePrinterSettingsRepository extends PrinterSettingsRepository {
  _FakePrinterSettingsRepository(this.printerName);

  final String printerName;

  @override
  Future<PrinterSettingsModel> getOrCreate() async {
    return PrinterSettingsModel(
      selectedPrinterName: printerName,
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

class _AndroidPrintingPlatformResolver extends PrintingPlatformResolver {
  const _AndroidPrintingPlatformResolver();

  @override
  PrintingPlatform get platform => PrintingPlatform.android;
}

ProviderContainer _container({
  required _Recorder recorder,
  bool rawFails = false,
  String printerName = 'POS-80',
  bool android = false,
}) {
  return ProviderContainer(
    overrides: [
      companyInfoRepositoryProvider.overrideWith(_FakeCompanyInfoRepository.new),
      printerSettingsRepositoryProvider.overrideWith(
        (_) => _FakePrinterSettingsRepository(printerName),
      ),
      printingPlatformResolverProvider.overrideWithValue(
        android
            ? const _AndroidPrintingPlatformResolver()
            : const _WindowsPrintingPlatformResolver(),
      ),
      unifiedTicketPrinterProvider.overrideWith(
        (ref) => _RecordingUnifiedTicketPrinter(
          ref,
          recorder: recorder,
          rawFails: rawFails,
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Datos oficiales del cierre
// ---------------------------------------------------------------------------

CashCloseTicketSnapshot _snapshot() {
  return CashCloseTicketSnapshot(
    state: CashGateState(
      businessDate: '20/08/2026',
      canOperate: true,
      activeSession: ActiveCashSession(
        userId: 'u1',
        cashId: 'CAJA-001',
        shiftId: 'SHIFT-20260820-001',
        openedAt: DateTime(2026, 8, 20, 8, 0),
        status: 'OPEN',
        userName: 'Yunior López',
        businessDate: '20/08/2026',
      ),
    ),
    summary: const CashSummaryModel(
      openingAmount: 5000,
      totalSales: 12350,
      totalExpenses: 250,
      totalWithdrawals: 900,
      cashInManual: 0,
      cashOutManual: 0,
      creditAbonos: 0,
      creditSalesTotal: 0,
      creditInitialCash: 0,
      creditInitialTransfer: 0,
      creditBalanceTotal: 0,
      creditPaymentCash: 0,
      creditPaymentTransfer: 0,
      salesCashTotal: 10000,
      salesTransferTotal: 2350,
      refundsCash: 0,
      expectedCash: 16200,
      totalTickets: 24,
      totalRefunds: 1,
      categorySummary: [
        CashCategorySummaryModel(
          category: 'SMART Y ACCESORIOS',
          totalSold: 944,
          totalProfit: 644,
          items: 1,
        ),
      ],
    ),
    movements: [
      CashMovementModel(
        id: 'm1',
        sessionId: 's1',
        type: 'OUT',
        amount: 250,
        reason: 'Compra de insumos',
        movementType: 'expense',
        affectsProfit: true,
        createdAt: DateTime(2026, 8, 20, 19, 0),
      ),
    ],
    closingAmount: 16300,
    note: 'Nota del turno',
    capturedAt: DateTime(2026, 8, 20, 20, 30),
  );
}

CashSessionHistoryModel _historyRow() {
  return CashSessionHistoryModel(
    id: 'h-20260820-001',
    userName: 'Yunior López',
    businessDate: '20/08/2026',
    openedAt: DateTime(2026, 8, 20, 8, 0),
    closedAt: DateTime(2026, 8, 20, 20, 30),
    initialAmount: 5000,
    closingAmount: 16200,
    expectedAmount: 16300,
    difference: 100,
    status: 'CLOSED',
  );
}

ShiftCloseReceiptViewModel _expectedCloseVm(CompanyInfo company) {
  return ShiftCloseReceiptViewModel(
    company: company,
    title: 'CIERRE DE TURNO',
    ticketNumber: 'CIERRE-20082026-SHIFT2',
    cashierName: 'Yunior López',
    shiftId: 'SHIFT-20260820-001',
    cashId: 'CAJA-001',
    businessDate: '20/08/2026',
    openedAt: DateTime(2026, 8, 20, 8, 0),
    closedAt: DateTime(2026, 8, 20, 20, 30),
    capturedAt: DateTime(2026, 8, 20, 20, 30),
    showSalesDetails: true,
    openingAmount: 5000,
    totalSales: 12350,
    cashSales: 10000,
    transferSales: 2350,
    manualCashIn: 0,
    expenses: 250,
    manualCashOut: 0,
    withdrawals: 900,
    refunds: 0,
    creditSales: 0,
    creditInitialCash: 0,
    creditInitialTransfer: 0,
    creditPaymentCash: 0,
    creditPaymentTransfer: 0,
    creditBalance: 0,
    expectedCash: 16200,
    countedCash: 16300,
    difference: 100,
    ticketCount: 24,
    refundCount: 1,
    categorySummaries: const [
      ShiftCloseCategorySummary(
        categoryName: 'SMART Y ACCESORIOS',
        soldAmount: 944,
        profitAmount: 644,
      ),
    ],
    status: '',
    note: 'Nota del turno',
    movements: const [
      ShiftCloseMovement(
        label: 'Gasto',
        amount: 250,
        isIn: false,
        reason: 'Compra de insumos',
      ),
    ],
  );
}

bool _containsText(List<int> bytes, String text) {
  return latin1.decode(bytes).contains(text);
}

int _cutCommandCount(List<int> bytes) {
  var count = 0;
  for (var i = 0; i < bytes.length - 2; i++) {
    if (bytes[i] == 0x1D && bytes[i + 1] == 0x56) {
      count++;
    }
  }
  return count;
}
