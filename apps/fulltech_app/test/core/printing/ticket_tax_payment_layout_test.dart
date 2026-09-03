import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión TICKET-TAX-PAYMENT-LAYOUT-FIX-01:
/// cuando los impuestos/ITBIS están habilitados, el ticket debe mostrar
/// SUBTOTAL/ITBIS/TOTAL y luego un bloque de pago SEPARADO
/// (EFECTIVO RECIBIDO / DEVUELTA cuando aplica). Con impuestos apagados no
/// debe inventarse una fila ITBIS.
const _company = CompanyInfo(
  name: 'Fulltech, srl',
  rnc: '133080206',
  phone: '8295319442',
  address: 'Higuey Beller 9',
);

SaleItemModel _item({double subtotal = 1000, double tax = 180}) {
  return SaleItemModel(
    id: 'i1',
    productId: 'p1',
    productNameSnapshot: 'ARTICULO GRAVADO',
    productImageSnapshot: null,
    qty: 1,
    priceSoldUnit: subtotal,
    costUnitSnapshot: subtotal * 0.5,
    subtotalSold: subtotal,
    subtotalCost: subtotal * 0.5,
    profit: subtotal * 0.5,
    category: null,
    taxableBase: subtotal,
    taxAmount: tax,
    exemptAmount: 0,
    taxExempt: false,
  );
}

SaleModel _sale({
  required String paymentMethod,
  required double paymentCashAmount,
  double? cashReceived,
  double? changeAmount,
  double totalSold = 1180,
  double taxableBase = 1000,
  double taxAmount = 180,
  double exemptAmount = 0,
  bool fiscalTaxEnabled = true,
  String? ncf,
  String? fiscalVoucherType,
}) {
  return SaleModel(
    id: 'sale-28201760',
    userId: 'u1',
    userName: 'Caja',
    customerId: null,
    customerName: null,
    customerPhone: null,
    saleDate: DateTime(2026, 9, 2, 10),
    note: null,
    totalSold: totalSold,
    totalCost: totalSold * 0.5,
    totalProfit: totalSold * 0.5,
    commissionAmount: 0,
    paymentMethod: paymentMethod,
    paymentCashAmount: paymentCashAmount,
    paymentTransferAmount: paymentMethod == 'transfer' ? totalSold : 0,
    cashReceived: cashReceived,
    changeAmount: changeAmount,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalTaxEnabled: fiscalTaxEnabled,
    fiscalPriceMode: 'NO_TAX',
    taxableBase: taxableBase,
    taxAmount: taxAmount,
    exemptAmount: exemptAmount,
    discountAmount: 0,
    fiscalVoucherType: fiscalVoucherType,
    ncf: ncf,
    items: [
      _item(
        subtotal: taxableBase > 0 ? taxableBase : totalSold,
        tax: taxAmount,
      ),
    ],
  );
}

TicketLayoutConfig _layout({required int mm, required int chars}) {
  return TicketLayoutConfig(
    paperWidthMm: mm,
    charsPerLine: chars,
    fontSize: 'normal',
    fontFamily: 'monospace',
    showLogo: true,
    logoSize: 80,
    showBusinessData: true,
    showItbis: true,
    showCashier: true,
    showClient: true,
    showPaymentMethod: true,
    showDiscounts: true,
    showCode: true,
    showDatetime: true,
    showSubtotalItbisTotal: true,
    footerMessage: 'Gracias por su preferencia!',
    warrantyPolicy: '',
    headerExtra: '',
    headerBusinessName: '',
    headerRnc: '',
    headerAddress: '',
    headerPhone: '',
    fontSizeLevel: 1,
    lineSpacingLevel: 1,
    sectionSpacingLevel: 1,
    headerAlignment: 'left',
    detailsAlignment: 'left',
    totalsAlignment: 'right',
    topMargin: 12,
    bottomMargin: 12,
    leftMargin: 4,
    rightMargin: 4,
    sectionSeparatorStyle: 'dashed',
  );
}

List<String> _renderLines(TicketData data, {int mm = 80, int chars = 48}) {
  return TicketRenderer(
    layout: _layout(mm: mm, chars: chars),
    company: _company,
  ).buildLines(data);
}

ThermalReceiptViewModel _escVm({
  double taxAmount = 180,
  double taxableBase = 1000,
  double? cashReceived,
  double? changeAmount,
  String paymentMethod = 'EFECTIVO',
}) {
  return ThermalReceiptViewModel(
    ticketNumber: '81472316',
    dateTime: DateTime(2026, 9, 2, 12),
    documentTitle: 'FACTURA',
    company: const CompanyInfo(
      name: 'FULLTECH, SRL',
      address: 'Centro Calle Beller 9 Local N2, Higüey',
      phone: '809-555-0000',
      rnc: '131000000',
    ),
    items: const [],
    subtotal: 1000,
    productDiscount: 0,
    generalDiscount: 0,
    taxableBase: taxableBase,
    exemptAmount: 0,
    taxAmount: taxAmount,
    total: 1180,
    fiscalTaxEnabled: taxAmount > 0,
    taxIncluded: false,
    paymentMethod: paymentMethod,
    cashReceived: cashReceived,
    changeAmount: changeAmount,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Tax section survives with a separated payment block', () {
    test('80mm taxes enabled + cash over-tender: SUBTOTAL/ITBIS/TOTAL then '
        'separated EFECTIVO RECIBIDO/DEVUELTA', () {
      final sale = _sale(
        paymentMethod: 'cash',
        paymentCashAmount: 1180,
        cashReceived: 1500,
        changeAmount: 320,
      );
      final lines = _renderLines(TicketData.fromSale(sale));

      expect(lines.any((l) => l.contains('Subtotal')), isTrue);
      expect(lines.any((l) => l.contains('ITBIS')), isTrue);
      final itbisIdx = lines.indexWhere((l) => l.contains('ITBIS'));
      final totalIdx = lines.indexWhere((l) => l.contains('TOTAL'));
      expect(itbisIdx, lessThan(totalIdx));
      expect(lines.any((l) => l.contains('EFECTIVO RECIBIDO')), isTrue);
      expect(lines.any((l) => l.contains('DEVUELTA')), isTrue);

      // Payment block appears BELOW TOTAL with a blank line separating it
      // from the totals (visual separation, not part of the tax calculation).
      final pagoIdx = lines.indexWhere((l) => l.trimLeft().startsWith('Pago'));
      expect(pagoIdx, greaterThan(totalIdx));
      expect(
        lines.sublist(totalIdx + 1, pagoIdx).any((l) => l.trim().isEmpty),
        isTrue,
        reason: 'expected a blank/separator line between TOTAL and payment',
      );
      expect(
        lines.any(
          (l) => l.contains('EFECTIVO RECIBIDO') && l.contains('1,500.00'),
        ),
        isTrue,
      );
      expect(
        lines.any((l) => l.contains('DEVUELTA') && l.contains('320.00')),
        isTrue,
      );
      expect(lines.every((l) => l.length <= 48), isTrue);
    });

    test('58mm taxes enabled + exact cash stays compact with tax rows', () {
      final sale = _sale(
        paymentMethod: 'cash',
        paymentCashAmount: 1180,
        cashReceived: 1180,
        changeAmount: 0,
        totalSold: 1180,
      );
      final lines = _renderLines(TicketData.fromSale(sale), mm: 58, chars: 30);
      expect(lines.any((l) => l.contains('ITBIS')), isTrue);
      expect(lines.any((l) => l.contains('TOTAL')), isTrue);
      expect(lines.any((l) => l.contains('EFECTIVO RECIBIDO')), isTrue);
      expect(lines.every((l) => l.length <= 30), isTrue);
    });

    test('transfer + ITBIS: tax rows appear and no fake cash rows', () {
      final sale = _sale(
        paymentMethod: 'transfer',
        paymentCashAmount: 0,
        cashReceived: 0,
        changeAmount: 0,
      );
      final lines = _renderLines(TicketData.fromSale(sale));
      expect(lines.any((l) => l.contains('ITBIS')), isTrue);
      expect(lines.any((l) => l.contains('TOTAL')), isTrue);
      expect(lines.any((l) => l.contains('EFECTIVO RECIBIDO')), isFalse);
      expect(lines.any((l) => l.contains('DEVUELTA')), isFalse);
    });

    test('taxes disabled: no fake ITBIS row', () {
      final sale = _sale(
        paymentMethod: 'cash',
        paymentCashAmount: 1000,
        cashReceived: 1000,
        changeAmount: 0,
        totalSold: 1000,
        taxableBase: 0,
        taxAmount: 0,
        exemptAmount: 0,
        fiscalTaxEnabled: false,
      );
      final lines = _renderLines(TicketData.fromSale(sale));
      expect(lines.any((l) => l.contains('ITBIS')), isFalse);
      expect(lines.any((l) => l.contains('Monto gravado')), isFalse);
      expect(lines.any((l) => l.contains('TOTAL')), isTrue);
    });

    test('fiscal NCF ticket keeps fiscal header and tax rows', () {
      final sale = _sale(
        paymentMethod: 'cash',
        paymentCashAmount: 1180,
        cashReceived: 1180,
        changeAmount: 0,
        ncf: 'B0100000003',
        fiscalVoucherType: 'B01',
      );
      final ticket = TicketData.fromSale(sale);
      expect(ticket.ncf, 'B0100000003');
      final lines = _renderLines(ticket);
      expect(lines.any((l) => l.contains('NCF')), isTrue);
      expect(lines.any((l) => l.contains('ITBIS')), isTrue);
      expect(lines.any((l) => l.contains('TOTAL')), isTrue);
    });

    test('reprint keeps tax rows and original cash tender/change', () {
      final sale = _sale(
        paymentMethod: 'cash',
        paymentCashAmount: 1180,
        cashReceived: 1500,
        changeAmount: 320,
      );
      final original = TicketData.fromSale(sale);
      final reprint = TicketData.fromSale(sale, isCopy: true);
      expect(reprint.itbis, original.itbis);
      expect(reprint.taxableBase, original.taxableBase);
      expect(reprint.cashReceived, 1500);
      expect(reprint.changeAmount, 320);
      final lines = _renderLines(reprint);
      expect(lines.any((l) => l.contains('ITBIS')), isTrue);
      expect(lines.any((l) => l.contains('EFECTIVO RECIBIDO')), isTrue);
    });
  });

  group('ESC/POS renderer tax + payment rows', () {
    final renderer = FullPosEscPosReceiptRenderer(cutPaper: false);

    test('shows SUBTOTAL/ITBIS/TOTAL and separated cash rows', () {
      final lines = renderer.previewLines(
        _escVm(cashReceived: 1500, changeAmount: 320),
      );
      expect(lines.any((l) => l.contains('SUBTOTAL')), isTrue);
      expect(lines.any((l) => l.contains('ITBIS')), isTrue);
      expect(lines.any((l) => l.contains('TOTAL')), isTrue);
      expect(
        lines.any(
          (l) => l.contains('EFECTIVO RECIBIDO') && l.contains('1,500.00'),
        ),
        isTrue,
      );
      expect(
        lines.any((l) => l.contains('DEVUELTA') && l.contains('320.00')),
        isTrue,
      );
    });

    test('omits ITBIS when taxes disabled', () {
      final lines = renderer.previewLines(_escVm(taxAmount: 0, taxableBase: 0));
      expect(lines.any((l) => l.contains('ITBIS')), isFalse);
      expect(lines.any((l) => l.contains('SUBTOTAL')), isTrue);
    });
  });

  group('HTML renderer tax + payment rows', () {
    test('renders tax rows before the payment block', () {
      final html = const HtmlThermalReceiptRenderer().render(
        _escVm(
          cashReceived: 1500,
          changeAmount: 320,
          paymentMethod: 'Efectivo',
        ),
      );
      expect(html, contains('SUBTOTAL'));
      expect(html, contains('ITBIS'));
      expect(html, contains('TOTAL'));
      expect(html, contains('EFECTIVO RECIBIDO'));
      expect(html, contains('DEVUELTA'));
      final sub = html.indexOf('SUBTOTAL');
      final pay = html.indexOf('EFECTIVO RECIBIDO');
      expect(pay, greaterThan(sub));
    });

    test('no ITBIS when taxes disabled', () {
      final html = const HtmlThermalReceiptRenderer().render(
        _escVm(taxAmount: 0, taxableBase: 0, paymentMethod: 'Efectivo'),
      );
      expect(html, isNot(contains('ITBIS')));
    });
  });
}
