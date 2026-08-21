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

  test('normal ticket shows fiscal snapshots without voucher and NCF', () {
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
    expect(text, contains('Monto gravado'));
    expect(text, contains('ITBIS'));
    expect(text, contains('RD\$ 180.00'));
    expect(text, contains('TOTAL'));
  });

  test(
    'tax-enabled normal invoice prints ordered tax totals without NCF block',
    () {
      final ticket = TicketData(
        ticketNumber: 'FV-TAX',
        dateTime: DateTime(2026, 8, 20, 10),
        client: const ClientInfo(name: 'Consumidor Final'),
        fiscalTaxEnabled: true,
        items: const [
          TicketItemData(
            name: 'Producto gravado',
            qty: 1,
            unitPrice: 2500,
            total: 2950,
            taxableBase: 2500,
            taxAmount: 450,
            taxExempt: false,
          ),
        ],
        subtotal: 2500,
        taxableBase: 2500,
        itbis: 450,
        total: 2950,
      );

      final lines = const TicketRenderer(
        layout: _layout80,
        company: _company,
      ).buildLines(ticket);
      final text = lines.join('\n');

      expect(text, isNot(contains('NCF')));
      expect(text, contains('Monto gravado'));
      expect(text, contains('ITBIS'));
      expect(text, contains('RD\$ 450.00'));
      expect(text.indexOf('Monto gravado'), lessThan(text.indexOf('ITBIS')));
      expect(text.indexOf('ITBIS'), lessThan(text.indexOf('TOTAL')));
    },
  );

  test(
    'tax-enabled exempt invoice prints exempt amount without zero ITBIS',
    () {
      final ticket = TicketData(
        ticketNumber: 'FV-EXEMPT',
        dateTime: DateTime(2026, 8, 20, 10),
        fiscalTaxEnabled: true,
        items: const [
          TicketItemData(
            name: 'Producto exento',
            qty: 1,
            unitPrice: 900,
            total: 900,
            exemptAmount: 900,
            taxExempt: true,
          ),
        ],
        subtotal: 900,
        exemptAmount: 900,
        itbis: 0,
        total: 900,
      );

      final lines = const TicketRenderer(
        layout: _layout80,
        company: _company,
      ).buildLines(ticket);
      final text = lines.join('\n');

      expect(text, contains('Monto exento'));
      expect(text, contains('RD\$ 900.00'));
      expect(text, isNot(contains('ITBIS')));
      expect(text, isNot(contains('RD\$ 0.00')));
    },
  );

  test(
    'TicketData.fromSale carries tax-enabled flag and mixed fiscal subtotal',
    () {
      final sale = _saleWithFiscalSnapshots();
      final ticket = TicketData.fromSale(sale);

      expect(ticket.fiscalTaxEnabled, isTrue);
      expect(ticket.resolvedSubtotal, 3400);
      expect(ticket.taxableBase, 2500);
      expect(ticket.exemptAmount, 900);
      expect(ticket.itbis, 450);
    },
  );

  test('TicketData.fromSale separates line and general discounts', () {
    final sale = _saleWithFiscalSnapshots(
      discountAmount: 300,
      lineDiscountAmount: 100,
    );

    final ticket = TicketData.fromSale(sale);

    expect(ticket.productDiscount, 100);
    expect(ticket.generalDiscount, 200);
    expect(ticket.discount, 300);

    final text = const TicketRenderer(
      layout: _layout80,
      company: _company,
    ).buildLines(ticket).join('\n');

    expect(text, contains('Desc. productos'));
    expect(text, contains('-RD\$ 100.00'));
    expect(text, contains('Desc. general'));
    expect(text, contains('-RD\$ 200.00'));
  });

  test('TicketRenderer does not print empty customer phone placeholders', () {
    final text = const TicketRenderer(layout: _layout80, company: _company)
        .buildLines(
          TicketData(
            ticketNumber: 'FV-CLIENT',
            dateTime: DateTime(2026, 8, 20, 10),
            client: const ClientInfo(name: 'Consumidor Final'),
            items: const [
              TicketItemData(
                name: 'Producto',
                qty: 1,
                unitPrice: 100,
                total: 100,
              ),
            ],
            total: 100,
          ),
        )
        .join('\n');

    expect(text, contains('Cliente'));
    expect(text, contains('Consumidor Final'));
    expect(text, isNot(contains('Tel.')));
    expect(text, isNot(contains(' -')));
  });

  test('TicketData.fromSale sanitizes pending cashier marker', () {
    final sale = _saleWithFiscalSnapshots(userName: 'Pendiente de sincronizar');

    expect(
      TicketData.fromSale(sale, cashierNameOverride: 'Maria Perez').cashierName,
      'Maria Perez',
    );
    expect(TicketData.fromSale(sale).cashierName, 'No disponible');
  });

  test('B01 ticket prints fiscal block and snapshot totals', () {
    final ticket = TicketData(
      ticketNumber: 'FV-B01',
      dateTime: DateTime(2026, 8, 18, 10),
      client: const ClientInfo(name: 'CANATECH SRL', document: '132588312'),
      fiscalVoucherType: 'B01',
      ncf: 'B0100000014',
      fiscalTaxEnabled: true,
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

  test(
    'ticket header prefers issuer snapshot over current company settings',
    () {
      final sale = SaleModel(
        id: 'snapshot-sale',
        userId: 'user-a',
        userName: 'Caja',
        customerId: 'client-a',
        customerName: 'Cliente actual cambiado',
        customerPhone: '809-999-9999',
        saleDate: DateTime(2026, 8, 18, 10),
        note: '',
        totalSold: 1180,
        totalCost: 600,
        totalProfit: 580,
        commissionAmount: 58,
        paymentMethod: 'cash',
        paymentCashAmount: 1180,
        paymentTransferAmount: 0,
        creditAmount: 0,
        creditPaidAmount: 0,
        creditBalance: 0,
        creditStatus: 'none',
        isDeleted: false,
        deletedAt: null,
        fiscalTaxEnabled: true,
        fiscalPriceMode: 'TAX_INCLUDED',
        taxableBase: 1000,
        taxAmount: 180,
        exemptAmount: 0,
        discountAmount: 0,
        fiscalVoucherType: 'B01',
        ncf: 'B0100000099',
        issuerNameSnapshot: 'EMISOR ORIGINAL SRL',
        issuerTaxIdSnapshot: '130000001',
        issuerPhoneSnapshot: '809-111-1111',
        issuerAddressSnapshot: 'Direccion original',
        fiscalCustomerTaxId: '101010101',
        fiscalCustomerName: 'CLIENTE ORIGINAL',
        customerPhoneSnapshot: '809-222-2222',
        items: const [
          SaleItemModel(
            id: 'item-a',
            productId: 'product-a',
            productNameSnapshot: 'PRODUCTO ORIGINAL',
            productImageSnapshot: null,
            qty: 1,
            priceSoldUnit: 1180,
            costUnitSnapshot: 600,
            subtotalSold: 1180,
            subtotalCost: 600,
            profit: 580,
            category: null,
            taxableBase: 1000,
            taxRate: 0.18,
            taxAmount: 180,
            exemptAmount: 0,
            taxIncluded: true,
            taxExempt: false,
          ),
        ],
      );

      final ticket = TicketData.fromSale(sale);
      final lines = const TicketRenderer(
        layout: _layout80,
        company: CompanyInfo(
          name: 'Empresa Cambiada',
          rnc: '999999999',
          phone: '809-000-0000',
          address: 'Direccion cambiada',
        ),
      ).buildLines(ticket);
      final text = lines.join('\n');

      expect(text, contains('EMISOR ORIGINAL SRL'));
      expect(text, contains('130000001'));
      expect(text, contains('809-111-1111'));
      expect(text, contains('Direccion original'));
      expect(text, contains('CLIENTE ORIGINAL'));
      expect(text, contains('PRODUCTO ORIGINAL'));
      expect(text, isNot(contains('Empresa Cambiada')));
      expect(text, isNot(contains('Cliente actual cambiado')));
    },
  );

  test('B02 ticket prints type and NCF without forcing RNC', () {
    final ticket = TicketData(
      ticketNumber: 'FV-B02',
      dateTime: DateTime(2026, 8, 18, 10),
      client: const ClientInfo(name: 'Consumidor Final'),
      fiscalVoucherType: 'B02',
      ncf: 'B0200000014',
      fiscalTaxEnabled: true,
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

SaleModel _saleWithFiscalSnapshots({
  String userName = 'Caja',
  double discountAmount = 0,
  double lineDiscountAmount = 0,
}) {
  return SaleModel(
    id: 'sale-fiscal-mixed',
    userId: 'user-1',
    userName: userName,
    customerId: null,
    customerName: 'Consumidor Final',
    customerPhone: '',
    saleDate: DateTime(2026, 8, 20, 10),
    note: '',
    totalSold: 3850,
    totalCost: 0,
    totalProfit: 3400,
    commissionAmount: 0,
    paymentMethod: 'cash',
    paymentCashAmount: 3850,
    paymentTransferAmount: 0,
    creditAmount: 0,
    creditPaidAmount: 0,
    creditBalance: 0,
    creditStatus: 'none',
    isDeleted: false,
    deletedAt: null,
    fiscalTaxEnabled: true,
    fiscalPriceMode: 'TAX_ADDED',
    taxableBase: 2500,
    taxAmount: 450,
    exemptAmount: 900,
    discountAmount: discountAmount,
    items: [
      SaleItemModel(
        id: 'item-exempt',
        productId: 'product-exempt',
        productNameSnapshot: 'Producto exento',
        productImageSnapshot: null,
        qty: 1,
        priceSoldUnit: 900,
        costUnitSnapshot: 0,
        subtotalSold: 900,
        subtotalCost: 0,
        profit: 900,
        category: null,
        grossAmount: 900,
        lineDiscountAmount: lineDiscountAmount,
        taxableBase: 0,
        taxRate: 0,
        taxAmount: 0,
        exemptAmount: 900,
        taxIncluded: false,
        taxExempt: true,
      ),
      SaleItemModel(
        id: 'item-taxable',
        productId: 'product-taxable',
        productNameSnapshot: 'Producto gravado',
        productImageSnapshot: null,
        qty: 1,
        priceSoldUnit: 2500,
        costUnitSnapshot: 0,
        subtotalSold: 2950,
        subtotalCost: 0,
        profit: 2500,
        category: null,
        grossAmount: 2500,
        taxableBase: 2500,
        taxRate: 0.18,
        taxAmount: 450,
        exemptAmount: 0,
        taxIncluded: false,
        taxExempt: false,
      ),
    ],
  );
}
