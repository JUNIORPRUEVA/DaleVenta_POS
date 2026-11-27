import 'dart:io';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;

Future<String> ticket({
  String method = 'Efectivo RD\$ 2,500.00',
  double received = 2500,
  double change = 0,
  double discount = 0,
  double tax = 0,
  double exempt = 0,
  bool fiscalTaxEnabled = false,
  TicketCreditSummary? credit,
  String? note,
  String? artifact,
  double width = 80,
}) async {
  final data = TicketData(
    ticketNumber: '12345678',
    dateTime: DateTime(2026, 11, 27),
    items: const [
      TicketItemData(
        name: 'Artículo de prueba',
        qty: 1,
        unitPrice: 2500,
        total: 2500,
      ),
    ],
    total: 2500 - discount + tax,
    subtotal: 2500,
    generalDiscount: discount,
    itbis: tax,
    taxableBase: tax > 0 ? 2500 : 0,
    exemptAmount: exempt,
    fiscalTaxEnabled: fiscalTaxEnabled,
    paymentMethod: method,
    cashReceived: received,
    changeAmount: change,
    credit: credit,
    note: note,
  );
  final bytes = await HtmlThermalReceiptPdfRenderer(paperWidthMm: width).render(
    ThermalReceiptViewModel.fromTicketData(
      data: data,
      company: const CompanyInfo(name: 'PRUEBA LOCAL SIN VALIDEZ FISCAL'),
    ),
  );
  if (artifact != null) {
    await File('../../.uat/credit-ticket/$artifact.pdf').writeAsBytes(bytes);
  }
  final document = pdf.PdfDocument(inputBytes: bytes);
  try {
    return pdf.PdfTextExtractor(
      document,
    ).extractText().replaceAll(RegExp(r'\s+'), ' ');
  } finally {
    document.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final received in [2500.0, 3000.0]) {
    test(
      'simple cash $received only total and change, including zero',
      () async {
        final text = await ticket(
          received: received,
          change: received - 2500,
          exempt: 2500,
          note: 'Pago: Efectivo',
          artifact: 'minimal-cash-${received.toInt()}',
        );
        expect(text, contains('TOTAL RD\$ 2,500.00'));
        expect(
          text,
          contains('DEVUELTA RD\$ ${received == 2500 ? '0.00' : '500.00'}'),
        );
        for (final duplicate in ['SUBTOTAL', 'PAGO:', 'EFECTIVO', 'EXENTO']) {
          expect(text, isNot(contains(duplicate)));
        }
        expect(text, contains('NOTA Pago: Efectivo'));
        expect(RegExp('Pago: Efectivo').allMatches(text), hasLength(1));
        expect(text.indexOf('NOTA'), greaterThan(text.indexOf('DEVUELTA')));
        expect(
          text.indexOf('¡GRACIAS'),
          greaterThan(text.indexOf('Pago: Efectivo')),
        );
      },
    );
  }
  for (final paid in [0.0, 1000.0, 2500.0]) {
    test(
      'credit $paid preserves paid and outstanding without repeated purchase',
      () async {
        final text = await ticket(
          method: paid == 0 ? 'Credito' : 'Credito + Efectivo',
          received: paid,
          credit: TicketCreditSummary(
            amount: 2500,
            paid: paid,
            balance: 2500 - paid,
          ),
          note: 'Pago: Crédito',
        );
        expect(text, contains('TOTAL RD\$ 2,500.00'));
        expect(text, contains('ABONADO'));
        expect(text, contains('PENDIENTE'));
        expect(text, contains('DEVUELTA RD\$ 0.00'));
        for (final duplicate in [
          'SUBTOTAL',
          'TOTAL COMPRA',
          'PAGO:',
          'EFECTIVO',
        ]) {
          expect(text, isNot(contains(duplicate)));
        }
        expect(text, contains('NOTA Pago: Crédito'));
      },
    );
  }
  test(
    'transfer retains method once, without repeating total amount',
    () async {
      final text = await ticket(
        method: 'Transferencia RD\$ 2,500.00',
        received: 0,
      );
      expect(text, contains('NOTA Pago: Transferencia'));
      expect(text, isNot(contains('TRANSFERENCIA RD\$')));
      expect(text, isNot(contains('SUBTOTAL')));
    },
  );
  test(
    'mixed allocations appear once, with no appended total or tender',
    () async {
      final text = await ticket(
        method: 'Efectivo RD\$ 1,000.00 + Transferencia RD\$ 1,500.00',
        received: 1000,
      );
      expect(RegExp(r'1,000\.00').allMatches(text), hasLength(1));
      expect(RegExp(r'1,500\.00').allMatches(text), hasLength(1));
      expect(
        text,
        contains('EFECTIVO RD\$ 1,000.00 TRANSFERENCIA RD\$ 1,500.00'),
      );
      expect(text, contains('DEVUELTA RD\$ 0.00'));
    },
  );
  test(
    'discount and tax keep explanatory subtotal and original amounts',
    () async {
      final discount = await ticket(discount: 100);
      expect(discount, contains('SUBTOTAL RD\$ 2,500.00'));
      expect(discount, contains('DESC. GENERAL -RD\$ 100.00'));
      expect(discount, contains('TOTAL RD\$ 2,400.00'));
      final tax = await ticket(tax: 450, fiscalTaxEnabled: true);
      expect(tax, contains('SUBTOTAL RD\$ 2,500.00'));
      expect(tax, contains('ITBIS RD\$ 450.00'));
      expect(tax, contains('TOTAL RD\$ 2,950.00'));
    },
  );
  test(
    'genuine notes survive while only known checkout payment lines are hidden',
    () async {
      final text = await ticket(
        note: 'Entregar mañana.\nPago: Efectivo\nPago: pendiente de entrega',
      );
      expect(text, contains('Entregar mañana.'));
      expect(text, contains('Pago: pendiente de entrega'));
      expect(RegExp('Pago: Efectivo').allMatches(text), hasLength(1));
    },
  );
  test('58mm payment details stay unchanged', () async {
    final text = await ticket(width: 58);
    expect(text, contains('SUBTOTAL'));
    expect(text, contains('EFECTIVO RECIBIDO'));
  });
  test(
    'credit with mixed payments keeps allocations and debt summary',
    () async {
      final text = await ticket(
        method: 'Credito + Efectivo RD\$ 500.00 + Transferencia RD\$ 1,000.00',
        credit: const TicketCreditSummary(
          amount: 2500,
          paid: 1500,
          balance: 1000,
        ),
      );
      expect(text, contains('ABONADO RD\$ 1,500.00'));
      expect(text, contains('PENDIENTE RD\$ 1,000.00'));
      expect(text, contains('EFECTIVO RD\$ 500.00'));
      expect(text, contains('TRANSFERENCIA RD\$ 1,000.00'));
      expect(text, isNot(contains('TOTAL COMPRA')));
    },
  );
  test(
    'distinct legacy purchase amount is preserved rather than treated as duplicate',
    () async {
      final text = await ticket(
        method: 'Credito',
        credit: const TicketCreditSummary(
          amount: 2000,
          paid: 500,
          balance: 1500,
        ),
      );
      expect(text, contains('TOTAL RD\$ 2,500.00'));
      expect(text, contains('TOTAL COMPRA RD\$ 2,000.00'));
      expect(text, contains('ABONADO RD\$ 500.00'));
      expect(text, contains('PENDIENTE RD\$ 1,500.00'));
    },
  );
}
