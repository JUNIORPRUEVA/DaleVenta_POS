import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdf;

import 'ecf_print_representation_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List logo;
  setUpAll(() async {
    logo = await File('assets/image/logo.png').readAsBytes();
  });
  ThermalReceiptViewModel receipt({
    bool withLogo = true,
    String state = 'SIGNED',
  }) => ThermalReceiptViewModel.fromTicketData(
    data: TicketData.fromSale(
      fixture.sale(),
      ecf: fixture.fiscal(state: state),
      paymentMethod: 'Efectivo',
    ),
    company: CompanyInfo(
      name: 'PRUEBA LOCAL SIN VALIDEZ FISCAL',
      logoBytes: withLogo ? logo : null,
    ),
  );
  for (final width in [58.0, 80.0]) {
    for (final withLogo in [true, false]) {
      test(
        '$width mm PDF conserva logo y termina después del sello: logo=$withLogo',
        () async {
          final bytes = await HtmlThermalReceiptPdfRenderer(
            paperWidthMm: width,
          ).render(receipt(withLogo: withLogo));
          final raw = latin1.decode(bytes);
          expect(RegExp(r'/Subtype\s*/Image').hasMatch(raw), withLogo);
          final document = pdf.PdfDocument(inputBytes: bytes);
          try {
            final lines = pdf.PdfTextExtractor(document).extractTextLines();
            final security = lines.firstWhere(
              (line) => line.text.contains('S9Qvrj'),
            );
            final thanks = lines.firstWhere(
              (line) => line.text.contains('GRACIAS'),
            );
            expect(security.bounds.bottom, lessThan(thanks.bounds.top));
            final text = pdf.PdfTextExtractor(document).extractText();
            expect(text, contains('E310000000002'));
            expect(text, contains('133080206'));
            expect(text, isNot(contains('LOGO')));
          } finally {
            document.dispose();
          }
          final out = Directory('../../.uat/ecf-ticket-hotfix')
            ..createSync(recursive: true);
          await File(
            '${out.path}/ecf-${width.toInt()}-${withLogo ? "logo" : "no-logo"}.pdf',
          ).writeAsBytes(bytes);
        },
      );
    }
  }
  test('HTML coloca QR y firma antes del agradecimiento', () {
    final html = const HtmlThermalReceiptRenderer().render(receipt());
    expect(html, contains('alt="Logo"'));
    expect(
      html.indexOf('QR de consulta DGII'),
      lessThan(html.indexOf('GRACIAS')),
    );
    expect(html.indexOf('S9Qvrj'), lessThan(html.indexOf('GRACIAS')));
    final withoutLogo = const HtmlThermalReceiptRenderer().render(
      receipt(withLogo: false),
    );
    expect(withoutLogo, isNot(contains('<div class="logo logo-placeholder">')));
  });
  test(
    'RAW incluye logo antes de la factura y sello antes del agradecimiento',
    () async {
      final renderer = FullPosEscPosReceiptRenderer();
      final bytes = await renderer.render(receipt());
      final withoutLogo = await renderer.render(receipt(withLogo: false));
      int rasters(List<int> data) {
        var count = 0;
        for (var i = 0; i + 2 < data.length; i++) {
          if (data[i] == 0x1d && data[i + 1] == 0x76 && data[i + 2] == 0x30) {
            count++;
          }
        }
        return count;
      }

      expect(rasters(bytes), rasters(withoutLogo) + 1);
      final text = latin1.decode(bytes);
      expect(
        text.indexOf('Codigo de seguridad:'),
        lessThan(text.indexOf('GRACIAS')),
      );
      expect(
        text.indexOf('Fecha de firma:'),
        lessThan(text.indexOf('GRACIAS')),
      );
      final out = Directory('../../.uat/ecf-ticket-hotfix')
        ..createSync(recursive: true);
      await File('${out.path}/ecf-80-logo.raw').writeAsBytes(bytes);
    },
  );
  test('texto heredado también deja el cierre después del sello', () {
    final data = TicketData.fromSale(fixture.sale(), ecf: fixture.fiscal());
    final layout = TicketLayoutConfig.fromPrinterSettings(
      PrinterSettingsModel(),
    );
    final text = TicketRenderer(
      layout: layout,
      company: const CompanyInfo(name: 'LOCAL'),
    ).buildLines(data).join('\n');
    expect(text.indexOf('S9Qvrj'), lessThan(text.indexOf('Gracias')));
  });
  test(
    'pendiente y rechazado no inventan un QR al reordenar el cierre',
    () async {
      for (final state in ['PENDING', 'REJECTED']) {
        final bytes = await const HtmlThermalReceiptPdfRenderer().render(
          receipt(state: state),
        );
        final document = pdf.PdfDocument(inputBytes: bytes);
        final text = pdf.PdfTextExtractor(document).extractText();
        expect(text, contains('GRACIAS'));
        expect(text, isNot(contains('S9Qvrj')));
        document.dispose();
      }
    },
  );
}
