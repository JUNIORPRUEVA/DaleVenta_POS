import 'dart:io';

import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;

import 'credit_ticket_test.dart' show creditSale;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    '80mm preserves credit data within the 576-dot printable area',
    () async {
      const product = 'Artículo de prueba crédito';
      final receipt = ThermalReceiptViewModel.fromTicketData(
        data: TicketData.fromSale(
          creditSale(productName: product, realReceiptFields: true),
        ),
        company: const CompanyInfo(
          name: 'FULLPOS LABORATORIO CRÉDITO',
          phone: '8095550100',
          address: 'PRUEBA LOCAL SIN VALIDEZ FISCAL',
        ),
      );
      final bytes = await const HtmlThermalReceiptPdfRenderer().render(receipt);
      final directory = Directory('../../.uat/credit-ticket')
        ..createSync(recursive: true);
      await File(
        '${directory.path}/thermal80-design-credit.pdf',
      ).writeAsBytes(bytes);
      final document = pdf.PdfDocument(inputBytes: bytes);
      try {
        final extractor = pdf.PdfTextExtractor(document);
        final text = extractor.extractText().replaceAll(RegExp(r'\s+'), ' ');
        expect(document.pages.count, 1);
        expect(text, isNot(contains('LOGO')));
        expect(text, isNot(contains('EXENTO')));
        for (final required in [
          product,
          'FULLPOS LABORATORIO CRÉDITO',
          'Cliente de credito',
          '8095550101',
          'Caja de prueba',
          'TOTAL',
          'ABONADO',
          'PENDIENTE',
          'DEVUELTA',
          '2,500.00',
          '1,000.00',
          '1,500.00',
        ]) {
          expect(text, contains(required));
        }
        final lines = extractor.extractTextLines();
        final words = lines.expand((line) => line.wordCollection).toList();
        final subtotalTop = words
            .lastWhere((word) => word.text == 'TOTAL')
            .bounds
            .top;
        final invoiceTop = words
            .firstWhere((word) => word.text == 'FACTURA')
            .bounds
            .top;
        for (final word in words) {
          final companyHeader = word.bounds.top < invoiceTop;
          expect(
            word.fontSize,
            companyHeader
                ? anyOf(closeTo(12, 0.05), closeTo(9.5, 0.05))
                : closeTo(9, 0.05),
            reason: 'Emphasized company header, compact 9pt body: ${word.text}',
          );
          expect(word.fontName, startsWith('RobotoCondensed'));
          if (!companyHeader && word.bounds.top < subtotalTop) {
            expect(
              word.fontStyle,
              isNot(contains(pdf.PdfFontStyle.bold)),
              reason: 'Regular headings, customer and product: ${word.text}',
            );
          }
        }
        final productTop = words
            .singleWhere((word) => word.text == 'Artículo')
            .bounds
            .top;
        final productWords = words
            .where(
              (word) =>
                  ['Artículo', 'de', 'prueba', 'crédito'].contains(word.text) &&
                  (word.bounds.top - productTop).abs() < 1,
            )
            .toList();
        expect(productWords, hasLength(4));
        expect(
          productWords.map((word) => word.bounds.top.round()).toSet(),
          hasLength(1),
        );
        for (final label in ['TOTAL', 'ABONADO', 'PENDIENTE', 'DEVUELTA']) {
          final labelWord = words.lastWhere((word) => word.text == label);
          final amountWord = words.where(
            (word) =>
                word.text == 'RD\$' &&
                (word.bounds.top - labelWord.bounds.top).abs() < 1,
          );
          expect(
            amountWord,
            hasLength(1),
            reason: '$label and amount must share one line',
          );
        }
        final labelRight = words
            .lastWhere((word) => word.text == 'TOTAL')
            .bounds
            .right;
        for (final label in ['ABONADO', 'PENDIENTE', 'DEVUELTA']) {
          expect(
            (words.singleWhere((word) => word.text == label).bounds.right -
                    labelRight)
                .abs(),
            lessThan(0.5),
            reason: 'Total labels must align right',
          );
        }
        expect(
          document.pages[0].size.height,
          lessThan(340),
          reason: 'Fitted text must not expand row heights',
        );
        for (final line in lines) {
          expect(
            line.bounds.left,
            greaterThanOrEqualTo(0.6),
            reason: line.text,
          );
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
  for (final hasLogo in [false, true]) {
    test(
      '80mm fiscal fields, discounts, long names and large totals, logo=$hasLogo',
      () async {
        final receipt = ThermalReceiptViewModel.fromTicketData(
          data: TicketData(
            ticketNumber: '12345678',
            dateTime: DateTime(2026, 11, 26, 14),
            items: const [
              TicketItemData(
                name: 'Lector inalámbrico profesional de códigos de barra 2D',
                qty: 2,
                unitPrice: 1234567.89,
                total: 2469135.78,
                discount: 500,
              ),
            ],
            total: 2469135.78,
            subtotal: 2469835.78,
            productDiscount: 500,
            generalDiscount: 200,
            itbis: 180,
            taxableBase: 1000,
            exemptAmount: 2467955.78,
            fiscalTaxEnabled: true,
            ncf: 'B0100000001',
            fiscalVoucherType: 'B01',
            ncfExpirationDate: DateTime(2027, 12, 31),
            client: const ClientInfo(
              name: 'María Peña',
              phone: '8095550101',
              document: '101000001',
            ),
            note: 'Entregar en recepción.',
            paymentMethod: 'transfer',
          ),
          company: CompanyInfo(
            name: 'Negocio de prueba',
            address: 'Calle principal 123',
            rnc: '131000001',
            logoBytes: hasLogo
                ? await File('assets/image/nuevologo.png').readAsBytes()
                : null,
          ),
        );
        final bytes = await const HtmlThermalReceiptPdfRenderer(
          warrantyPolicy: 'Garantía: conservar esta factura.',
        ).render(receipt);
        await File(
          '../../.uat/credit-ticket/thermal80-fiscal-logo-$hasLogo.pdf',
        ).writeAsBytes(bytes);
        final document = pdf.PdfDocument(inputBytes: bytes);
        try {
          final extractor = pdf.PdfTextExtractor(document);
          final text = extractor.extractText().replaceAll(RegExp(r'\s+'), ' ');
          for (final required in [
            'Lector inalámbrico',
            '...',
            '2,469,135.78',
            '1,234,567.89',
            'DESC. PRODUCTOS',
            'DESC. GENERAL',
            'MONTO EXENTO',
            'MONTO GRAVADO',
            'ITBIS',
            'B0100000001',
            '31/12/2027',
            '101000001',
            '131000001',
            'María Peña',
            'Entregar en recepción.',
            'Garantía: conservar esta factura.',
          ]) {
            expect(text, contains(required));
          }
          expect(text, isNot(contains('LOGO')));
          for (final line in extractor.extractTextLines()) {
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
