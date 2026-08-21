import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/printing/esc_pos/fullpos_esc_pos_shift_close_renderer.dart';
import '../../core/printing/esc_pos/shift_close_receipt_view_model.dart';
import '../../core/printing/models/company_info.dart';
import '../../core/printing/models/receipt_text_utils.dart';
import '../../core/printing/models/ticket_layout_config.dart';
import '../../core/printing/printing_platform_resolver.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../features/settings/data/printer_settings_model.dart';
import '../../features/settings/data/printer_settings_repository.dart';
import 'cash_models.dart';

final cashCloseTicketPrinterProvider = Provider<CashCloseTicketPrinter>((ref) {
  return CashCloseTicketPrinter(ref);
});

class CashCloseTicketSnapshot {
  const CashCloseTicketSnapshot({
    required this.state,
    required this.summary,
    required this.movements,
    required this.closingAmount,
    this.note,
    required this.capturedAt,
  });

  final CashGateState state;
  final CashSummaryModel summary;
  final List<CashMovementModel> movements;
  final double closingAmount;
  final String? note;
  final DateTime capturedAt;

  ActiveCashSession? get active => state.activeSession;
  double get difference => summary.difference(closingAmount);
}

class CashCloseTicketPrinter {
  CashCloseTicketPrinter(this._ref);

  /// Rollback global: si se compila con `FULLPOS_FORCE_LEGACY_PDF=true` se
  /// vuelve al PDF legacy aunque haya impresora térmica configurada
  /// (debug/emergencia). Por defecto el cierre normal en Windows usa RAW.
  static const bool _forceLegacyPdf = bool.fromEnvironment(
    'FULLPOS_FORCE_LEGACY_PDF',
  );

  final Ref _ref;

  Future<PrintTicketResult> printCloseTicket(
    CashCloseTicketSnapshot snapshot, {
    bool automatic = true,
  }) async {
    final ticketNumber = _ticketNumber(snapshot);
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    if (await _shouldTryWindowsRawEscPos(settings)) {
      final printerName = await _resolveWindowsPrinterName(settings);
      final bytes = await _buildCloseEscPos(snapshot, ticketNumber);
      debugPrint('[CASH PRINT] platform = Windows');
      debugPrint('[CASH PRINT] renderer = FullPosEscPosShiftCloseRenderer');
      debugPrint('[CASH PRINT] transport = Windows RAW ESC/POS');
      debugPrint('[CASH PRINT] printer = $printerName');
      debugPrint('[CASH PRINT] bytes = ${bytes.length}');
      final rawResult = await _ref
          .read(unifiedTicketPrinterProvider)
          .printWindowsRawEscPosBytes(
            bytes: bytes,
            ticketNumber: ticketNumber,
            documentName: 'Cierre de turno $ticketNumber',
            printerName: printerName,
          );
      if (rawResult.success) {
        debugPrint('[CASH PRINT] result = SUCCESS');
        return rawResult;
      }
      debugPrint('[CASH PRINT] RAW ERROR = ${rawResult.message}');
      debugPrint('[CASH PRINT] fallback = PDF legacy');
    }
    final pdf = await _buildClosePdf(snapshot, ticketNumber: ticketNumber);
    // El cierre de turno siempre imprime el ticket (térmico o diálogo del
    // sistema como respaldo) para que salga de inmediato en móvil y PC.
    return _ref
        .read(unifiedTicketPrinterProvider)
        .printPdfBytes(
          bytes: pdf,
          ticketNumber: ticketNumber,
          documentName: 'Cierre de turno $ticketNumber',
          fallbackLines: buildLines(snapshot),
        );
  }

  Future<PrintTicketResult> printHistoryTicket(
    CashSessionHistoryModel row,
  ) async {
    final date = row.closedAt ?? row.openedAt;
    final ticketDate = row.businessDate.trim().isNotEmpty
        ? row.businessDate.trim().replaceAll(RegExp(r'[^0-9]'), '')
        : DateFormat('yyyyMMdd').format(date);
    final suffix = row.id.replaceAll('-', '');
    final compactSuffix = suffix.substring(
      0,
      suffix.length < 6 ? suffix.length : 6,
    );
    final ticketNumber = 'CIERRE-$ticketDate-$compactSuffix';
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    if (await _shouldTryWindowsRawEscPos(settings)) {
      final printerName = await _resolveWindowsPrinterName(settings);
      final bytes = await _buildHistoryEscPos(row, ticketNumber);
      debugPrint('[CASH PRINT] platform = Windows');
      debugPrint('[CASH PRINT] renderer = FullPosEscPosShiftCloseRenderer');
      debugPrint('[CASH PRINT] transport = Windows RAW ESC/POS');
      debugPrint('[CASH PRINT] printer = $printerName');
      debugPrint('[CASH PRINT] bytes = ${bytes.length}');
      final rawResult = await _ref
          .read(unifiedTicketPrinterProvider)
          .printWindowsRawEscPosBytes(
            bytes: bytes,
            ticketNumber: ticketNumber,
            documentName: 'Reimpresion cierre $ticketNumber',
            printerName: printerName,
          );
      if (rawResult.success) {
        debugPrint('[CASH PRINT] result = SUCCESS');
        return rawResult;
      }
      debugPrint('[CASH PRINT] RAW ERROR = ${rawResult.message}');
      debugPrint('[CASH PRINT] fallback = PDF legacy');
    }
    final pdf = await _buildHistoryPdf(row, ticketNumber: ticketNumber);
    return _ref
        .read(unifiedTicketPrinterProvider)
        .printPdfBytes(
          bytes: pdf,
          ticketNumber: ticketNumber,
          documentName: 'Reimpresion cierre $ticketNumber',
          fallbackLines: buildHistoryLines(row),
        );
  }

  Future<Uint8List> _buildClosePdf(
    CashCloseTicketSnapshot snapshot, {
    required String ticketNumber,
  }) async {
    final company = await _ref
        .read(companyInfoRepositoryProvider)
        .getCurrentCompanyInfo();
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    return _CashClosePdfBuilder(
      company: company,
      layout: layout,
    ).buildClose(snapshot, ticketNumber: ticketNumber);
  }

  Future<Uint8List> _buildHistoryPdf(
    CashSessionHistoryModel row, {
    required String ticketNumber,
  }) async {
    final company = await _ref
        .read(companyInfoRepositoryProvider)
        .getCurrentCompanyInfo();
    final settings = await _ref
        .read(printerSettingsRepositoryProvider)
        .getOrCreate();
    final layout = TicketLayoutConfig.fromPrinterSettings(settings);
    return _CashClosePdfBuilder(
      company: company,
      layout: layout,
    ).buildHistory(row, ticketNumber: ticketNumber);
  }

  /// Política de cierre en Windows: usar el renderer profesional RAW ESC/POS
  /// por defecto (con impresora disponible) y PDF legacy solo como fallback.
  /// El antiguo gate por `FULLPOS_ESC_POS_RECEIPT` ya no condiciona el cierre.
  Future<bool> _shouldTryWindowsRawEscPos(PrinterSettingsModel settings) async {
    final platform = _ref.read(printingPlatformResolverProvider).platform;
    if (platform != PrintingPlatform.windows) return false;
    if (_forceLegacyPdf) return false;
    return (await _resolveWindowsPrinterName(settings)).isNotEmpty;
  }

  /// Resuelve el nombre de impresora para el cierre en Windows: primero la
  /// impresora configurada en Ajustes; si no hay, la impresora por defecto del
  /// sistema (así el cierre profesional se intenta sin configuración extra).
  Future<String> _resolveWindowsPrinterName(
    PrinterSettingsModel settings,
  ) async {
    final configured = (settings.selectedPrinterName ?? '').trim();
    if (configured.isNotEmpty) return configured;
    try {
      final printers = await _ref
          .read(unifiedTicketPrinterProvider)
          .getAvailablePrinters();
      if (printers.isEmpty) return '';
      return printers.first.name;
    } catch (_) {
      return '';
    }
  }

  Future<Uint8List> _buildCloseEscPos(
    CashCloseTicketSnapshot snapshot,
    String ticketNumber,
  ) async {
    final company = await _ref
        .read(companyInfoRepositoryProvider)
        .getCurrentCompanyInfo();
    return FullPosEscPosShiftCloseRenderer(cutPaper: true).render(
      _closeViewModel(snapshot, ticketNumber: ticketNumber, company: company),
    );
  }

  Future<Uint8List> _buildHistoryEscPos(
    CashSessionHistoryModel row,
    String ticketNumber,
  ) async {
    final company = await _ref
        .read(companyInfoRepositoryProvider)
        .getCurrentCompanyInfo();
    return FullPosEscPosShiftCloseRenderer(cutPaper: true).render(
      _historyViewModel(row, ticketNumber: ticketNumber, company: company),
    );
  }

  ShiftCloseReceiptViewModel _closeViewModel(
    CashCloseTicketSnapshot snapshot, {
    required String ticketNumber,
    required CompanyInfo company,
  }) {
    final active = snapshot.active;
    final summary = snapshot.summary;
    return ShiftCloseReceiptViewModel(
      company: company,
      title: 'CIERRE DE TURNO',
      ticketNumber: ticketNumber,
      cashierName: active?.userName ?? '',
      shiftId: active?.shiftId ?? '',
      cashId: active?.cashId ?? '',
      businessDate: snapshot.state.businessDate,
      openedAt: active?.openedAt,
      closedAt: snapshot.capturedAt,
      capturedAt: snapshot.capturedAt,
      showSalesDetails: true,
      openingAmount: summary.openingAmount,
      totalSales: summary.totalSales,
      cashSales: summary.salesCashTotal,
      transferSales: summary.salesTransferTotal,
      manualCashIn: summary.cashInManual,
      expenses: summary.totalExpenses,
      manualCashOut: summary.cashOutManual,
      withdrawals: summary.totalWithdrawals,
      refunds: summary.refundsCash,
      creditSales: summary.creditSalesTotal,
      creditInitialCash: summary.creditInitialCash,
      creditInitialTransfer: summary.creditInitialTransfer,
      creditPaymentCash: summary.creditPaymentCash,
      creditPaymentTransfer: summary.creditPaymentTransfer,
      creditBalance: summary.creditBalanceTotal,
      expectedCash: summary.expectedCash,
      countedCash: snapshot.closingAmount,
      difference: snapshot.difference,
      ticketCount: summary.totalTickets,
      refundCount: summary.totalRefunds,
      categorySummaries: [
        for (final category in summary.categorySummary)
          ShiftCloseCategorySummary(
            categoryName: category.category,
            soldAmount: category.totalSold,
            profitAmount: category.totalProfit,
          ),
      ],
      status: '',
      note: snapshot.note,
      movements: [
        for (final movement in snapshot.movements)
          ShiftCloseMovement(
            label: _movementLabel(movement),
            amount: movement.amount,
            isIn: movement.isIn,
            reason: movement.reason.trim().isEmpty
                ? null
                : movement.reason,
          ),
      ],
    );
  }

  ShiftCloseReceiptViewModel _historyViewModel(
    CashSessionHistoryModel row, {
    required String ticketNumber,
    required CompanyInfo company,
  }) {
    final closedAt = row.closedAt;
    return ShiftCloseReceiptViewModel(
      company: company,
      title: 'REIMPRESION CIERRE',
      ticketNumber: ticketNumber,
      cashierName: row.userName,
      shiftId: '',
      cashId: '',
      businessDate: row.businessDate,
      openedAt: row.openedAt,
      closedAt: closedAt,
      capturedAt: closedAt ?? row.openedAt,
      showSalesDetails: false,
      openingAmount: row.initialAmount,
      totalSales: 0,
      cashSales: 0,
      transferSales: 0,
      manualCashIn: 0,
      expenses: 0,
      manualCashOut: 0,
      withdrawals: 0,
      refunds: 0,
      creditSales: 0,
      creditInitialCash: 0,
      creditInitialTransfer: 0,
      creditPaymentCash: 0,
      creditPaymentTransfer: 0,
      creditBalance: 0,
      expectedCash: row.expectedAmount,
      countedCash: row.closingAmount,
      difference: row.difference,
      ticketCount: 0,
      refundCount: 0,
      categorySummaries: const [],
      status: row.status,
      note: null,
      movements: null,
    );
  }

  List<String> buildHistoryLines(CashSessionHistoryModel row) {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
    final date = DateFormat('dd/MM/yyyy HH:mm');
    const width = 32;
    final closedAt = row.closedAt;

    return [
      ReceiptTextUtils.center('REIMPRESION CORTE', width),
      ReceiptTextUtils.center('DE TURNO', width),
      ReceiptTextUtils.separator(width, 'double'),
      ReceiptTextUtils.leftRight('Turno', row.businessDate, width),
      ReceiptTextUtils.leftRight('Cajero', row.userName, width),
      ReceiptTextUtils.leftRight(
        'Apertura',
        date.format(row.openedAt.toLocal()),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Cierre',
        closedAt == null ? 'Sin cierre' : date.format(closedAt.toLocal()),
        width,
      ),
      ReceiptTextUtils.leftRight('Estado', row.status, width),
      ReceiptTextUtils.separator(width, 'double'),
      ReceiptTextUtils.leftRight(
        'Base inicial',
        money.format(row.initialAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Efectivo esperado',
        money.format(row.expectedAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Efectivo contado',
        money.format(row.closingAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Diferencia',
        money.format(row.difference),
        width,
      ),
    ];
  }

  List<String> buildLines(CashCloseTicketSnapshot snapshot) {
    final money = NumberFormat.currency(locale: 'en_US', symbol: 'RD\$ ');
    final date = DateFormat('dd/MM/yyyy HH:mm');
    final active = snapshot.active;
    const width = 32;
    final note = (snapshot.note ?? '').trim();
    final movements = snapshot.movements;

    return [
      ReceiptTextUtils.center('CORTE DE TURNO', width),
      ReceiptTextUtils.separator(width, 'double'),
      ReceiptTextUtils.center('RESUMEN DE CAJA', width),
      ReceiptTextUtils.separator(width, 'dashed'),
      ReceiptTextUtils.leftRight(
        'Fecha',
        date.format(snapshot.capturedAt.toLocal()),
        width,
      ),
      if (snapshot.state.businessDate.trim().isNotEmpty)
        ReceiptTextUtils.leftRight(
          'Dia negocio',
          snapshot.state.businessDate,
          width,
        ),
      if (active != null) ...[
        ReceiptTextUtils.leftRight('Cajero', active.userName, width),
        ReceiptTextUtils.leftRight(
          'Apertura',
          date.format(active.openedAt.toLocal()),
          width,
        ),
      ],
      ReceiptTextUtils.separator(width, 'dashed'),
      ReceiptTextUtils.center('VENTAS Y EFECTIVO', width),
      ReceiptTextUtils.leftRight(
        'Base inicial',
        money.format(snapshot.summary.openingAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Total vendido',
        money.format(snapshot.summary.totalSales),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Ventas efectivo',
        money.format(snapshot.summary.salesCashTotal),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Transferencias',
        money.format(snapshot.summary.salesTransferTotal),
        width,
      ),
      if (snapshot.summary.creditSalesTotal > 0) ...[
        ReceiptTextUtils.separator(width, 'dashed'),
        'VENTAS A CREDITO',
        ReceiptTextUtils.leftRight(
          'Total credito',
          money.format(snapshot.summary.creditSalesTotal),
          width,
        ),
        ReceiptTextUtils.leftRight(
          'Inicial efectivo',
          money.format(snapshot.summary.creditInitialCash),
          width,
        ),
        ReceiptTextUtils.leftRight(
          'Inicial transf.',
          money.format(snapshot.summary.creditInitialTransfer),
          width,
        ),
        ReceiptTextUtils.leftRight(
          'Abonos efectivo',
          money.format(snapshot.summary.creditPaymentCash),
          width,
        ),
        ReceiptTextUtils.leftRight(
          'Abonos transf.',
          money.format(snapshot.summary.creditPaymentTransfer),
          width,
        ),
        ReceiptTextUtils.leftRight(
          'Balance credito',
          money.format(snapshot.summary.creditBalanceTotal),
          width,
        ),
      ],
      ReceiptTextUtils.leftRight(
        'Entradas',
        money.format(snapshot.summary.cashInManual),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Gastos',
        money.format(snapshot.summary.totalExpenses),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Salidas',
        money.format(snapshot.summary.cashOutManual),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Retiros',
        money.format(snapshot.summary.totalWithdrawals),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Devoluciones',
        money.format(snapshot.summary.refundsCash),
        width,
      ),
      if (snapshot.summary.categorySummary.isNotEmpty) ...[
        ReceiptTextUtils.separator(width, 'dashed'),
        ReceiptTextUtils.center('POR CATEGORIA', width),
        for (final category in snapshot.summary.categorySummary.take(8)) ...[
          ...ReceiptTextUtils.wrap(category.category, width),
          ReceiptTextUtils.leftRight(
            ' Vendido',
            money.format(category.totalSold),
            width,
          ),
          ReceiptTextUtils.leftRight(
            ' Ganancia',
            money.format(category.totalProfit),
            width,
          ),
        ],
      ],
      ReceiptTextUtils.separator(width, 'double'),
      ReceiptTextUtils.center('CUADRE FINAL', width),
      ReceiptTextUtils.leftRight(
        'Gran total venta',
        money.format(snapshot.summary.totalSales),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Caja apertura',
        money.format(snapshot.summary.openingAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Efectivo esperado',
        money.format(snapshot.summary.expectedCash),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Efectivo contado',
        money.format(snapshot.closingAmount),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Diferencia',
        money.format(snapshot.difference),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Tickets',
        snapshot.summary.totalTickets.toString(),
        width,
      ),
      ReceiptTextUtils.leftRight(
        'Devoluciones',
        snapshot.summary.totalRefunds.toString(),
        width,
      ),
      if (note.isNotEmpty) ...[
        ReceiptTextUtils.separator(width, 'dashed'),
        'Nota:',
        ...ReceiptTextUtils.wrap(note, width),
      ],
      if (movements.isNotEmpty) ...[
        ReceiptTextUtils.separator(width, 'dashed'),
        ReceiptTextUtils.center('MOVIMIENTOS', width),
        for (final movement in movements) ...[
          ReceiptTextUtils.leftRight(
            _movementLabel(movement),
            '${movement.isIn ? '+' : '-'}${money.format(movement.amount)}',
            width,
          ),
          if (movement.reason.trim().isNotEmpty)
            ...ReceiptTextUtils.wrap('  ${movement.reason}', width),
        ],
      ],
    ];
  }

  String _ticketNumber(CashCloseTicketSnapshot snapshot) {
    final date = snapshot.state.businessDate.trim().isNotEmpty
        ? snapshot.state.businessDate.trim().replaceAll(RegExp(r'[^0-9]'), '')
        : DateFormat('yyyyMMdd').format(snapshot.capturedAt);
    final suffix = snapshot.active?.shiftId.replaceAll('-', '');
    final suffixEnd = suffix == null
        ? 0
        : (suffix.length < 6 ? suffix.length : 6);
    final compactSuffix = suffix == null || suffix.isEmpty
        ? DateFormat('HHmmss').format(snapshot.capturedAt)
        : suffix.substring(0, suffixEnd);
    return 'CIERRE-$date-$compactSuffix';
  }

  String _movementLabel(CashMovementModel movement) {
    return switch (movement.movementType) {
      'expense' => 'Gasto',
      'owner_draw' => 'Retiro',
      'transfer' => movement.isIn ? 'Entrada' : 'Transfer.',
      _ => movement.isIn ? 'Entrada' : 'Salida',
    };
  }
}

class _CashClosePdfBuilder {
  _CashClosePdfBuilder({required this.company, required this.layout});

  final CompanyInfo company;
  final TicketLayoutConfig layout;

  late final NumberFormat _money = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD\$ ',
  );
  late final DateFormat _date = DateFormat('dd/MM/yyyy hh:mm a');
  late final _fonts = _loadFonts();

  Future<Uint8List> buildClose(
    CashCloseTicketSnapshot snapshot, {
    required String ticketNumber,
  }) async {
    final rows = <pw.Widget>[
      _header('CORTE DE TURNO', 'Comprobante de cierre de caja'),
      _section('Datos del turno'),
      _kv('No. cierre', ticketNumber, boldValue: true),
      _kv('Fecha cierre', _date.format(snapshot.capturedAt.toLocal())),
      if (snapshot.state.businessDate.trim().isNotEmpty)
        _kv('Dia negocio', snapshot.state.businessDate.trim()),
      if (snapshot.active != null) ...[
        _kv('Cajero', snapshot.active!.userName),
        _kv('Apertura', _date.format(snapshot.active!.openedAt.toLocal())),
      ],
      _divider(),
      _section('Ventas y efectivo'),
      _kv('Base inicial', _money.format(snapshot.summary.openingAmount)),
      _kv('Total vendido', _money.format(snapshot.summary.totalSales)),
      _kv('Ventas efectivo', _money.format(snapshot.summary.salesCashTotal)),
      _kv('Transferencias', _money.format(snapshot.summary.salesTransferTotal)),
      _kv('Entradas manuales', _money.format(snapshot.summary.cashInManual)),
      _kv('Gastos', _money.format(snapshot.summary.totalExpenses)),
      _kv('Salidas', _money.format(snapshot.summary.cashOutManual)),
      _kv('Retiros', _money.format(snapshot.summary.totalWithdrawals)),
      _kv('Devoluciones', _money.format(snapshot.summary.refundsCash)),
      if (snapshot.summary.creditSalesTotal > 0) ...[
        _divider(),
        _section('Credito'),
        _kv('Ventas credito', _money.format(snapshot.summary.creditSalesTotal)),
        _kv(
          'Inicial efectivo',
          _money.format(snapshot.summary.creditInitialCash),
        ),
        _kv(
          'Inicial transf.',
          _money.format(snapshot.summary.creditInitialTransfer),
        ),
        _kv(
          'Abonos efectivo',
          _money.format(snapshot.summary.creditPaymentCash),
        ),
        _kv(
          'Abonos transf.',
          _money.format(snapshot.summary.creditPaymentTransfer),
        ),
        _kv(
          'Balance credito',
          _money.format(snapshot.summary.creditBalanceTotal),
        ),
      ],
      if (snapshot.summary.categorySummary.isNotEmpty) ...[
        _divider(),
        _section('Resumen por categoria'),
        for (final category in snapshot.summary.categorySummary.take(8))
          _category(category),
      ],
      _divider(),
      _section('Cuadre final'),
      _kv('Efectivo esperado', _money.format(snapshot.summary.expectedCash)),
      _kv('Efectivo contado', _money.format(snapshot.closingAmount)),
      _highlightTotal('Diferencia', _money.format(snapshot.difference)),
      _kv('Tickets', snapshot.summary.totalTickets.toString()),
      _kv('Devoluciones', snapshot.summary.totalRefunds.toString()),
      if ((snapshot.note ?? '').trim().isNotEmpty) ...[
        _divider(),
        _section('Nota interna'),
        _paragraph(snapshot.note!.trim()),
      ],
      if (snapshot.movements.isNotEmpty) ...[
        _divider(),
        _section('Movimientos manuales'),
        for (final movement in snapshot.movements.take(12)) _movement(movement),
        if (snapshot.movements.length > 12)
          _paragraph('+${snapshot.movements.length - 12} movimientos mas'),
      ],
      _footer(),
    ];
    return _document(ticketNumber, rows);
  }

  Future<Uint8List> buildHistory(
    CashSessionHistoryModel row, {
    required String ticketNumber,
  }) async {
    final rows = <pw.Widget>[
      _header('REIMPRESION CIERRE', 'Comprobante historico de caja'),
      _section('Datos del turno'),
      _kv('No. cierre', ticketNumber, boldValue: true),
      _kv('Dia negocio', row.businessDate),
      _kv('Cajero', row.userName),
      _kv('Apertura', _date.format(row.openedAt.toLocal())),
      _kv(
        'Cierre',
        row.closedAt == null
            ? 'Sin cierre'
            : _date.format(row.closedAt!.toLocal()),
      ),
      _kv('Estado', row.status),
      _divider(),
      _section('Cuadre final'),
      _kv('Base inicial', _money.format(row.initialAmount)),
      _kv('Efectivo esperado', _money.format(row.expectedAmount)),
      _kv('Efectivo contado', _money.format(row.closingAmount)),
      _highlightTotal('Diferencia', _money.format(row.difference)),
      _footer(),
    ];
    return _document(ticketNumber, rows);
  }

  Future<Uint8List> _document(String ticketNumber, List<pw.Widget> rows) async {
    final doc = pw.Document(author: 'FullTech', title: ticketNumber);
    final pageWidth = layout.printableWidthMm * PdfPageFormat.mm;
    final marginLeft = layout.leftMargin.clamp(0, 4) * PdfPageFormat.mm;
    final marginRight = layout.rightMargin.clamp(0, 4) * PdfPageFormat.mm;
    final pageHeight = math
        .max(145 * PdfPageFormat.mm, rows.length * 14.0 + 180)
        .clamp(145 * PdfPageFormat.mm, 2000 * PdfPageFormat.mm)
        .toDouble();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.only(
          left: marginLeft,
          right: marginRight,
          top: 6,
          bottom: 8,
        ),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          mainAxisSize: pw.MainAxisSize.min,
          children: rows,
        ),
      ),
    );
    return doc.save();
  }

  ({pw.Font regular, pw.Font bold}) _loadFonts() {
    return (regular: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
  }

  pw.Widget _header(String title, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (layout.showLogo && company.logoBytes != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Center(
              child: pw.Image(
                pw.MemoryImage(company.logoBytes!),
                width: layout.paperWidthMm == 58 ? 38 : 46,
                height: layout.paperWidthMm == 58 ? 38 : 46,
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        pw.Text(
          company.name.toUpperCase(),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: _fonts.bold, fontSize: _fontSize + 3.2),
        ),
        if (company.rnc.trim().isNotEmpty)
          _centerSmall('RNC: ${company.rnc.trim()}'),
        if (company.phone.trim().isNotEmpty)
          _centerSmall('TEL: ${company.phone.trim()}'),
        if (company.address.trim().isNotEmpty)
          _centerSmall(company.address.trim()),
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 7, bottom: 7),
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 5),
          decoration: const pw.BoxDecoration(color: PdfColors.grey900),
          child: pw.Column(
            children: [
              pw.Text(
                title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: _fonts.bold,
                  fontSize: _fontSize + 2,
                  color: PdfColors.white,
                ),
              ),
              pw.SizedBox(height: 1.5),
              pw.Text(
                subtitle.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: _fonts.regular,
                  fontSize: _fontSize - 0.8,
                  color: PdfColors.grey200,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _centerSmall(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 1),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: _fonts.regular, fontSize: _fontSize - 0.4),
      ),
    );
  }

  pw.Widget _section(String label) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
      child: pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          font: _fonts.bold,
          fontSize: _fontSize + 0.6,
          color: PdfColors.grey900,
        ),
      ),
    );
  }

  pw.Widget _kv(String label, String value, {bool boldValue = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 9,
            child: pw.Text(
              label,
              style: pw.TextStyle(font: _fonts.regular, fontSize: _fontSize),
            ),
          ),
          pw.SizedBox(width: 5),
          pw.Expanded(
            flex: 11,
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                font: boldValue ? _fonts.bold : _fonts.regular,
                fontSize: _fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _highlightTotal(String label, String value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 3, bottom: 5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey900, width: 1),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              label.toUpperCase(),
              style: pw.TextStyle(font: _fonts.bold, fontSize: _fontSize + 0.6),
            ),
          ),
          pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: pw.TextStyle(font: _fonts.bold, fontSize: _fontSize + 1.2),
          ),
        ],
      ),
    );
  }

  pw.Widget _category(CashCategorySummaryModel category) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            category.category,
            style: pw.TextStyle(font: _fonts.bold, fontSize: _fontSize),
          ),
          _kv('Vendido', _money.format(category.totalSold)),
          _kv('Ganancia', _money.format(category.totalProfit)),
        ],
      ),
    );
  }

  pw.Widget _movement(CashMovementModel movement) {
    final label = switch (movement.movementType) {
      'expense' => 'Gasto',
      'owner_draw' => 'Retiro',
      'transfer' => movement.isIn ? 'Entrada' : 'Transfer.',
      _ => movement.isIn ? 'Entrada' : 'Salida',
    };
    final amount =
        '${movement.isIn ? '+' : '-'}${_money.format(movement.amount)}';
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.4),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _kv(label, amount, boldValue: true),
          if (movement.reason.trim().isNotEmpty)
            _paragraph(movement.reason.trim(), compact: true),
        ],
      ),
    );
  }

  pw.Widget _paragraph(String text, {bool compact = false}) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(bottom: compact ? 2 : 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: _fonts.regular,
          fontSize: compact ? _fontSize - 0.2 : _fontSize,
          height: 1.15,
        ),
      ),
    );
  }

  pw.Widget _footer() {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Text(
        'Documento generado por FullPOS Cloud',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: _fonts.regular,
          fontSize: _fontSize - 0.8,
          color: PdfColors.grey700,
        ),
      ),
    );
  }

  pw.Widget _divider() {
    return pw.Container(
      height: 0.8,
      margin: const pw.EdgeInsets.symmetric(vertical: 5),
      color: PdfColors.grey500,
    );
  }

  double get _fontSize {
    final base = layout.paperWidthMm == 58 ? 7.2 : 8.1;
    final adjusted = base + ((layout.fontSizeLevel.clamp(1, 10) - 5) * 0.16);
    return adjusted.clamp(6.4, 9.8).toDouble();
  }
}
