import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_builder.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';

void main() {
  group('TicketBuilder 80mm invoice PDF', () {
    test(
      'builds a normal sale with customer, taxes and cash payment',
      () async {
        final bytes = await _builder().buildPdf(
          TicketData(
            ticketNumber: 'FV-00012345',
            dateTime: DateTime(2026, 8, 11, 10, 30),
            client: const ClientInfo(
              name: 'Ferreteria Los Primos',
              phone: '809-555-1111',
              document: '131000000',
            ),
            cashierName: 'Junior',
            paymentMethod: 'Efectivo RD\$ 2,000.00',
            items: const [
              TicketItemData(
                name: 'Martillo profesional',
                qty: 1,
                unitPrice: 450,
                total: 450,
              ),
              TicketItemData(
                name: 'Caja tornillos',
                qty: 2,
                unitPrice: 125,
                total: 250,
              ),
              TicketItemData(
                name: 'Cable electrico 12 AWG',
                qty: 3,
                unitPrice: 80,
                total: 240,
              ),
              TicketItemData(
                name: 'Cinta aislante',
                qty: 1,
                unitPrice: 75,
                total: 75,
              ),
            ],
            subtotal: 1015,
            itbis: 182.70,
            total: 1197.70,
          ),
        );
        expect(bytes.length, greaterThan(1000));
      },
    );

    test('builds long product names without PDF layout exceptions', () async {
      final bytes = await _builder().buildPdf(
        TicketData(
          ticketNumber: 'FV-LONG',
          dateTime: DateTime(2026, 8, 11, 11),
          client: const ClientInfo(
            name: 'Cliente con nombre comercial muy largo para prueba',
          ),
          cashierName: 'Caja principal',
          paymentMethod: 'Transferencia',
          items: const [
            TicketItemData(
              name:
                  'Camara Hikvision DS-2CD1043G2-I lente 2.8mm exterior metalica',
              qty: 12,
              unitPrice: 3250,
              total: 39000,
            ),
            TicketItemData(
              name:
                  'Cable UTP CAT6 exterior caja completa color negro alta resistencia',
              qty: 3,
              unitPrice: 8450,
              total: 25350,
            ),
          ],
          subtotal: 64350,
          total: 64350,
        ),
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('builds large monetary values with aligned numeric columns', () async {
      final bytes = await _builder().buildPdf(
        TicketData(
          ticketNumber: 'FV-BIG',
          dateTime: DateTime(2026, 8, 11, 12),
          paymentMethod: 'Mixto',
          items: const [
            TicketItemData(
              name: 'Servidor empresarial',
              qty: 2,
              unitPrice: 987654.32,
              total: 1975308.64,
            ),
            TicketItemData(
              name: 'Licencia anual',
              qty: 10,
              unitPrice: 12345.67,
              total: 123456.70,
            ),
          ],
          subtotal: 2098765.34,
          discount: 10000,
          itbis: 376777.76,
          total: 2465543.10,
        ),
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('builds many items and grows vertically', () async {
      final bytes = await _builder().buildPdf(
        TicketData(
          ticketNumber: 'FV-MANY',
          dateTime: DateTime(2026, 8, 11, 13),
          items: [
            for (var i = 1; i <= 35; i++)
              TicketItemData(
                name: 'Producto inventario $i',
                qty: i.toDouble(),
                unitPrice: 25.5 + i,
                total: (25.5 + i) * i,
              ),
          ],
          subtotal: 25000,
          total: 25000,
        ),
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('builds a minimal invoice with missing optional data', () async {
      final bytes = await _builder(company: const CompanyInfo(name: 'NEGOCIO'))
          .buildPdf(
            TicketData(
              ticketNumber: 'FV-MIN',
              dateTime: DateTime(2026, 8, 11, 14),
              items: const [
                TicketItemData(
                  name: 'Venta rapida',
                  qty: 1,
                  unitPrice: 100,
                  total: 100,
                ),
              ],
              total: 100,
            ),
          );
      expect(bytes.length, greaterThan(1000));
    });

    test('builds tax-enabled invoice totals without NCF', () async {
      final bytes = await _builder().buildPdf(
        TicketData(
          ticketNumber: 'FV-TAX-NO-NCF',
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
          subtotal: 3400,
          taxableBase: 2500,
          exemptAmount: 900,
          itbis: 450,
          total: 3850,
        ),
      );

      expect(bytes.length, greaterThan(1000));
    });

    test(
      'real Windows ticket PDF contains new table and fiscal content',
      () async {
        final bytes =
            await _builder(
              company: const CompanyInfo(name: 'FULLTECH, SRL'),
            ).buildPdf(
              TicketData(
                ticketNumber: '81472316',
                dateTime: DateTime(2026, 8, 20, 23, 29),
                client: const ClientInfo(name: 'Consumidor Final'),
                cashierName: 'Juan Perez',
                paymentMethod: 'Efectivo',
                items: const [
                  TicketItemData(
                    name: 'ADAPTADOR HDMI A RJ45',
                    qty: 1,
                    unitPrice: 800,
                    total: 800,
                    exemptAmount: 800,
                    taxExempt: true,
                  ),
                  TicketItemData(
                    name: '2CONNET LECTOR/ESCANER 2D CODIGO WIRELESS',
                    qty: 1,
                    unitPrice: 2500,
                    total: 2500,
                    discount: 500,
                    taxableBase: 1800,
                    taxAmount: 324,
                    taxExempt: false,
                  ),
                ],
                subtotal: 3300,
                productDiscount: 500,
                generalDiscount: 200,
                taxableBase: 1800,
                exemptAmount: 800,
                itbis: 324,
                total: 2924,
                fiscalTaxEnabled: true,
                note: '',
              ),
            );
        final text = _pdfText(bytes);
        final compactText = _compactPdfText(text);

        expect(text, contains('CANT'));
        expect(text, contains('ITEM'));
        expect(text, contains('PRECIO'));
        expect(text, contains('TOTAL'));
        expect(text, isNot(contains('IMPORTE')));
        expect(text, isNot(contains('PENDIENTE DE SINCRONIZAR')));
        expect(text, isNot(contains('NOTAS')));
        expect(text, contains('ITBIS'));
        expect(compactText, contains('DESC. PRODUCTOS'));
        expect(compactText, contains('DESC. GENERAL'));
        expect(compactText, contains('MONTO GRAVADO'));
        expect(compactText, contains('MONTO EXENTO'));
      },
    );

    test(
      'real Windows ticket PDF resolves cashier for immediate and reprint data',
      () async {
        final immediate = TicketData.resolveCashierDisplayName(
          cashierNameOverride: null,
          saleCashierName: 'Maria Caja',
        );
        final historical = TicketData.resolveCashierDisplayName(
          cashierNameOverride: null,
          saleCashierName: 'PENDIENTE DE SINCRONIZAR',
        );

        expect(immediate, 'Maria Caja');
        expect(historical, 'No disponible');
      },
    );

    test('generates a Windows TicketBuilder diagnostic sample PDF', () async {
      final bytes =
          await _builder(
            company: const CompanyInfo(name: 'FULLTECH, SRL'),
          ).buildPdf(
            TicketData(
              ticketNumber: 'SAMPLE-80MM',
              dateTime: DateTime(2026, 8, 20, 23, 29),
              client: const ClientInfo(
                name: 'Cliente Fiscal',
                phone: '809-555-1111',
                document: '131000000',
              ),
              cashierName: 'Juan Perez',
              paymentMethod: 'Efectivo',
              fiscalVoucherType: 'B01',
              ncf: 'B0100000001',
              items: const [
                TicketItemData(
                  name: 'CABLE DE CORRIENTE',
                  qty: 1,
                  unitPrice: 800,
                  total: 800,
                  exemptAmount: 800,
                  taxExempt: true,
                ),
                TicketItemData(
                  name: 'CAMARA AHD 1080P',
                  qty: 1,
                  unitPrice: 2500,
                  total: 2500,
                  discount: 500,
                  taxableBase: 1800,
                  taxAmount: 324,
                  taxExempt: false,
                ),
              ],
              subtotal: 3300,
              productDiscount: 500,
              generalDiscount: 200,
              taxableBase: 1800,
              exemptAmount: 800,
              itbis: 324,
              total: 2924,
              fiscalTaxEnabled: true,
              note: 'Entregar con garantia.',
            ),
          );
      final file = File('build/ticket_samples/windows_ticket_sample_80mm.pdf');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);

      expect(file.existsSync(), isTrue);
      expect(bytes.length, greaterThan(1000));
      expect(_pdfText(bytes), contains('NCF'));
    });
  });
}

String _pdfText(List<int> bytes) {
  final document = PdfDocument(inputBytes: bytes);
  try {
    return PdfTextExtractor(document).extractText();
  } finally {
    document.dispose();
  }
}

String _compactPdfText(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

TicketBuilder _builder({CompanyInfo? company}) {
  return TicketBuilder(
    layout: _layout80(),
    company:
        company ??
        const CompanyInfo(
          name: 'FullPOS Cloud Super Mercado SRL',
          rnc: '131-00000-1',
          phone: '829-534-4286',
          address: 'Av. Principal #12, Santo Domingo, Republica Dominicana',
          email: 'ventas@fulltechrd.com',
          website: 'fulltechrd.com',
        ),
  );
}

TicketLayoutConfig _layout80() {
  return const TicketLayoutConfig(
    paperWidthMm: 80,
    charsPerLine: 48,
    fontSize: 'normal',
    fontFamily: 'mono',
    showLogo: false,
    logoSize: 44,
    showBusinessData: true,
    showItbis: true,
    showCashier: true,
    showClient: true,
    showPaymentMethod: true,
    showDiscounts: true,
    showCode: false,
    showDatetime: true,
    showSubtotalItbisTotal: true,
    footerMessage: 'Gracias por su preferencia',
    warrantyPolicy: 'Cambios sujetos a politica de la empresa.',
    headerExtra: '',
    headerBusinessName: '',
    headerRnc: '',
    headerAddress: '',
    headerPhone: '',
    fontSizeLevel: 5,
    lineSpacingLevel: 5,
    sectionSpacingLevel: 5,
    headerAlignment: 'center',
    detailsAlignment: 'left',
    totalsAlignment: 'right',
    topMargin: 2,
    bottomMargin: 2,
    leftMargin: 2,
    rightMargin: 2,
    sectionSeparatorStyle: 'line',
  );
}
