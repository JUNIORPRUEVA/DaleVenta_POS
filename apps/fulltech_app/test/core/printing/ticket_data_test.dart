import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TicketData.fromSale prints mixed payment amounts', () {
    final sale = SaleModel(
      id: 'sale-12345678',
      userId: 'user-1',
      userName: 'Caja',
      customerId: 'client-1',
      customerName: 'Cliente',
      customerPhone: '8090000000',
      saleDate: DateTime(2026, 8, 2, 10),
      note: null,
      totalSold: 1000,
      totalCost: 600,
      totalProfit: 400,
      commissionAmount: 40,
      paymentMethod: 'mixed',
      paymentCashAmount: 350,
      paymentTransferAmount: 650,
      creditAmount: 0,
      creditPaidAmount: 1000,
      creditBalance: 0,
      creditStatus: 'none',
      isDeleted: false,
      deletedAt: null,
      items: const [],
    );

    final ticket = TicketData.fromSale(sale);

    expect(
      ticket.paymentMethod,
      'Efectivo RD\$ 350.00 + Transferencia RD\$ 650.00',
    );
  });

  test('TicketRenderer keeps 58mm invoice compact and within width', () {
    const layout = TicketLayoutConfig(
      paperWidthMm: 58,
      charsPerLine: 32,
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
    const company = CompanyInfo(
      name: 'Fulltech, srl',
      rnc: '133080206',
      phone: '8295319442',
      address: 'Higuey Beller 9',
    );
    final ticket = TicketData(
      ticketNumber: '28201760',
      dateTime: DateTime(2026, 8, 3, 15, 42),
      cashierName: 'Administrador',
      client: const ClientInfo(name: 'Junior'),
      paymentMethod: 'Efectivo RD\$ 2,900.00',
      items: const [
        TicketItemData(
          name: 'AURICULARES INPODS 12',
          qty: 1,
          unitPrice: 800,
          total: 800,
        ),
        TicketItemData(
          name: 'ADAPTADOR JACLINK USB A HDMI',
          qty: 1,
          unitPrice: 1300,
          total: 1300,
        ),
        TicketItemData(
          name: 'ADAPTADOR HDMI A RJ45',
          qty: 1,
          unitPrice: 800,
          total: 800,
        ),
      ],
      subtotal: 2900,
      total: 2900,
      isCopy: true,
    );

    final lines = const TicketRenderer(
      layout: layout,
      company: company,
    ).buildLines(ticket);

    expect(lines.every((line) => line.length <= 30), isTrue);
    expect(lines.first, '        Fulltech, srl');
    expect(lines, contains('PRODUCTO               IMPORTE'));
    expect(lines, contains('..............................'));
  });

  test('normal ticket does not add fiscal block without voucher and NCF', () {
    final ticket = TicketData(
      ticketNumber: 'FV-NORMAL',
      dateTime: DateTime(2026, 8, 18, 10),
      client: const ClientInfo(name: 'Cliente normal', document: '132588312'),
      items: const [
        TicketItemData(name: 'Producto', qty: 1, unitPrice: 1180, total: 1180),
      ],
      subtotal: 1000,
      itbis: 180,
      taxableBase: 1000,
      total: 1180,
    );

    final lines = const TicketRenderer(
      layout: _layout80,
      company: _company,
    ).buildLines(ticket);
    final text = lines.join('\n');

    expect(text, isNot(contains('B01 - CREDITO FISCAL')));
    expect(text, isNot(contains('NCF')));
    expect(text, isNot(contains('Base imponible')));
    expect(text, isNot(contains('ITBIS 18%')));
    expect(text, contains('TOTAL'));
  });

  test('B01 ticket prints fiscal block and snapshot totals', () {
    final ticket = TicketData(
      ticketNumber: 'FV-B01',
      dateTime: DateTime(2026, 8, 18, 10),
      client: const ClientInfo(name: 'CANATECH SRL', document: '132588312'),
      fiscalVoucherType: 'B01',
      ncf: 'B0100000014',
      taxIncluded: true,
      items: const [
        TicketItemData(
          name: 'FOTOCELDA PARA MOTOR',
          qty: 1,
          unitPrice: 1200,
          total: 1200,
        ),
      ],
      subtotal: 21779.66,
      taxableBase: 21779.66,
      itbis: 3920.34,
      total: 25700,
    );

    final lines = const TicketRenderer(
      layout: _layout80,
      company: _company,
    ).buildLines(ticket);
    final text = lines.join('\n');

    expect(text, contains('B01 - CREDITO FISCAL'));
    expect(text, contains('NCF'));
    expect(text, contains('B0100000014'));
    expect(text, contains('CANATECH SRL'));
    expect(text, contains('132588312'));
    expect(text, contains('RD\$ 21,779.66'));
    expect(text, contains('RD\$ 3,920.34'));
    expect(text, contains('RD\$ 25,700.00'));
    expect(text, isNot(contains('Ajuste')));
  });

  test('B02 ticket prints type and NCF without forcing RNC', () {
    final ticket = TicketData(
      ticketNumber: 'FV-B02',
      dateTime: DateTime(2026, 8, 18, 10),
      client: const ClientInfo(name: 'Consumidor Final'),
      fiscalVoucherType: 'B02',
      ncf: 'B0200000014',
      items: const [
        TicketItemData(name: 'Producto', qty: 1, unitPrice: 500, total: 500),
      ],
      subtotal: 500,
      exemptAmount: 500,
      total: 500,
    );

    final lines = const TicketRenderer(
      layout: _layout80,
      company: _company,
    ).buildLines(ticket);
    final text = lines.join('\n');

    expect(text, contains('B02 - CONSUMO'));
    expect(text, contains('B0200000014'));
    expect(text, contains('RD\$ 500.00'));
    expect(text, isNot(contains('RNC        ')));
  });
}

const _company = CompanyInfo(
  name: 'FULLTECH, SRL',
  rnc: '133080206',
  phone: '8295319442',
  address: 'Higuey Beller 9',
);

const _layout80 = TicketLayoutConfig(
  paperWidthMm: 80,
  charsPerLine: 48,
  fontSize: 'normal',
  fontFamily: 'monospace',
  showLogo: false,
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
  footerMessage: '',
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
  leftMargin: 0,
  rightMargin: 0,
  sectionSeparatorStyle: 'dashed',
);
