import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';

import 'esc_pos_layout.dart';
import 'shift_close_receipt_view_model.dart';
import 'thermal_printer_profile.dart';

/// Professional 80 mm ESC/POS shift-close ticket renderer.
///
/// It reuses the SAME shared layout primitives as the sales receipt renderer
/// (`ThermalPrinterProfile.mm80`, `EscPosLayout` alignment/padding/money
/// helpers, company header, separators, styles, wrap and cut pipeline), so the
/// shift-close ticket looks and prints like the professional sales ticket and
/// no padding logic is duplicated.
///
/// The renderer NEVER recalculates financial values: it consumes the official
/// `ShiftCloseReceiptViewModel` amounts. Warranty policy is intentionally NOT
/// printed on the shift-close (it belongs to sales documents only).
class FullPosEscPosShiftCloseRenderer {
  FullPosEscPosShiftCloseRenderer({
    ThermalPrinterProfile? profile,
    this.profileName = 'default',
    this.codeTable = 'CP1252',
    this.cutPaper = true,
  }) : profile = profile ?? ThermalPrinterProfile.mm80();

  final ThermalPrinterProfile profile;
  final String profileName;
  final String codeTable;
  final bool cutPaper;

  Future<Uint8List> render(ShiftCloseReceiptViewModel vm) {
    return EscPosLayout.renderLines(
      lines: _buildLines(vm),
      profile: profile,
      profileName: profileName,
      codeTable: codeTable,
      cutPaper: cutPaper,
    );
  }

  /// Text preview exactly as it will be printed (physical left-safe offset
  /// included), used by tests and diagnostics.
  List<String> preview(ShiftCloseReceiptViewModel vm) {
    return _buildLines(vm).map(
      (line) => EscPosLayout.layoutLine(profile, line.text, line.width),
    ).toList(growable: false);
  }

  List<EscPosLine> _buildLines(ShiftCloseReceiptViewModel vm) {
    final lines = <EscPosLine>[];
    final normalA = EscPosLayout.normalA(codeTable: codeTable);
    final boldA = EscPosLayout.boldA(codeTable: codeTable);
    final normalB = EscPosLayout.normalB(codeTable: codeTable);
    final boldB = EscPosLayout.boldB(codeTable: codeTable);

    void addB(String text, {PosStyles? styles}) {
      lines.add(EscPosLine(text, styles ?? normalB, profile.usableChars));
    }

    void addA(String text, {PosStyles? styles}) {
      lines.add(EscPosLine(text, styles ?? normalA, profile.usableFontAChars));
    }

    void addRule() {
      addB(EscPosLayout.rule(profile, profile.usableChars), styles: normalB);
    }

    void addSection(String title) {
      addB(title, styles: boldB);
    }

    /// Meta label:value. Si el valor no cabe en dos columnas se usa su propia
    /// línea (wrap completo) para no truncar datos administrativos.
    void addMeta(String label, String value, {int rightWidth = 20}) {
      if (value.length <= rightWidth) {
        addB(
          EscPosLayout.twoColumnLine(
            profile,
            label,
            value,
            rightWidth: rightWidth,
          ),
        );
        return;
      }
      addB(label, styles: boldB);
      for (final line in EscPosLayout.wrapContent(
        value,
        profile.usableChars,
      )) {
        addB(line);
      }
    }

    void addMoney(String label, double amount) {
      addB(
        EscPosLayout.totalLine(profile, label, EscPosLayout.money(amount)),
        styles: normalB,
      );
    }

    // Cabecera de empresa elegante (sin logo, alineada a la izquierda):
    // nombre en negrita y datos de contacto.
    final companyName = EscPosLayout.clean(vm.company.name);
    if (companyName.isNotEmpty) {
      final headerLines = EscPosLayout.companyHeaderLines(
        profile,
        companyName: companyName,
        address: vm.company.address,
        phone: vm.company.phone,
        rnc: vm.company.rnc,
      );
      for (var i = 0; i < headerLines.length; i++) {
        addB(headerLines[i], styles: i == 0 ? boldB : normalB);
      }
      addRule();
    }

    addB(EscPosLayout.centerContent(profile, vm.title), styles: boldB);
    addRule();

    // 1) DATOS DEL TURNO.
    addSection('DATOS DEL TURNO');
    addMeta('No. cierre', vm.ticketNumber, rightWidth: 22);
    addMeta('Fecha cierre', _dateTime.format(vm.capturedAt.toLocal()));
    if (vm.businessDate.trim().isNotEmpty) {
      addMeta('Dia negocio', vm.businessDate.trim());
    }
    if (vm.cashierName.trim().isNotEmpty) {
      addMeta('Cajero', vm.cashierName.trim());
    }
    if (vm.openedAt != null) {
      addMeta('Apertura', _dateTime.format(vm.openedAt!.toLocal()));
    }
    if (vm.status.trim().isNotEmpty) {
      addMeta('Estado', vm.status.trim());
    }

    // 2) VENTAS Y EFECTIVO (campos de control de caja: SIEMPRE, incluso 0).
    if (vm.showSalesDetails) {
      addRule();
      addSection('VENTAS Y EFECTIVO');
      addMoney('Base inicial', vm.openingAmount);
      addMoney('Total vendido', vm.totalSales);
      addMoney('Ventas efectivo', vm.cashSales);
      addMoney('Transferencias', vm.transferSales);
      addMoney('Entradas manuales', vm.manualCashIn);
      addMoney('Gastos', vm.expenses);
      addMoney('Salidas', vm.manualCashOut);
      addMoney('Retiros', vm.withdrawals);
      addMoney('Devoluciones', vm.refunds);

      // CRÉDITO (solo si el cierre oficial tiene ventas a crédito).
      if (vm.creditSales > 0) {
        addRule();
        addSection('CREDITO');
        addMoney('Ventas credito', vm.creditSales);
        addMoney('Inicial efectivo', vm.creditInitialCash);
        addMoney('Inicial transf.', vm.creditInitialTransfer);
        addMoney('Abonos efectivo', vm.creditPaymentCash);
        addMoney('Abonos transf.', vm.creditPaymentTransfer);
        addMoney('Balance credito', vm.creditBalance);
      }

      // RESUMEN POR CATEGORÍA (fuente oficial ya calculada).
      if (vm.categorySummaries.isNotEmpty) {
        addRule();
        addSection('RESUMEN POR CATEGORIA');
        for (final category in vm.categorySummaries) {
          addB(
            EscPosLayout.centerContent(profile, category.categoryName),
            styles: boldB,
          );
          addMoney('Vendido', category.soldAmount);
          addMoney('Ganancia', category.profitAmount);
        }
      }
    }

    // 3) CUADRE FINAL.
    addRule();
    addSection('CUADRE FINAL');
    if (!vm.showSalesDetails) {
      addMoney('Base inicial', vm.openingAmount);
    }
    addMoney('Efectivo esperado', vm.expectedCash);
    addMoney('Efectivo contado', vm.countedCash);
    addB(EscPosLayout.totalSeparator(profile), styles: normalB);
    addB(
      EscPosLayout.totalLine(
        profile,
        'DIFERENCIA',
        EscPosLayout.money(vm.difference),
      ),
      styles: boldB,
    );
    addB(EscPosLayout.totalSeparator(profile), styles: normalB);

    // CONTADORES (solo en cierre vivo con desglose).
    if (vm.showSalesDetails) {
      addRule();
      addMeta('Tickets', vm.ticketCount.toString(), rightWidth: 18);
      addMeta('Devoluciones', vm.refundCount.toString(), rightWidth: 18);
    }

    // NOTA.
    final note = EscPosLayout.clean(vm.note ?? '');
    if (note.isNotEmpty) {
      addRule();
      addA('NOTA', styles: boldA);
      for (final line in EscPosLayout.wrapContent(
        note,
        profile.usableFontAChars,
      )) {
        addA(line);
      }
    }

    // MOVIMIENTOS manuales.
    final movements = vm.movements ?? const <ShiftCloseMovement>[];
    if (movements.isNotEmpty) {
      addRule();
      addSection('MOVIMIENTOS');
      for (final movement in movements) {
        final sign = movement.isIn ? '+' : '-';
        addMeta(
          movement.label,
          '$sign${EscPosLayout.money(movement.amount)}',
          rightWidth: 20,
        );
        final reason = EscPosLayout.clean(movement.reason ?? '');
        if (reason.isNotEmpty) {
          for (final line in EscPosLayout.wrapContent(
            reason,
            profile.usableChars,
          )) {
            addB(line);
          }
        }
      }
    }

    addRule();
    addB(EscPosLayout.centerContent(profile, 'FullPOS Cloud'), styles: normalB);

    return lines;
  }

  static final _dateTime = DateFormat('dd/MM/yyyy h:mm a');
}
