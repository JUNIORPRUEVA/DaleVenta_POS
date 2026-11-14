import 'dart:io';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/features/ecf/ecf_print_document.dart';
import 'package:daleventa_pos/core/printing/ecf_print_footer.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';
import 'package:image/image.dart' as img;
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdfread;

const qr =
    'https://ecf.dgii.gov.do/testecf/ConsultaTimbre?RNCEmisor=133080206&RncComprador=133306001&ENCF=E310000000002&FechaEmision=13-11-2026&MontoTotal=118.00&FechaFirma=13-11-2026%2008:45:19&CodigoSeguridad=S9Qvrj';
EcfPrintDocument fiscal({String state = 'SIGNED'}) => EcfPrintDocument(
  documentId: 'synthetic-doc',
  documentType: 'E31',
  label: 'Factura de Crédito Fiscal Electrónica',
  encf: 'E310000000002',
  environment: 'SANDBOX',
  state: state,
  contingencyLegend: state == 'CONTINGENCY' ? 'EMITIDO EN CONTINGENCIA - PENDIENTE DGII' : null,
  issueDate: '2026-11-13',
  total: '118.00',
  subtotal: '100.00',
  issuerName: 'EMPRESA DEMOSTRACION SRL',
  issuerRnc: '133080206',
  issuerAddress: 'Santo Domingo, Distrito Nacional',
  buyerName: 'RECEPTOR DE PRUEBA',
  buyerRnc: '133306001',
  expiresAt: '2028-12-31',
  qrUrl: state == 'SIGNED' || state == 'CONTINGENCY' ? qr : null,
  securityCode: state == 'SIGNED' || state == 'CONTINGENCY' ? 'S9Qvrj' : null,
  signedAt: state == 'SIGNED' || state == 'CONTINGENCY' ? '13-11-2026 08:45:19' : null,
);
SaleModel sale({String? voucherType = 'E31'}) => SaleModel.fromJson({
  'id': '00000000-0000-4000-8000-000000000001',
  'userId': 'synthetic-user',
  'saleDate': '2026-11-13T12:00:00Z',
  'totalSold': 118,
  'taxableBase': 100,
  'taxAmount': 18,
  'fiscalTaxEnabled': true,
  'fiscalVoucherType': voucherType,
  'fiscalPriceMode': 'TAX_ADDED',
  'items': [
    {
      'id': 'item',
      'productNameSnapshot': 'Artículo de demostración',
      'qty': 1,
      'priceSoldUnit': 100,
      'subtotalSold': 118,
      'taxableBase': 100,
      'taxAmount': 18,
      'taxExempt': false,
      'unitNameSnapshot': 'Unidad',
    },
  ],
});
ThermalReceiptViewModel receipt({String state = 'SIGNED'}) =>
    ThermalReceiptViewModel.fromTicketData(
      data: TicketData.fromSale(sale(), ecf: fiscal(state: state)),
      company: const CompanyInfo(name: 'EMPRESA DEMOSTRACION SRL'),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es_DO'));
  test('mismatched amounts cannot print a valid QR against another total', () {
    expect(fiscal().matchesTotal(119), isFalse);
    expect(fiscal().matchesTotal(118), isTrue);
  });
  test('Normal with ITBIS prints an ordinary ticket and PDF without fiscal identity or QR', () async {
    final normal=sale(voucherType:'NORMAL');
    final data=TicketData.fromSale(normal);
    expect(data.fiscalVoucherType,isNull);expect(data.ncf,isNull);expect(data.ecf,isNull);
    final bytes=await buildSaleInvoicePdf(sale:normal);
    final document=pdfread.PdfDocument(inputBytes:bytes);
    final text=pdfread.PdfTextExtractor(document).extractText();
    expect(text,contains('ITBIS'));
    expect(text, isNot(contains('e-NCF')));expect(text,isNot(contains('Código de seguridad')));
    document.dispose();
    await expectLater(buildSaleInvoicePdf(sale:normal,ecf:fiscal()),throwsStateError);
  });
  test('legacy NULL and blank intents keep ITBIS and ordinary PDF behavior', () async {
    for (final type in [null, '', 'NORMAL']) {
      final ordinary = sale(voucherType: type);
      expect(ordinary.requiresElectronicPrint, isFalse);
      final bytes = await buildSaleInvoicePdf(sale: ordinary);
      final pdf = pdfread.PdfDocument(inputBytes: bytes);
      final text = pdfread.PdfTextExtractor(pdf).extractText();
      expect(text, contains('ITBIS'));
      expect(text, isNot(contains('e-NCF')));
      pdf.dispose();
    }
    final historical = SaleModel.fromJson({'id': 'historic', 'fiscalVoucherType': null,
      'hasElectronicFiscalDocument': true, 'totalSold': 118});
    expect(historical.requiresElectronicPrint, isTrue);
    await expectLater(buildSaleInvoicePdf(sale: historical), throwsStateError);
  });
  test('contingency prints the validated QR and a pending legend in ticket and PDF', () async {
    final pending=fiscal(state:'CONTINGENCY');
    expect(pending.hasStamp,isTrue);expect(pending.notice,contains('PENDIENTE DGII'));
    final bytes=await buildSaleInvoicePdf(sale:sale(),ecf:pending);
    final pdf=pdfread.PdfDocument(inputBytes:bytes);
    final text=pdfread.PdfTextExtractor(pdf).extractText().replaceAll(RegExp(r'\s+'),' ');
    expect(text,contains('PENDIENTE DGII'));expect(text,contains('S9Qvrj'));pdf.dispose();
    for(final width in [58.0,80.0]) {
      final bytes=await HtmlThermalReceiptPdfRenderer(paperWidthMm:width).render(receipt(state:'CONTINGENCY'));
      final pdf=pdfread.PdfDocument(inputBytes:bytes);
      expect(pdfread.PdfTextExtractor(pdf).extractText().replaceAll(RegExp(r'\s+'),' '),contains('PENDIENTE DGII'));
      pdf.dispose();
    }
  });
  test('an electronic sale cannot produce an ordinary PDF without its fiscal projection', () async {
    await expectLater(buildSaleInvoicePdf(sale: sale()), throwsStateError);
  });
  test(
    'every page repeats e-NCF, issuer and official verification data',
    () async {
      final many = SaleModel.fromJson({
        'id': '00000000-0000-4000-8000-000000000001',
        'userId': 'synthetic',
        'saleDate': '2026-11-13T12:00:00Z',
        'totalSold': 118,
        'taxableBase': 100,
        'taxAmount': 18,
        'fiscalTaxEnabled': true,
        'items': List.generate(
          40,
          (index) => {
            'id': 'line-$index',
            'productNameSnapshot':
                'Artículo de demostración número $index para verificar páginas completas',
            'qty': 1,
            'priceSoldUnit': 2.5,
            'subtotalSold': 2.95,
            'taxableBase': 2.5,
            'taxAmount': 0.45,
            'taxExempt': false,
          },
        ),
      });
      final bytes = await buildSaleInvoicePdf(sale: many, ecf: fiscal());
      final pdf = pdfread.PdfDocument(inputBytes: bytes);
      expect(pdf.pages.count, greaterThan(1));
      for (var page = 0; page < pdf.pages.count; page++) {
        final text = pdfread.PdfTextExtractor(pdf)
            .extractText(startPageIndex: page, endPageIndex: page)
            .replaceAll(RegExp(r'\s+'), ' ');
        expect(text, contains('E310000000002'));
        expect(text, contains('133080206'));
        expect(text, contains('S9Qvrj'));
        final rows = RegExp(r'número\s+\d+').allMatches(text).length;
        if (page < pdf.pages.count - 1) {
          expect(rows, greaterThan(0));
          expect(
            text,
            contains(
              'Monto total página: RD\$${(rows * 2.95).toStringAsFixed(2)}',
            ),
          );
          expect(
            text,
            contains(
              'Subtotal ITBIS página: RD\$${(rows * 0.45).toStringAsFixed(2)}',
            ),
          );
        }
      }
      pdf.dispose();
      final output = Platform.environment['FULLPOS_ECF_PRINT_QA'];
      if (output != null) {
        await File('$output/factura-varias-paginas.pdf').writeAsBytes(bytes);
      }
    },
  );
  test(
    'HTML keeps official QR after totals, with quiet zone, security and signature',
    () {
      final html = const HtmlThermalReceiptRenderer().render(receipt());
      expect(html, contains('data:image/svg+xml;base64,'));
      expect(html, contains('width:22mm;height:22mm'));
      expect(html, contains('padding:3mm'));
      expect(
        html.indexOf('QR de consulta DGII'),
        greaterThan(html.indexOf('¡GRACIAS')),
      );
      expect(html, contains('S9Qvrj'));
      expect(html, contains('13-11-2026 08:45:19'));
      expect(html, contains('SIN VALIDEZ FISCAL'));
    },
  );
  test('pending documents have no fabricated QR', () {
    final html = const HtmlThermalReceiptRenderer().render(
      receipt(state: 'PENDING'),
    );
    expect(html, isNot(contains('data:image/svg+xml;base64,')));
    expect(fiscal(state: 'PENDING').hasStamp, isFalse);
  });
  test('80/58mm RAW contains raster QR before paper cut', () async {
    for (final profile in [
      ThermalPrinterProfile.mm80(),
      ThermalPrinterProfile.mm58(),
    ]) {
      final bytes = await FullPosEscPosReceiptRenderer(
        profile: profile,
      ).render(receipt());
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(hex, contains('1d4c8800'));
      expect(hex, contains('1d7630'));
    }
  });
  test(
    'render PDF and raster evidence with actual product renderers',
    () async {
      final target = Platform.environment['FULLPOS_ECF_PRINT_QA'];
      for (final width in [58.0, 80.0]) {
        final bytes = await HtmlThermalReceiptPdfRenderer(
          paperWidthMm: width,
        ).render(receipt());
        expect(bytes.length, greaterThan(1500));
        final rendered = pdfread.PdfDocument(inputBytes: bytes);
        final printedText = pdfread.PdfTextExtractor(
          rendered,
        ).extractText().replaceAll(RegExp(r'\s+'), ' ');
        expect(printedText, contains('S9Qvrj'));
        expect(printedText, contains('13-11-2026 08:45:19'));
        rendered.dispose();
        if (target != null) {
          await Directory(target).create(recursive: true);
          await File('$target/ticket-${width.toInt()}.pdf').writeAsBytes(bytes);
        }
      }
      final invoice = await buildSaleInvoicePdf(sale: sale(), ecf: fiscal());
      final pending = await buildSaleInvoicePdf(
        sale: sale(),
        ecf: fiscal(state: 'PENDING'),
      );
      if (target != null) {
        await File('$target/factura-a4.pdf').writeAsBytes(invoice);
        await File('$target/factura-pendiente.pdf').writeAsBytes(pending);
        await File(
          '$target/qr-raster.png',
        ).writeAsBytes(img.encodePng(ecfQrRaster(qr)));
      }
    },
  );
}
