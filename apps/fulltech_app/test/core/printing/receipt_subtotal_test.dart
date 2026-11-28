import 'dart:io';

import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;

import 'ecf_print_representation_test.dart' as fixture;

TicketData ticket({
  String productName = 'Artículo ficticio',
  bool electronic = true,
  double subtotal = 100,
  double exempt = 0,
  double discount = 0,
  double productDiscount = 0,
  double generalDiscount = 0,
}) => TicketData(
  ticketNumber: '12345678',
  dateTime: DateTime(2026, 11, 28),
  items: [
    TicketItemData(
      name: productName,
      qty: 1,
      unitPrice: 100,
      total: 118,
      taxableBase: 100,
      taxAmount: 18,
    ),
  ],
  subtotal: subtotal,
  taxableBase: 100,
  exemptAmount: exempt,
  discount: discount,
  productDiscount: productDiscount,
  generalDiscount: generalDiscount,
  itbis: 18,
  total: 118 + exempt,
  fiscalTaxEnabled: true,
  ecf: electronic ? fixture.fiscal() : null,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es_DO'));

  for (final width in [58.0, 80.0]) {
    test(
      'reprint uses current ${width.toInt()}mm format without changing the stored item',
      () async {
        final data = TicketData.fromSale(
          fixture.sale(),
          ecf: fixture.fiscal(),
          isCopy: true,
        );
        expect(data.items.single.name, contains('(Unidad)'));
        expect(data.items.single.compactName, isNot(contains('(Unidad)')));
        final receipt = ThermalReceiptViewModel.fromTicketData(
          data: data,
          company: const CompanyInfo(name: 'EMPRESA FICTICIA'),
        );
        final bytes = await HtmlThermalReceiptPdfRenderer(
          paperWidthMm: width,
        ).render(receipt);
        final document = pdf.PdfDocument(inputBytes: bytes);
        try {
          final extractor = pdf.PdfTextExtractor(document);
          final text = extractor.extractText().replaceAll(RegExp(r'\s+'), ' ');
          expect(text.toUpperCase().replaceAll(' ', '').contains('(UNIDAD)'), width == 58);
          expect(
            RegExp(r'\bITBIS\b').allMatches(text).length,
            width == 80 ? 1 : 2,
          );
          if (width == 80) {
            final words = extractor
                .extractTextLines()
                .expand((line) => line.wordCollection)
                .toList();
            final heading = words.firstWhere((word) => word.text == 'CANT');
            final header = words
                .where(
                  (word) => (word.bounds.top - heading.bounds.top).abs() < 1,
                )
                .toList();
            expect(header.map((word) => word.text).toList(), [
              'CANT',
              'ITEM',
              'PRECIO',
              'TOTAL',
            ]);
            for (final word in header) {
              expect(word.fontSize, closeTo(9, 0.05));
            }
            final raw = FullPosEscPosReceiptRenderer()
                .previewLines(receipt)
                .join('\n');
            expect(raw, isNot(contains('(Unidad)')));
            expect(RegExp(r'\bITBIS\b').allMatches(raw).length, 1);
          }
        } finally {
          document.dispose();
        }
        final html = HtmlThermalReceiptRenderer(
          paperWidthMm: width,
        ).render(receipt);
        expect(html.contains('<th class="price">ITBIS</th>'), width == 58);
        expect(html.contains('(UNIDAD)'), width == 58);
        final dir = Directory('../../.uat/subtotal-preview')
          ..createSync(recursive: true);
        File(
          '${dir.path}/reprinted-${width.toInt()}.pdf',
        ).writeAsBytesSync(bytes);
      },
    );
  }

  for (final electronic in [false, true]) {
    test(
      '80mm long item stays on one line at 9pt, electronic=$electronic',
      () async {
        const name =
            'Lector inalámbrico profesional de códigos de barra para el negocio';
        final receipt = ThermalReceiptViewModel.fromTicketData(
          data: ticket(electronic: electronic, productName: name),
          company: const CompanyInfo(name: 'EMPRESA FICTICIA'),
        );
        final bytes = await const HtmlThermalReceiptPdfRenderer().render(
          receipt,
        );
        final document = pdf.PdfDocument(inputBytes: bytes);
        try {
          final extractor = pdf.PdfTextExtractor(document);
          expect(
            extractor.extractText().replaceAll(RegExp(r'\s+'), ' '),
            contains('Lector inalámbrico'),
          );
          final words = extractor
              .extractTextLines()
              .expand((line) => line.wordCollection)
              .toList();
          for (final word in words.where(
            (word) => [
              'Lector',
              'inalámbrico',
              'profesional',
              'códigos',
              'barra',
              'negocio',
            ].contains(word.text),
          )) {
            expect(word.fontSize, closeTo(9, 0.05), reason: word.text);
          }
          expect(words.where((word) => word.text == 'Lector'), isNotEmpty);
          final itemWords = words
              .where(
                (word) =>
                    word.text == 'Lector' ||
                    word.text == 'inalámbrico' ||
                    word.text.endsWith('...'),
              )
              .toList();
          expect(itemWords.any((word) => word.text.endsWith('...')), isTrue);
          final baseline = itemWords.first.bounds.top;
          expect(
            itemWords.every((word) => (word.bounds.top - baseline).abs() < 1),
            isTrue,
          );
        } finally {
          document.dispose();
        }
        final dir = Directory('../../.uat/subtotal-preview')
          ..createSync(recursive: true);
        File(
          '${dir.path}/legible-item-${electronic ? 'electronic' : 'normal'}-80.pdf',
        ).writeAsBytesSync(bytes);
      },
    );
  }

  final cases = <String, TicketData>{
    'electronic': ticket(),
    'normal-itbis': ticket(electronic: false),
    'mixed': ticket(subtotal: 150, exempt: 50),
    'discount': ticket(subtotal: 110, productDiscount: 10),
    'legacy-discount': ticket(discount: 10),
    'general-discount': ticket(generalDiscount: 10),
    'different-base': ticket(subtotal: 100.01),
  };
  for (final entry in cases.entries) {
    final combined = entry.key == 'electronic';
    test('${entry.key}: models and HTML/RAW preserve the correct subtotal', () {
      final data = entry.value;
      final receipt = ThermalReceiptViewModel.fromTicketData(
        data: data,
        company: const CompanyInfo(name: 'EMPRESA FICTICIA'),
      );
      expect(data.combinesSubtotal, combined);
      expect(receipt.combinesSubtotal, combined);
      final outputs = [
        const HtmlThermalReceiptRenderer().render(receipt),
        FullPosEscPosReceiptRenderer().previewLines(receipt).join('\n'),
        TicketRenderer(
          layout: TicketLayoutConfig.fromPrinterSettings(
            const PrinterSettingsModel(),
          ),
          company: const CompanyInfo(
            name: 'EMPRESA FICTICIA',
            phone: '809-555-0100',
          ),
        ).buildLines(data).join('\n').toUpperCase(),
      ];
      for (final text in outputs) {
        expect(text, isNot(contains('ITBIS:')));
        expect(text, contains(combined ? 'SUBTOTAL GRAVADO' : 'SUBTOTAL'));
        expect(text.contains('MONTO GRAVADO'), !combined);
        if (data.ecf == null) expect(text, isNot(contains('SUBTOTAL GRAVADO')));
        expect(text, contains('ITBIS'));
      }
    });
    for (final width in [58.0, 80.0]) {
      test(
        '${entry.key}: PDF $width mm retains amounts without duplicate bases',
        () async {
          final receipt = ThermalReceiptViewModel.fromTicketData(
            data: entry.value,
            company: const CompanyInfo(
              name: 'EMPRESA FICTICIA',
              phone: '809-555-0100',
            ),
          );
          final bytes = await HtmlThermalReceiptPdfRenderer(
            paperWidthMm: width,
          ).render(receipt);
          final document = pdf.PdfDocument(inputBytes: bytes);
          try {
            final text = pdf.PdfTextExtractor(
              document,
            ).extractText().replaceAll(RegExp(r'\s+'), ' ');
            expect(text, contains(combined ? 'SUBTOTAL GRAVADO' : 'SUBTOTAL'));
            expect(text, isNot(contains('ITBIS:')));
            if (combined && width == 58) {
              final words = pdf.PdfTextExtractor(document)
                  .extractTextLines()
                  .expand((line) => line.wordCollection)
                  .toList();
              final tax = words.firstWhere((word) => word.text == '18.00');
              final price = words.firstWhere((word) => word.text == '100.00');
              final total = words.firstWhere((word) => word.text == '118.00');
              expect(tax.bounds.top, closeTo(price.bounds.top, 1));
              expect(tax.bounds.top, closeTo(total.bounds.top, 1));
            }
            expect(text.contains('MONTO GRAVADO'), !combined);
            if (entry.key == 'normal-itbis') {
              expect(text, isNot(contains('SUBTOTAL GRAVADO')));
            }
            expect(text, contains('ITBIS'));
            expect(text, contains(entry.value.total.toStringAsFixed(2)));
            if (entry.key == 'mixed') expect(text, contains('MONTO EXENTO'));
            if (entry.key == 'discount') {
              expect(text, contains('DESC. PRODUCTOS'));
            }
          } finally {
            document.dispose();
          }
          if (combined || entry.key == 'normal-itbis') {
            final dir = Directory('../../.uat/subtotal-preview')
              ..createSync(recursive: true);
            File(
              '${dir.path}/${entry.key}-${width.toInt()}.pdf',
            ).writeAsBytesSync(bytes);
          }
        },
      );
    }
  }

  for (final electronic in [false, true]) {
    test(
      'Letter invoice keeps ${electronic ? 'electronic' : 'ordinary'} subtotal identity',
      () async {
        final bytes = await buildSaleInvoicePdf(
          sale: fixture.sale(voucherType: electronic ? 'E31' : 'NORMAL'),
          ecf: electronic ? fixture.fiscal() : null,
        );
        final document = pdf.PdfDocument(inputBytes: bytes);
        try {
          final text = pdf.PdfTextExtractor(
            document,
          ).extractText().replaceAll(RegExp(r'\s+'), ' ');
          expect(text, contains(electronic ? 'Subtotal gravado' : 'Subtotal'));
          if (electronic) expect(text, isNot(contains('Base imponible')));
          if (!electronic) expect(text, isNot(contains('Subtotal gravado')));
          expect(text, contains('ITBIS'));
          if (electronic) expect(text, contains('Unidad'));
        } finally {
          document.dispose();
        }
      },
    );
  }
}
