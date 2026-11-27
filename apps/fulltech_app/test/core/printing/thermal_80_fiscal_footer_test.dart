import 'dart:io';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;
import 'ecf_print_representation_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final type in ['B01', 'B02']) {
    test(
      'traditional $type keeps its NCF without an electronic stamp',
      () async {
        final receipt = ThermalReceiptViewModel.fromTicketData(
          data: TicketData(
            ticketNumber: '12345678',
            dateTime: DateTime(2026, 11, 27),
            items: const [
              TicketItemData(
                name: 'Artículo de prueba',
                qty: 1,
                unitPrice: 100,
                total: 100,
              ),
            ],
            total: 100,
            subtotal: 100,
            paymentMethod: 'Efectivo',
            ncf: '${type}00000001',
            fiscalVoucherType: type,
            ncfExpirationDate: DateTime(2028, 12, 31),
          ),
          company: const CompanyInfo(name: 'PRUEBA LOCAL', rnc: '133080206'),
        );
        final bytes = await const HtmlThermalReceiptPdfRenderer().render(
          receipt,
        );
        await File(
          '../../.uat/credit-ticket/restored-fiscal-$type.pdf',
        ).writeAsBytes(bytes);
        final document = pdf.PdfDocument(inputBytes: bytes);
        try {
          final text = pdf.PdfTextExtractor(
            document,
          ).extractText().replaceAll(RegExp(r'\s+'), ' ');
          expect(text, contains('NCF: ${type}00000001'));
          expect(text, contains('31/12/2028'));
          expect(text, contains('133080206'));
          expect(text, contains('NOTA Pago: Efectivo'));
          expect(text, isNot(contains('e-NCF:')));
          expect(text, isNot(contains('Código de seguridad')));
        } finally {
          document.dispose();
        }
      },
    );
  }
  for (final state in ['SIGNED', 'CONTINGENCY', 'PENDING', 'REJECTED']) {
    test(
      '80mm fiscal identity and authentic stamp availability: $state',
      () async {
        final receipt = ThermalReceiptViewModel.fromTicketData(
          data: TicketData.fromSale(
            fixture.sale(),
            ecf: fixture.fiscal(state: state),
            paymentMethod: 'Efectivo',
          ),
          company: const CompanyInfo(name: 'EMPRESA DEMOSTRACION SRL'),
        );
        final bytes = await const HtmlThermalReceiptPdfRenderer().render(
          receipt,
        );
        final directory = Directory('../../.uat/credit-ticket')
          ..createSync(recursive: true);
        await File(
          '${directory.path}/restored-fiscal-${state.toLowerCase()}.pdf',
        ).writeAsBytes(bytes);
        await File(
          '${directory.path}/restored-fiscal-expected-qr.txt',
        ).writeAsString(fixture.qr);
        final document = pdf.PdfDocument(inputBytes: bytes);
        try {
          final text = pdf.PdfTextExtractor(
            document,
          ).extractText().replaceAll(RegExp(r'\s+'), ' ');
          expect(text, contains('NOTA Pago: Efectivo'));
          for (final value in [
            'E310000000002',
            '133080206',
            '133306001',
            '31/12/2028',
            'EMPRESA DEMOSTRACION SRL',
            'RECEPTOR DE PRUEBA',
            'ITBIS',
            '118.00',
            'SIN VALIDEZ FISCAL',
          ]) {
            expect(text, contains(value));
          }
          expect(text.contains('S9Qvrj'), receipt.ecf!.hasStamp);
          expect(text.contains('13-11-2026 08:45:19'), receipt.ecf!.hasStamp);
          if (state == 'CONTINGENCY') expect(text, contains('PENDIENTE DGII'));
          for (final line in pdf.PdfTextExtractor(
            document,
          ).extractTextLines()) {
            expect(
              line.bounds.right,
              lessThanOrEqualTo(72 * 72 / 25.4),
              reason: line.text,
            );
            expect(
              line.bounds.bottom,
              lessThan(document.pages[0].size.height),
              reason: line.text,
            );
          }
        } finally {
          document.dispose();
        }
      },
    );
  }
}
