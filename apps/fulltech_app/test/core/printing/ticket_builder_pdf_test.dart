import 'package:flutter_test/flutter_test.dart';

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
  });
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
