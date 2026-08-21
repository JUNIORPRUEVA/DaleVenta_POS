import 'dart:io';

import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('renders standalone 80mm HTML without recalculating fiscal values', () {
    final html = const HtmlThermalReceiptRenderer().render(
      _receipt(
        items: const [
          TicketItemData(
            name: '2CONNET LECTOR/ESCÁNER 2D CÓDIGO WIRELESS',
            qty: 1,
            unitPrice: 2500,
            total: 2500,
            discount: 500,
          ),
        ],
        subtotal: 3300,
        productDiscount: 500,
        generalDiscount: 200,
        taxableBase: 1800,
        exemptAmount: 800,
        taxAmount: 324,
        total: 2924,
      ),
    );

    expect(html, contains('@page'));
    expect(html, contains('size: 80mm auto'));
    expect(html, contains('margin: 2.2mm'));
    expect(html, contains('padding: 2.2mm 8mm 3mm 0.5mm'));
    expect(html, contains('width: 71.50mm'));
    expect(html, contains('font-family: "Arial Narrow", Arial, sans-serif'));
    expect(html, contains('grid-template-columns: 1fr 1fr'));
    expect(html, contains('width: 13%'));
    expect(html, contains('width: 47%'));
    expect(html, contains('white-space: nowrap'));
    expect(html, contains('text-overflow: ellipsis'));
    expect(html, contains('PAGO: EFECTIVO'));
    expect(html, contains('RD\$ 3,300.00'));
    expect(html, contains('-RD\$ 500.00'));
    expect(html, contains('-RD\$ 200.00'));
    expect(html, contains('RD\$ 1,800.00'));
    expect(html, contains('RD\$ 324.00'));
    expect(html, contains('RD\$ 2,924.00'));
    expect(html, contains('MONTO GRAVADO'));
    expect(html, isNot(contains('BASE IMPONIBLE')));
    expect(html, isNot(contains('NOTA</div>')));
  });

  test('renders notes only when present', () {
    final renderer = const HtmlThermalReceiptRenderer();
    final withoutNote = renderer.render(_receipt(note: '   '));
    final withNote = renderer.render(_receipt(note: 'Entregar con garantía.'));

    expect(withoutNote, isNot(contains('class="notes"')));
    expect(withNote, contains('class="notes"'));
    expect(withNote, contains('Entregar con garantía.'));
  });

  test('renders warranty policy only when configured', () {
    final withoutPolicy = const HtmlThermalReceiptRenderer().render(_receipt());
    final withPolicy = const HtmlThermalReceiptRenderer(
      warrantyPolicy: 'Garantía según política de la empresa.',
    ).render(_receipt());

    expect(withoutPolicy, isNot(contains('POLITICA DE GARANTIA')));
    expect(withPolicy, contains('POLITICA DE GARANTIA'));
    expect(withPolicy, contains('Garantía según política de la empresa.'));
  });

  test('renders thermal PDF template with widened CANT column', () async {
    final bytes = await const HtmlThermalReceiptPdfRenderer().render(
      _receipt(
        items: const [
          TicketItemData(
            name: 'CAPSULAS PHYTOEMAGRY',
            qty: 23,
            unitPrice: 250,
            total: 6785,
          ),
          TicketItemData(
            name: 'CARGADOR DE BATERIA',
            qty: 1,
            unitPrice: 1500,
            total: 1771,
          ),
        ],
        subtotal: 7250,
        taxableBase: 7250,
        taxAmount: 1305,
        total: 8555,
      ),
    );

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(1000));
  });

  test('generates visual POC sample HTML files', () {
    final renderer = const HtmlThermalReceiptRenderer();
    final samples = <String, ThermalReceiptViewModel>{
      '01_un_producto_consumidor_final.html': _receipt(),
      '02_dos_productos_cliente_completo.html': _receipt(
        client: const ThermalReceiptClientViewModel(
          name: 'Cliente Fiscal',
          phone: '809-555-1111',
          document: '131000000',
        ),
        items: const [
          TicketItemData(name: 'CABLE USB', qty: 1, unitPrice: 150, total: 150),
          TicketItemData(
            name: 'ADAPTADOR HDMI A RJ45',
            qty: 1,
            unitPrice: 800,
            total: 800,
          ),
        ],
        subtotal: 950,
        total: 950,
      ),
      '03_producto_largo.html': _receipt(
        items: const [
          TicketItemData(
            name: '2CONNET LECTOR/ESCÁNER 2D CÓDIGO WIRELESS',
            qty: 1,
            unitPrice: 2500,
            total: 2500,
          ),
        ],
        subtotal: 2500,
        total: 2500,
      ),
      '04_descuentos_itbis_exento_gravado.html': _receipt(
        items: const [
          TicketItemData(
            name: 'SERVICIO EXENTO',
            qty: 1,
            unitPrice: 800,
            total: 800,
            exemptAmount: 800,
          ),
          TicketItemData(
            name: 'CÁMARA AHD 1080P',
            qty: 1,
            unitPrice: 2500,
            total: 2500,
            discount: 500,
            taxableBase: 1800,
            taxAmount: 324,
          ),
        ],
        subtotal: 3300,
        productDiscount: 500,
        generalDiscount: 200,
        taxableBase: 1800,
        exemptAmount: 800,
        taxAmount: 324,
        total: 2924,
      ),
      '05_diez_productos.html': _receipt(
        items: List.generate(
          10,
          (index) => TicketItemData(
            name: 'PRODUCTO ${index + 1} DE PRUEBA',
            qty: index + 1,
            unitPrice: (125 + index).toDouble(),
            total: ((index + 1) * (125 + index)).toDouble(),
          ),
        ),
        subtotal: 7355,
        total: 7355,
      ),
      '06_con_nota_usuario.html': _receipt(
        note: 'Entregar mañana antes de las 10 AM.',
      ),
    };

    final directory = Directory('build/ticket_samples/html_80mm');
    directory.createSync(recursive: true);
    for (final entry in samples.entries) {
      final file = File('${directory.path}/${entry.key}');
      file.writeAsStringSync(renderer.render(entry.value));
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(1000));
    }
  });

  test('thermal PDF renders a long warranty policy fully (no truncation)',
      () async {
    final longPolicy =
        'La garantía cubre únicamente defectos de fabricación por un período '
        'de doce (12) meses a partir de la fecha de compra. No incluye daños '
        'por mal uso, caídas, humedad, descargas eléctricas ni alteraciones '
        'realizadas por personal no autorizado. Conserve su factura para '
        'hacer valida la garantía en nuestro establecimiento.';
    final bytes = await HtmlThermalReceiptPdfRenderer(
      warrantyPolicy: longPolicy,
    ).render(_receipt());

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(1000));
  });
}

ThermalReceiptViewModel _receipt({
  List<TicketItemData> items = const [
    TicketItemData(name: 'CABLE USB', qty: 1, unitPrice: 150, total: 150),
  ],
  ThermalReceiptClientViewModel? client = const ThermalReceiptClientViewModel(
    name: 'Consumidor Final',
  ),
  double subtotal = 150,
  double productDiscount = 0,
  double generalDiscount = 0,
  double taxableBase = 0,
  double exemptAmount = 0,
  double taxAmount = 0,
  double total = 150,
  String? note,
}) {
  return ThermalReceiptViewModel(
    ticketNumber: '81472316',
    dateTime: DateTime(2026, 8, 20, 19, 29),
    documentTitle: 'FACTURA',
    company: const CompanyInfo(
      name: 'FULLTECH, SRL',
      address: 'Centro Calle Beller 9 Local N2, Higüey, La Altagracia, R.D.',
      phone: '8295319442',
      rnc: '133080206',
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
    client: client,
    cashierName: 'Yunior Lopez',
    paymentMethod: 'Efectivo',
    note: note,
  );
}
