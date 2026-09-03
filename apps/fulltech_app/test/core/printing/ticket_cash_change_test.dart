import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';

SaleModel _sale({
  required double totalSold,
  String paymentMethod = 'cash',
  double paymentCashAmount = 0,
  double paymentTransferAmount = 0,
  double? cashReceived,
  double? changeAmount,
  String? ncf,
  String? fiscalVoucherType,
}) {
  return SaleModel(
    id: 'sale-28201760',
    userId: 'user-1',
    userName: 'Caja',
    customerId: null,
    customerName: null,
    customerPhone: null,
    saleDate: DateTime(2026, 8, 2, 10),
    note: null,
    totalSold: totalSold,
    totalCost: totalSold * 0.5,
    totalProfit: totalSold * 0.5,
    commissionAmount: 0,
    paymentMethod: paymentMethod,
    paymentCashAmount: paymentCashAmount,
    paymentTransferAmount: paymentTransferAmount,
    cashReceived: cashReceived,
    changeAmount: changeAmount,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalVoucherType: fiscalVoucherType,
    ncf: ncf,
    items: const [],
  );
}

TicketLayoutConfig _layout({required int paperWidthMm, required int chars}) {
  return TicketLayoutConfig(
    paperWidthMm: paperWidthMm,
    charsPerLine: chars,
    fontSize: 'normal',
    fontFamily: 'monospace',
    showLogo: true,
    logoSize: 80,
    showBusinessData: true,
    showItbis: false,
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

const _company = CompanyInfo(
  name: 'Fulltech, srl',
  rnc: '133080206',
  phone: '8295319442',
  address: 'Higuey Beller 9',
);

List<String> _render(TicketData data, {int mm = 80, int chars = 48}) {
  return TicketRenderer(
    layout: _layout(paperWidthMm: mm, chars: chars),
    company: _company,
  ).buildLines(data);
}

Map<String, dynamic> _json() => {
      'id': 'sale-1',
      'userId': 'u-1',
      'userName': 'Caja',
      'customerId': null,
      'customerName': null,
      'customerPhone': null,
      'saleDate': '2026-09-01T10:00:00.000Z',
      'note': null,
      'totalSold': 850,
      'totalCost': 425,
      'totalProfit': 425,
      'commissionAmount': 0,
      'paymentMethod': 'cash',
      'paymentCashAmount': 850,
      'paymentTransferAmount': 0,
      'creditAmount': 0,
      'creditPaidAmount': 850,
      'creditBalance': 0,
      'creditStatus': 'none',
      'isDeleted': false,
      'deletedAt': null,
      'items': <dynamic>[],
    };

void main() {
  group('TicketData.fromSale preserves cash tender', () {
    test('cash over-tender 850/1000/150 maps net, received and change', () {
      final ticket = TicketData.fromSale(
        _sale(
          totalSold: 850,
          paymentMethod: 'cash',
          paymentCashAmount: 850,
          cashReceived: 1000,
          changeAmount: 150,
        ),
      );
      expect(ticket.cashReceived, 1000);
      expect(ticket.changeAmount, 150);
      expect(ticket.hasCashTender, isTrue);
      expect(ticket.total, 850);
    });

    test('exact cash 850/850/0', () {
      final ticket = TicketData.fromSale(
        _sale(
          totalSold: 850,
          paymentMethod: 'cash',
          paymentCashAmount: 850,
          cashReceived: 850,
          changeAmount: 0,
        ),
      );
      expect(ticket.cashReceived, 850);
      expect(ticket.changeAmount, 0);
      expect(ticket.hasCashTender, isTrue);
    });

    test('transfer-only has no cash tender rows', () {
      final ticket = TicketData.fromSale(
        _sale(
          totalSold: 850,
          paymentMethod: 'transfer',
          paymentCashAmount: 0,
          paymentTransferAmount: 850,
          cashReceived: 0,
          changeAmount: 0,
        ),
      );
      expect(ticket.hasCashTender, isFalse);
    });

    test('legacy sale with unknown tender does not fabricate values', () {
      final ticket = TicketData.fromSale(
        _sale(totalSold: 850, paymentMethod: 'cash', paymentCashAmount: 850),
      );
      expect(ticket.cashReceived, isNull);
      expect(ticket.changeAmount, isNull);
      expect(ticket.hasCashTender, isFalse);
    });

    test('decimal 999.99 received 1000 change 0.01', () {
      final ticket = TicketData.fromSale(
        _sale(
          totalSold: 999.99,
          paymentMethod: 'cash',
          paymentCashAmount: 999.99,
          cashReceived: 1000,
          changeAmount: 0.01,
        ),
      );
      expect(ticket.cashReceived, 1000);
      expect(ticket.changeAmount, 0.01);
    });

    test('reprint (isCopy) reproduces the original received/change', () {
      final sale = _sale(
        totalSold: 850,
        paymentMethod: 'cash',
        paymentCashAmount: 850,
        cashReceived: 1000,
        changeAmount: 150,
      );
      final original = TicketData.fromSale(sale);
      final reprint = TicketData.fromSale(sale, isCopy: true);
      expect(reprint.cashReceived, original.cashReceived);
      expect(reprint.changeAmount, original.changeAmount);
      expect(reprint.cashReceived, 1000);
      expect(reprint.changeAmount, 150);
    });

    test('fiscal sale keeps NCF and cash rows', () {
      final ticket = TicketData.fromSale(
        _sale(
          totalSold: 850,
          paymentMethod: 'cash',
          paymentCashAmount: 850,
          cashReceived: 1000,
          changeAmount: 150,
          ncf: 'B0100000003',
          fiscalVoucherType: 'B01',
        ),
      );
      expect(ticket.ncf, 'B0100000003');
      expect(ticket.fiscalVoucherType, 'B01');
      expect(ticket.cashReceived, 1000);
    });
  });

  group('TicketRenderer payment rows', () {

    test('80mm cash over-tender shows EFECTIVO RECIBIDO and DEVUELTA', () {
      final lines = _render(
        TicketData.fromSale(
          _sale(
            totalSold: 850,
            paymentMethod: 'cash',
            paymentCashAmount: 850,
            cashReceived: 1000,
            changeAmount: 150,
          ),
        ),
      );
      expect(
        lines.any(
          (l) => l.contains('EFECTIVO RECIBIDO') && l.contains('1,000.00'),
        ),
        isTrue,
      );
      expect(
        lines.any((l) => l.contains('DEVUELTA') && l.contains('150.00')),
        isTrue,
      );
    });

    test('58mm over-tender stays within width and keeps rows', () {
      final lines = _render(
        TicketData.fromSale(
          _sale(
            totalSold: 850,
            paymentMethod: 'cash',
            paymentCashAmount: 850,
            cashReceived: 1000,
            changeAmount: 150,
          ),
        ),
        mm: 58,
        chars: 30,
      );
      expect(
        lines.any(
          (l) => l.contains('EFECTIVO RECIBIDO') && l.contains('1,000.00'),
        ),
        isTrue,
      );
      expect(lines.every((l) => l.length <= 30), isTrue,
          reason: '58mm lines must not overflow the printable width');
    });

    test('exact cash shows DEVUELTA RD\$ 0.00 (known tender)', () {
      final lines = _render(
        TicketData.fromSale(
          _sale(
            totalSold: 850,
            paymentMethod: 'cash',
            paymentCashAmount: 850,
            cashReceived: 850,
            changeAmount: 0,
          ),
        ),
      );
      expect(
        lines.any((l) => l.contains('DEVUELTA') && l.contains('0.00')),
        isTrue,
      );
    });

    test('transfer-only does NOT show received/devuelta rows', () {
      final lines = _render(
        TicketData.fromSale(
          _sale(
            totalSold: 850,
            paymentMethod: 'transfer',
            paymentCashAmount: 0,
            paymentTransferAmount: 850,
            cashReceived: 0,
            changeAmount: 0,
          ),
        ),
      );
      expect(lines.any((l) => l.contains('EFECTIVO RECIBIDO')), isFalse);
      expect(lines.any((l) => l.contains('DEVUELTA')), isFalse);
    });

    test('legacy unknown tender does NOT fabricate rows', () {
      final lines = _render(
        TicketData.fromSale(
          _sale(totalSold: 850, paymentMethod: 'cash', paymentCashAmount: 850),
        ),
      );
      expect(lines.any((l) => l.contains('EFECTIVO RECIBIDO')), isFalse);
      expect(lines.any((l) => l.contains('DEVUELTA')), isFalse);
    });
  });

  group('SaleModel serialization preserves cash tender', () {

    test('fromJson keeps cashReceived and changeAmount', () {
      final sale = SaleModel.fromJson({
        ..._json(),
        'cashReceived': 1000,
        'changeAmount': 150,
      });
      expect(sale.cashReceived, 1000);
      expect(sale.changeAmount, 150);
      expect(sale.paymentCashAmount, 850);
    });

    test('fromJson yields null for legacy rows without tender', () {
      final sale = SaleModel.fromJson(_json());
      expect(sale.cashReceived, isNull);
      expect(sale.changeAmount, isNull);
    });
  });
}
