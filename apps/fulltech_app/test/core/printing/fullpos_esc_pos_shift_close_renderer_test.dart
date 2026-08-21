import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_shift_close_renderer.dart';
import 'package:daleventa_pos/core/printing/esc_pos/shift_close_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a professional close ticket with all official fields', () {
    final lines = _renderer.preview(
      _closeVm(
        cash: 10000,
        transfer: 2350,
        expected: 12350,
        declared: 12350,
        tickets: 12,
      ),
    );

    // Company header + title.
    expect(lines.any((l) => l.contains('FULLTECH, SRL')), isTrue);
    expect(lines.any((l) => l.contains('CIERRE DE TURNO')), isTrue);

    // DATOS DEL TURNO.
    expect(lines.any((l) => l.contains('DATOS DEL TURNO')), isTrue);
    expect(
      lines.any(
        (l) => l.contains('No. cierre') && l.contains('CIERRE-20260820-ABC123'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('Fecha cierre') && l.contains('20/08/2026'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('Cajero') && l.contains('Yunior López')),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('Apertura') && l.contains('20/08/2026 8:00 AM'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('Dia negocio') && l.contains('20/08/2026'),
      ),
      isTrue,
    );

    // VENTAS Y EFECTIVO.
    expect(lines.any((l) => l.contains('VENTAS Y EFECTIVO')), isTrue);
    expect(
      lines.any(
        (l) => l.contains('TOTAL VENDIDO') && l.contains('RD\$ 12,350.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('VENTAS EFECTIVO') && l.contains('RD\$ 10,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('TRANSFERENCIAS') && l.contains('RD\$ 2,350.00'),
      ),
      isTrue,
    );

    // CUADRE FINAL + DIFERENCIA.
    expect(lines.any((l) => l.contains('CUADRE FINAL')), isTrue);
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO ESPERADO') && l.contains('RD\$ 12,350.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO CONTADO') && l.contains('RD\$ 12,350.00'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('DIFERENCIA') && l.contains('RD\$ 0.00')),
      isTrue,
    );

    // CONTADORES.
    expect(
      lines.any((l) => l.trim().startsWith('Tickets') && l.endsWith('12')),
      isTrue,
    );
    expect(
      lines.any((l) => l.trim().startsWith('Devoluciones') && l.endsWith('0')),
      isTrue,
    );

    // Footer.
    expect(lines.any((l) => l.contains('FullPOS Cloud')), isTrue);
  });

  test('full fixture shows every section with all official amounts', () {
    final lines = _renderer.preview(
      _closeVm(
        opening: 2000,
        totalSales: 10000,
        cash: 5000,
        transfer: 3000,
        credit: 2000,
        creditBalance: 2000,
        manualIn: 500,
        expenses: 250,
        manualOut: 300,
        withdrawals: 1000,
        refunds: 200,
        expected: 9000,
        declared: 9000,
        difference: 0,
        tickets: 30,
        refundCount: 2,
        categories: const [
          ShiftCloseCategorySummary(
            categoryName: 'COMPUTADORAS Y POS',
            soldAmount: 4300,
            profitAmount: 1820,
          ),
          ShiftCloseCategorySummary(
            categoryName: 'SISTEMA DE VIGILANCIA',
            soldAmount: 8500,
            profitAmount: 2900,
          ),
          ShiftCloseCategorySummary(
            categoryName: 'SMART Y ACCESORIOS',
            soldAmount: 944,
            profitAmount: 644,
          ),
        ],
      ),
    );

    expect(lines.any((l) => l.contains('DATOS DEL TURNO')), isTrue);
    expect(lines.any((l) => l.contains('VENTAS Y EFECTIVO')), isTrue);
    expect(lines.any((l) => l.contains('CREDITO')), isTrue);
    expect(lines.any((l) => l.contains('RESUMEN POR CATEGORIA')), isTrue);
    expect(lines.any((l) => l.contains('CUADRE FINAL')), isTrue);

    // VENTAS Y EFECTIVO (todos, incluidos los distintos de cero).
    expect(
      lines.any((l) => l.contains('BASE INICIAL') && l.contains('RD\$ 2,000.00')),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('TOTAL VENDIDO') && l.contains('RD\$ 10,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('VENTAS EFECTIVO') && l.contains('RD\$ 5,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('TRANSFERENCIAS') && l.contains('RD\$ 3,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('ENTRADAS MANUALES') && l.contains('RD\$ 500.00'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('GASTOS') && l.contains('RD\$ 250.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('SALIDAS') && l.contains('RD\$ 300.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('RETIROS') && l.contains('RD\$ 1,000.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('DEVOLUCIONES') && l.contains('RD\$ 200.00')),
      isTrue,
    );

    // CRÉDITO.
    expect(
      lines.any(
        (l) => l.contains('VENTAS CREDITO') && l.contains('RD\$ 2,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('BALANCE CREDITO') && l.contains('RD\$ 2,000.00'),
      ),
      isTrue,
    );

    // RESUMEN POR CATEGORÍA (todas las categorías con movimiento).
    expect(lines.any((l) => l.contains('COMPUTADORAS Y POS')), isTrue);
    expect(
      lines.any((l) => l.contains('VENDIDO') && l.contains('RD\$ 4,300.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('GANANCIA') && l.contains('RD\$ 1,820.00')),
      isTrue,
    );
    expect(lines.any((l) => l.contains('SISTEMA DE VIGILANCIA')), isTrue);
    expect(
      lines.any((l) => l.contains('GANANCIA') && l.contains('RD\$ 2,900.00')),
      isTrue,
    );
    expect(lines.any((l) => l.contains('SMART Y ACCESORIOS')), isTrue);
    expect(
      lines.any((l) => l.contains('VENDIDO') && l.contains('RD\$ 944.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('GANANCIA') && l.contains('RD\$ 644.00')),
      isTrue,
    );

    // CUADRE FINAL.
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO ESPERADO') && l.contains('RD\$ 9,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO CONTADO') && l.contains('RD\$ 9,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('DIFERENCIA') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.trim().startsWith('Tickets') && l.endsWith('30')),
      isTrue,
    );
    expect(
      lines.any((l) => l.trim().startsWith('Devoluciones') && l.endsWith('2')),
      isTrue,
    );
  });

  test('zero case still prints every control-cash line', () {
    final lines = _renderer.preview(
      _closeVm(
        opening: 0,
        totalSales: 944,
        cash: 944,
        transfer: 0,
        credit: 0,
        manualIn: 0,
        expenses: 0,
        manualOut: 0,
        withdrawals: 0,
        refunds: 0,
        expected: 944,
        declared: 944,
        difference: 0,
        tickets: 1,
        refundCount: 0,
        categories: const [
          ShiftCloseCategorySummary(
            categoryName: 'SMART Y ACCESORIOS',
            soldAmount: 944,
            profitAmount: 644,
          ),
        ],
      ),
    );

    // Valores cero de control de caja SIEMPRE visibles.
    expect(
      lines.any((l) => l.contains('BASE INICIAL') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('TRANSFERENCIAS') && l.contains('RD\$ 0.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('ENTRADAS MANUALES') && l.contains('RD\$ 0.00'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('GASTOS') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('SALIDAS') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('RETIROS') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('DEVOLUCIONES') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO ESPERADO') && l.contains('RD\$ 944.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO CONTADO') && l.contains('RD\$ 944.00'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('DIFERENCIA') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.trim().startsWith('Tickets') && l.endsWith('1')),
      isTrue,
    );
    // Categoría de la foto.
    expect(lines.any((l) => l.contains('SMART Y ACCESORIOS')), isTrue);
    expect(
      lines.any((l) => l.contains('VENDIDO') && l.contains('RD\$ 944.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('GANANCIA') && l.contains('RD\$ 644.00')),
      isTrue,
    );
  });

  test('shows credit section only when there are credit sales', () {
    final withoutCredit = _renderer.preview(_closeVm(credit: 0));
    final withCredit = _renderer.preview(
      _closeVm(credit: 2000, creditBalance: 2000),
    );

    expect(
      withoutCredit.any((l) => l.trim().startsWith('CREDITO')),
      isFalse,
    );
    expect(withCredit.any((l) => l.trim().startsWith('CREDITO')), isTrue);
  });

  test('supports positive and negative difference signs', () {
    final positive = _renderer.preview(
      _closeVm(expected: 12000, declared: 12350, difference: 350),
    );
    final negative = _renderer.preview(
      _closeVm(expected: 12500, declared: 12350, difference: -150),
    );

    expect(
      positive.any((l) => l.contains('DIFERENCIA') && l.contains('RD\$ 350.00')),
      isTrue,
    );
    expect(
      negative.any(
        (l) => l.contains('DIFERENCIA') && l.contains('RD\$ -150.00'),
      ),
      isTrue,
    );
  });

  test('prints the real cashier and never a sync placeholder', () {
    final lines = _renderer.preview(
      _closeVm(cashier: 'Maria De Los Santos'),
    );

    expect(
      lines.any(
        (l) => l.contains('Cajero') && l.contains('Maria De Los Santos'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('PENDIENTE DE SINCRONIZAR')),
      isFalse,
    );
  });

  test('never invents TARJETA or other non-official methods', () {
    final lines = _renderer.preview(_closeVm());

    expect(lines.any((l) => l.contains('TARJETA')), isFalse);
    expect(lines.any((l) => l.contains('OTROS')), isFalse);
  });

  test('omits empty optional fields without noise', () {
    final lines = _renderer.preview(
      _closeVm(
        cashier: '',
        shiftId: '',
        cashId: '',
        businessDate: '',
        includeOpenedAt: false,
        includeClosedAt: false,
        status: '',
        note: null,
        totalSales: 0,
        cash: 0,
        expected: 0,
        declared: 0,
        tickets: 0,
        refundCount: 0,
        categories: const [],
      ),
    );

    expect(lines.any((l) => l.contains('Cajero')), isFalse);
    expect(lines.any((l) => l.contains('Turno')), isFalse);
    expect(lines.any((l) => l.contains('Caja')), isFalse);
    expect(lines.any((l) => l.contains('Dia negocio')), isFalse);
    expect(lines.any((l) => l.contains('Apertura')), isFalse);
    expect(lines.any((l) => l.contains('Estado')), isFalse);
    expect(lines.any((l) => l.contains('NOTA')), isFalse);
    expect(lines.any((l) => l.trim().startsWith('CREDITO')), isFalse);
    expect(lines.any((l) => l.contains('RESUMEN POR CATEGORIA')), isFalse);
    expect(lines.any((l) => l.contains('MOVIMIENTOS')), isFalse);
    // Las secciones de control de caja SIEMPRE existen.
    expect(lines.any((l) => l.contains('VENTAS Y EFECTIVO')), isTrue);
    expect(
      lines.any((l) => l.contains('BASE INICIAL') && l.contains('RD\$ 0.00')),
      isTrue,
    );
    expect(lines.any((l) => l.contains('CUADRE FINAL')), isTrue);
    expect(
      lines.any((l) => l.contains('DIFERENCIA') && l.contains('RD\$ 0.00')),
      isTrue,
    );
  });

  test('renders note and manual movements when present', () {
    final lines = _renderer.preview(
      _closeVm(
        note: 'Entregar después de las 3:00 PM.',
        movements: const [
          ShiftCloseMovement(
            label: 'Gasto',
            amount: 250,
            isIn: false,
            reason: 'Compra de insumos',
          ),
          ShiftCloseMovement(label: 'Entrada', amount: 500, isIn: true),
        ],
      ),
    );

    expect(
      lines.any((l) => l.contains('Entregar después de las 3:00 PM.')),
      isTrue,
    );
    expect(lines.any((l) => l.contains('MOVIMIENTOS')), isTrue);
    expect(
      lines.any((l) => l.contains('Gasto') && l.contains('-RD\$ 250.00')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('Entrada') && l.contains('+RD\$ 500.00')),
      isTrue,
    );
    expect(lines.any((l) => l.contains('Compra de insumos')), isTrue);
  });

  test('never prints cash register or shift ids', () {
    final lines = _renderer.preview(
      _closeVm(cashId: 'CAJA-001', shiftId: 'SHIFT-20260820-001'),
    );

    expect(lines.any((l) => l.contains('Caja')), isFalse);
    expect(lines.any((l) => l.contains('Turno')), isFalse);
  });

  test('never prints warranty policy on the shift-close ticket', () {
    final lines = _renderer.preview(_closeVm());

    expect(lines.any((l) => l.contains('POLITICA DE GARANTIA')), isFalse);
  });

  test('renders a historical reprint from the official history model', () {
    final vm = _historyVm(
      status: 'CLOSED',
      cashier: 'Yunior López',
      initial: 1000,
      expected: 14000,
      declared: 13950,
      difference: -50,
    );
    final lines = _renderer.preview(vm);

    expect(lines.any((l) => l.contains('REIMPRESION CIERRE')), isTrue);
    expect(
      lines.any((l) => l.contains('Cajero') && l.contains('Yunior López')),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('Estado') && l.contains('CLOSED')),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('BASE INICIAL') && l.contains('RD\$ 1,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO ESPERADO') && l.contains('RD\$ 14,000.00'),
      ),
      isTrue,
    );
    expect(
      lines.any(
        (l) => l.contains('EFECTIVO CONTADO') && l.contains('RD\$ 13,950.00'),
      ),
      isTrue,
    );
    expect(
      lines.any((l) => l.contains('DIFERENCIA') && l.contains('RD\$ -50.00')),
      isTrue,
    );
    // La reimpresión histórica no tiene desglose de ventas.
    expect(lines.any((l) => l.contains('VENTAS Y EFECTIVO')), isFalse);
    expect(lines.any((l) => l.contains('RESUMEN POR CATEGORIA')), isFalse);
    expect(lines.any((l) => l.trim().startsWith('Tickets')), isFalse);
  });

  test('renders bytes with Spanish characters using CP1252', () async {
    final bytes = await _renderer.render(
      _closeVm(
        cashier: 'Yunior López',
        company: const CompanyInfo(
          name: 'FULLTECH, SRL',
          address: 'Centro Calle Beller 9, Higüey',
        ),
      ),
    );

    expect(bytes, isNotEmpty);
    expect(bytes, contains(0xF3)); // ó (López) in latin1/CP1252.
    expect(bytes, contains(0xFC)); // ü (Higüey) in latin1/CP1252.
  });

  test('cuts exactly once', () async {
    final bytes = await _renderer.render(_closeVm());

    expect(_cutCommandCount(bytes), 1);
  });
}

final _renderer = FullPosEscPosShiftCloseRenderer(cutPaper: true);

int _cutCommandCount(List<int> bytes) {
  var count = 0;
  for (var i = 0; i < bytes.length - 2; i++) {
    if (bytes[i] == 0x1D && bytes[i + 1] == 0x56) {
      count++;
    }
  }
  return count;
}

ShiftCloseReceiptViewModel _closeVm({
  double opening = 0,
  double totalSales = 12350,
  double cash = 12350,
  double transfer = 0,
  double credit = 0,
  double creditInitialCash = 0,
  double creditInitialTransfer = 0,
  double creditPaymentCash = 0,
  double creditPaymentTransfer = 0,
  double creditBalance = 0,
  double manualIn = 0,
  double expenses = 0,
  double manualOut = 0,
  double withdrawals = 0,
  double refunds = 0,
  double expected = 12350,
  double declared = 12350,
  double difference = 0,
  int tickets = 12,
  int refundCount = 0,
  String cashier = 'Yunior López',
  String shiftId = 'SHIFT-20260820-001',
  String cashId = 'CAJA-001',
  String businessDate = '20/08/2026',
  bool includeOpenedAt = true,
  DateTime? openedAt,
  bool includeClosedAt = true,
  DateTime? closedAt,
  String status = '',
  String? note,
  bool showSalesDetails = true,
  List<ShiftCloseCategorySummary> categories = const [],
  List<ShiftCloseMovement>? movements,
  CompanyInfo company = const CompanyInfo(
    name: 'FULLTECH, SRL',
    address: 'Higüey',
    phone: '809-000-0000',
    rnc: '131000000',
  ),
}) {
  return ShiftCloseReceiptViewModel(
    company: company,
    title: 'CIERRE DE TURNO',
    ticketNumber: 'CIERRE-20260820-ABC123',
    cashierName: cashier,
    shiftId: shiftId,
    cashId: cashId,
    businessDate: businessDate,
    openedAt: includeOpenedAt
        ? (openedAt ?? DateTime(2026, 8, 20, 8, 0))
        : null,
    closedAt: includeClosedAt
        ? (closedAt ?? DateTime(2026, 8, 20, 20, 30))
        : null,
    capturedAt: DateTime(2026, 8, 20, 20, 30),
    showSalesDetails: showSalesDetails,
    openingAmount: opening,
    totalSales: totalSales,
    cashSales: cash,
    transferSales: transfer,
    manualCashIn: manualIn,
    expenses: expenses,
    manualCashOut: manualOut,
    withdrawals: withdrawals,
    refunds: refunds,
    creditSales: credit,
    creditInitialCash: creditInitialCash,
    creditInitialTransfer: creditInitialTransfer,
    creditPaymentCash: creditPaymentCash,
    creditPaymentTransfer: creditPaymentTransfer,
    creditBalance: creditBalance,
    expectedCash: expected,
    countedCash: declared,
    difference: difference,
    ticketCount: tickets,
    refundCount: refundCount,
    categorySummaries: categories,
    status: status,
    note: note,
    movements: movements,
  );
}

ShiftCloseReceiptViewModel _historyVm({
  String cashier = 'Yunior López',
  String status = 'CLOSED',
  double initial = 1000,
  double expected = 14000,
  double declared = 13950,
  double difference = -50,
}) {
  return ShiftCloseReceiptViewModel(
    company: const CompanyInfo(
      name: 'FULLTECH, SRL',
      address: 'Higüey',
      phone: '809-000-0000',
      rnc: '131000000',
    ),
    title: 'REIMPRESION CIERRE',
    ticketNumber: 'CIERRE-20260820-ABC123',
    cashierName: cashier,
    shiftId: '',
    cashId: '',
    businessDate: '20/08/2026',
    openedAt: DateTime(2026, 8, 20, 8, 0),
    closedAt: DateTime(2026, 8, 20, 20, 30),
    capturedAt: DateTime(2026, 8, 20, 20, 30),
    showSalesDetails: false,
    openingAmount: initial,
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
    expectedCash: expected,
    countedCash: declared,
    difference: difference,
    ticketCount: 0,
    refundCount: 0,
    categorySummaries: const [],
    status: status,
    note: null,
    movements: null,
  );
}
