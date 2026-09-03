import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps normal product names on one safe 80mm table line', () {
    final lines = _renderer.previewLines(
      _receipt(
        items: const [
          TicketItemData(name: 'CABLE USB', qty: 1, unitPrice: 6, total: 6),
          TicketItemData(
            name: 'ADAPTADOR HDMI A RJ45',
            qty: 1,
            unitPrice: 800,
            total: 800,
          ),
          TicketItemData(
            name: 'CÁMARA AHD 1080P',
            qty: 9,
            unitPrice: 250,
            total: 2250,
          ),
        ],
      ),
    );

    expect(
      lines,
      contains('       1 CABLE USB                         6.00         6.00'),
    );
    expect(
      lines,
      contains('       1 ADAPTADOR HDMI A RJ45           800.00       800.00'),
    );
    expect(
      lines,
      contains('       9 CÁMARA AHD 1080P                250.00     2,250.00'),
    );
  });

  test('truncates long product names without moving price or total', () {
    final lines = _renderer.previewLines(
      _receipt(
        items: const [
          TicketItemData(
            name: '2CONNET LECTOR/ESCÁNER 2D CÓDIGO WIRELESS',
            qty: 1,
            unitPrice: 2500,
            total: 2500,
          ),
        ],
      ),
    );

    const expected =
        '       1 2CONNET LECTOR/ESCÁNER 2...   2,500.00     2,500.00';
    expect(lines, contains(expected));
    expect(
      expected.length,
      lessThanOrEqualTo(
        FullPosEscPosReceiptRenderer.fontBChars -
            FullPosEscPosReceiptRenderer.rightSafeChars,
      ),
    );
  });

  test(
    'supports quantities, large values, discounts, fiscal lines and notes',
    () {
      final lines = _renderer.previewLines(
        _receipt(
          items: const [
            TicketItemData(
              name: 'CABLE DE CORRIENTE',
              qty: 99,
              unitPrice: 25000,
              total: 2500000,
              discount: 500,
            ),
            TicketItemData(
              name: 'SERVICIO EXENTO',
              qty: 999,
              unitPrice: 999999.99,
              total: 999999.99,
            ),
          ],
          subtotal: 3300,
          productDiscount: 500,
          generalDiscount: 200,
          taxableBase: 1800,
          exemptAmount: 800,
          taxAmount: 324,
          total: 2924,
          note: 'Entregar con garantía y soporte.',
          ncf: 'B0100000001',
          fiscalVoucherType: 'CREDITO FISCAL',
        ),
      );

      expect(
        lines,
        contains(
          '      99 CABLE DE CORRIENTE           25,000.00 2,500,000.00',
        ),
      );
      expect(lines, contains('       Desc. -RD\$ 500.00'));
      expect(
        lines,
        contains(
          '                        SUBTOTAL                RD\$ 3,300.00',
        ),
      );
      expect(
        lines,
        contains(
          '                        DESC. PRODUCTOS          -RD\$ 500.00',
        ),
      );
      expect(
        lines,
        contains(
          '                        DESC. GENERAL            -RD\$ 200.00',
        ),
      );
      expect(
        lines,
        contains(
          '                        MONTO EXENTO              RD\$ 800.00',
        ),
      );
      expect(
        lines,
        contains(
          '                        MONTO GRAVADO           RD\$ 1,800.00',
        ),
      );
      expect(
        lines,
        contains(
          '                        ITBIS                     RD\$ 324.00',
        ),
      );
      expect(lines, contains('    NCF: B0100000001'));
      expect(lines, contains('    NOTA'));
    },
  );

  test('table and totals reserve safe characters at the right edge', () {
    final profile = ThermalPrinterProfile.mm80();
    final lines = _renderer.previewLines(
      _receipt(
        items: const [
          TicketItemData(
            name: '2CONNET LECTOR/ESCÁNER 2D CÓDIGO WIRELESS',
            qty: 1,
            unitPrice: 2500,
            total: 2500,
          ),
        ],
        subtotal: 3300,
        taxableBase: 1800,
        exemptAmount: 800,
        taxAmount: 324,
        total: 2924,
      ),
    );

    final tableLines = lines.where(
      (line) =>
          line.startsWith('CANT ') ||
          line.startsWith('    CAN ') ||
          line.startsWith('      1 ') ||
          line.startsWith('                        '),
    );

    expect(profile.tableLineChars, lessThanOrEqualTo(profile.usableChars));
    expect(
      profile.layout.leftOuterPadding +
          profile.layout.contentWidth +
          profile.layout.rightOuterPadding,
      lessThanOrEqualTo(profile.layout.physicalChars),
    );
    for (final line in tableLines) {
      expect(line.length, lessThanOrEqualTo(profile.printableFontBChars));
    }
  });

  test('final layout keeps every content section inside central width', () {
    final profile = ThermalPrinterProfile.mm80();
    final lines = _renderer.previewLines(
      _receipt(
        items: const [
          TicketItemData(
            name: '2CONNET LECTOR/ESCÁNER 2D CÓDIGO WIRELESS MUY LARGO',
            qty: 123,
            unitPrice: 999999.99,
            total: 9999999.99,
            discount: 500,
          ),
        ],
        subtotal: 9999999.99,
        productDiscount: 500,
        generalDiscount: 200,
        taxableBase: 8500000,
        exemptAmount: 300,
        taxAmount: 1530000,
        total: 10000000,
      ),
    );

    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(profile.printableFontBChars));
    }
    expect(
      lines,
      contains('    CANT ITEM                            PRECIO        TOTAL'),
    );
    expect(
      lines.any(
        (line) =>
            line.contains('2CONNET LECTOR/ESCÁNER') && line.contains('...'),
      ),
      isTrue,
    );
    expect(lines.any((line) => line.trimLeft().startsWith('ITBIS')), isTrue);
    expect(lines.any((line) => line.contains('PAGO: EFECTIVO')), isTrue);
  });

  test('omits empty client fields and empty notes', () {
    final lines = _renderer.previewLines(_receipt(note: '   '));

    expect(lines, contains('    CLIENTE: CONSUMIDOR FINAL'));
    expect(lines.any((line) => line.trimLeft().startsWith('TEL:')), isFalse);
    expect(
      lines.any((line) => line.trimLeft().startsWith('RNC/CEDULA:')),
      isFalse,
    );
    expect(lines, isNot(contains('    NOTA')));
  });

  test('prints warranty policy when configured', () {
    final lines = FullPosEscPosReceiptRenderer(
      cutPaper: false,
      warrantyPolicy: 'Garantia segun politica de la empresa.',
    ).previewLines(_receipt());

    expect(lines, contains('    POLITICA DE GARANTIA'));
    expect(lines, contains('    Garantia segun politica de la empresa.'));
  });

  test('renders esc pos bytes with Spanish characters using CP1252', () async {
    final bytes = await _renderer.render(
      _receipt(
        items: const [
          TicketItemData(
            name: 'ESCÁNER CÓDIGO HIGÜEY Ñ',
            qty: 1,
            unitPrice: 250,
            total: 250,
          ),
        ],
      ),
    );

    expect(bytes, isNotEmpty);
    expect(bytes, contains(0xC1)); // Á in latin1/CP1252.
    expect(bytes, contains(0xD1)); // Ñ in latin1/CP1252.
  });

  test('diagnostic raw ticket includes Spanish text and cuts once', () async {
    final bytes = await FullPosEscPosReceiptRenderer()
        .renderWindowsRawDiagnostic();

    expect(bytes, contains(0xC1)); // Á
    expect(bytes, contains(0xD1)); // Ñ
    expect(_cutCommandCount(bytes), 1);
  });

  test('prints VENCE line when NCF expiration exists', () {
    final lines = _renderer.previewLines(
      _receipt(
        ncf: 'B0100000003',
        fiscalVoucherType: 'B01',
        ncfExpirationDate: DateTime(2026, 12, 31),
      ),
    );

    expect(lines.any((line) => line.contains('NCF: B0100000003')), isTrue);
    expect(lines.any((line) => line.contains('VENCE: 31/12/2026')), isTrue);
    expect(lines.any((line) => line.contains('COMPROBANTE: B01')), isTrue);
  });

  test('does not print VENCE line when there is no expiration', () {
    final lines = _renderer.previewLines(
      _receipt(
        ncf: 'B0100000003',
        fiscalVoucherType: 'B01',
      ),
    );

    expect(lines.any((line) => line.contains('NCF: B0100000003')), isTrue);
    expect(lines.where((line) => line.contains('VENCE')), isEmpty);
  });

  test('prints cashier name and falls back to No disponible only when empty', () {
    final withCashier = _renderer.previewLines(
      _receipt(),
    );
    expect(withCashier, contains(contains('Cajero: JUAN PÉREZ')));

    final withoutCashier = FullPosEscPosReceiptRenderer(cutPaper: false)
        .previewLines(
          ThermalReceiptViewModel(
            ticketNumber: '81472316',
            dateTime: DateTime(2026, 8, 20, 19, 29),
            documentTitle: 'FACTURA',
            company: const CompanyInfo(
              name: 'FULLTECH, SRL',
              address: 'Centro Calle Beller 9 Local N2, Higüey',
              phone: '809-555-0000',
              rnc: '131000000',
            ),
            items: const [],
            subtotal: 0,
            productDiscount: 0,
            generalDiscount: 0,
            taxableBase: 0,
            exemptAmount: 0,
            taxAmount: 0,
            total: 0,
            fiscalTaxEnabled: false,
            taxIncluded: false,
            cashierName: null,
          ),
        );
    expect(withoutCashier, contains(contains('Cajero: No disponible')));
  });

  test('ESC/POS shows EFECTIVO RECIBIDO and DEVUELTA for cash over-tender', () {
    final lines = _renderer.previewLines(
      ThermalReceiptViewModel(
        ticketNumber: '81472316',
        dateTime: DateTime(2026, 8, 20, 19, 29),
        documentTitle: 'FACTURA',
        company: const CompanyInfo(
          name: 'FULLTECH, SRL',
          address: 'Centro Calle Beller 9 Local N2, Higüey',
          phone: '809-555-0000',
          rnc: '131000000',
        ),
        items: const [],
        subtotal: 850,
        productDiscount: 0,
        generalDiscount: 0,
        taxableBase: 0,
        exemptAmount: 0,
        taxAmount: 0,
        total: 850,
        fiscalTaxEnabled: false,
        taxIncluded: false,
        paymentMethod: 'EFECTIVO',
        cashReceived: 1000,
        changeAmount: 150,
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

  test('ESC/POS omits received/devuelta rows for non-cash tickets', () {
    final lines = _renderer.previewLines(
      ThermalReceiptViewModel(
        ticketNumber: '81472316',
        dateTime: DateTime(2026, 8, 20, 19, 29),
        documentTitle: 'FACTURA',
        company: const CompanyInfo(
          name: 'FULLTECH, SRL',
          address: 'Centro Calle Beller 9 Local N2, Higüey',
          phone: '809-555-0000',
          rnc: '131000000',
        ),
        items: const [],
        subtotal: 850,
        productDiscount: 0,
        generalDiscount: 0,
        taxableBase: 0,
        exemptAmount: 0,
        taxAmount: 0,
        total: 850,
        fiscalTaxEnabled: false,
        taxIncluded: false,
        paymentMethod: 'TRANSFERENCIA',
        cashReceived: 0,
        changeAmount: 0,
      ),
    );
    expect(lines.any((l) => l.contains('EFECTIVO RECIBIDO')), isFalse);
    expect(lines.any((l) => l.contains('DEVUELTA')), isFalse);
  });
}

final _renderer = FullPosEscPosReceiptRenderer(cutPaper: false);

int _cutCommandCount(List<int> bytes) {
  var count = 0;
  for (var i = 0; i < bytes.length - 2; i++) {
    if (bytes[i] == 0x1D && bytes[i + 1] == 0x56) {
      count++;
    }
  }
  return count;
}

ThermalReceiptViewModel _receipt({
  List<TicketItemData> items = const [
    TicketItemData(name: 'CABLE USB', qty: 1, unitPrice: 6, total: 6),
  ],
  double subtotal = 6,
  double productDiscount = 0,
  double generalDiscount = 0,
  double taxableBase = 0,
  double exemptAmount = 0,
  double taxAmount = 0,
  double total = 6,
  String? note,
  String? ncf,
  String? fiscalVoucherType,
  DateTime? ncfExpirationDate,
}) {
  return ThermalReceiptViewModel(
    ticketNumber: '81472316',
    dateTime: DateTime(2026, 8, 20, 19, 29),
    documentTitle: 'FACTURA',
    company: const CompanyInfo(
      name: 'FULLTECH, SRL',
      address: 'Centro Calle Beller 9 Local N2, Higüey',
      phone: '809-555-0000',
      rnc: '131000000',
    ),
    items: items
        .map(
          (item) => ThermalReceiptItemViewModel(
            name: item.name,
            qty: item.qty,
            unitPrice: item.unitPrice,
            total: item.total,
            discount: item.discount,
            taxableBase: item.taxableBase,
            exemptAmount: item.exemptAmount,
            taxAmount: item.taxAmount,
          ),
        )
        .toList(growable: false),
    subtotal: subtotal,
    productDiscount: productDiscount,
    generalDiscount: generalDiscount,
    taxableBase: taxableBase,
    exemptAmount: exemptAmount,
    taxAmount: taxAmount,
    total: total,
    fiscalTaxEnabled: taxAmount > 0 || taxableBase > 0 || exemptAmount > 0,
    taxIncluded: false,
    client: const ThermalReceiptClientViewModel(name: 'Consumidor Final'),
    cashierName: 'JUAN PÉREZ',
    paymentMethod: 'EFECTIVO',
    note: note,
    ncf: ncf,
    fiscalVoucherType: fiscalVoucherType,
    ncfExpirationDate: ncfExpirationDate,
  );
}
