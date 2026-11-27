import 'dart:io';

import 'package:daleventa_pos/core/printing/esc_pos/fullpos_esc_pos_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/esc_pos/thermal_receipt_view_model.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_renderer.dart';
import 'package:daleventa_pos/core/printing/html/html_thermal_receipt_pdf_renderer.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_builder.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdfread;

SaleModel creditSale({
  double paid = 1000,
  double balance = 1500,
  String method = 'credit',
  String kind = 'invoice',
  String productName = 'Producto de prueba',
  bool realReceiptFields = false,
  bool taxEnabled = false,
}) => SaleModel.fromJson({
  'id': '00000000-0000-4000-8000-000012345678',
  'userId': 'cashier', 'userName': 'Caja de prueba',
  'customerName': 'Cliente de prueba', 'saleDate': '2026-11-26T14:00:00Z',
  'customer': {'nombre': 'Cliente de credito', 'telefono': '8095550101'},
  'totalSold': 2500, 'paymentMethod': method, 'kind': kind,
  'paymentCashAmount': paid, 'paymentTransferAmount': 0,
  'creditAmount': 1500, 'creditPaidAmount': paid, 'creditBalance': balance,
  'creditStatus': balance == 0 ? 'paid' : 'open',
  'fiscalTaxEnabled': taxEnabled,
  if (realReceiptFields) ...{
    'cashReceived': 1000, 'changeAmount': 0, 'exemptAmount': 2500,
  },
  // A ledger projection must not be counted on top of accumulated sale money.
  'creditPayments': [
    {'amount': 500, 'cashAmount': 500},
  ],
  'items': [
    {
      'productNameSnapshot': productName,
      'qty': 1,
      'priceSoldUnit': 2500,
      'subtotalSold': 2500,
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const company = CompanyInfo(name: 'Negocio de prueba');
  for (final width in [58, 80]) {
    for (final taxesEnabled in [false, true]) {
      test('$width mm exempt breakdown follows the saved tax setting: $taxesEnabled', () async {
        final sale = creditSale(realReceiptFields: true, taxEnabled: taxesEnabled);
        final data = TicketData.fromSale(sale);
        final receipt = ThermalReceiptViewModel.fromTicketData(data: data, company: company);
        final layout = TicketLayoutConfig.fromPrinterSettings(PrinterSettingsModel(paperWidthMm: width));
        final outputs = [
          HtmlThermalReceiptRenderer(paperWidthMm: width.toDouble()).render(receipt),
          FullPosEscPosReceiptRenderer(profile: width == 58 ? ThermalPrinterProfile.mm58() : ThermalPrinterProfile.mm80()).previewLines(receipt).join('\n'),
          TicketRenderer(layout: layout, company: company).buildLines(data).join('\n'),
        ];
        for (final bytes in [
          await HtmlThermalReceiptPdfRenderer(paperWidthMm: width.toDouble()).render(receipt),
          await TicketBuilder(layout: layout, company: company).buildPdf(data),
        ]) {
          final pdf = pdfread.PdfDocument(inputBytes: bytes);
          try { outputs.add(pdfread.PdfTextExtractor(pdf).extractText()); }
          finally { pdf.dispose(); }
        }
        for (final output in outputs) {
          final text = output.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
          expect(text.contains('EXENTO'), taxesEnabled, reason: 'Disabled taxes must not be presented as an exemption');
          expect(text, contains('ABONADO'));
          expect(text, contains('PENDIENTE'));
        }
        expect(data.exemptAmount, 2500); // Presentation never rewrites financial data.
        expect(data.total, 2500);
        expect(data.credit!.paid, 1000);
        expect(data.credit!.balance, 1500);
      });
    }
  }
  for (final width in [58, 80]) {
    for (final paid in [1000.0, 1500.0, 2500.0]) {
      test('$width mm actual Windows PDF retains credit after wrapped items: $paid', () async {
        final sale = creditSale(
          paid: paid, balance: 2500 - paid,
          realReceiptFields: true,
          productName: 'PRODUCTO CREDITO NATIVO 20D789AB-0199-4ED0-A486-B3CF84BE4C11',
        );
        final receipt = ThermalReceiptViewModel.fromTicketData(
          data: TicketData.fromSale(sale, isCopy: true),
          company: const CompanyInfo(
            name: 'FULLPOS PRUEBA DE CREDITO', address: 'SIN VALIDEZ FISCAL',
          ),
        );
        final bytes = await HtmlThermalReceiptPdfRenderer(
          paperWidthMm: width.toDouble(),
        ).render(receipt);
        final dir = Directory('../../.uat/credit-ticket')..createSync(recursive: true);
        File('${dir.path}/windows-layout-$width-${paid.toInt()}.pdf').writeAsBytesSync(bytes);
        final document = pdfread.PdfDocument(inputBytes: bytes);
        try {
          expect(document.pages.count, 1);
          final text = pdfread.PdfTextExtractor(document).extractText()
              .replaceAll(RegExp(r'\s+'), ' ');
          expect(text, contains('ABONADO'));
          expect(text, contains(width == 80 ? 'PENDIENTE' : 'SALDO PENDIENTE'));
          final paidText = {1000.0: '1,000.00', 1500.0: '1,500.00', 2500.0: '2,500.00'}[paid]!;
          final balanceText = {1000.0: '1,500.00', 1500.0: '1,000.00', 2500.0: '0.00'}[paid]!;
          expect(text, contains('ABONADO RD\$ $paidText'));
          expect(text, contains('${width == 80 ? 'PENDIENTE' : 'SALDO PENDIENTE'} RD\$ $balanceText'));
          expect(text, contains('FullPOS Cloud'));
          for (final line in pdfread.PdfTextExtractor(document).extractTextLines()) {
            expect(line.bounds.bottom, lessThanOrEqualTo(document.pages[0].size.height + 0.1),
              reason: 'Text outside printable page: ${line.text}');
            expect(line.bounds.top, greaterThanOrEqualTo(-0.1));
          }
        } finally {
          document.dispose();
        }
      });
    }
  }
  for (final width in [58, 80]) {
    for (final stage in [
      (paid: 0.0, balance: 2500.0),
      (paid: 1000.0, balance: 1500.0),
      (paid: 1500.0, balance: 1000.0),
      (paid: 2500.0, balance: 0.0),
    ]) {
      test(
        '$width mm: paid ${stage.paid}, balance ${stage.balance}, same invoice',
        () async {
          final sale = creditSale(paid: stage.paid, balance: stage.balance);
          final data = TicketData.fromSale(sale, isCopy: true);
          expect(data.credit!.amount, 2500);
          expect(data.credit!.paid, stage.paid);
          expect(data.credit!.balance, stage.balance);
          expect(data.paymentMethod, startsWith('Credito'));
          expect(data.ticketNumber, TicketData.fromSale(sale).ticketNumber);
          final vm = ThermalReceiptViewModel.fromTicketData(
            data: data,
            company: company,
          );
          final layout = TicketLayoutConfig.fromPrinterSettings(
            PrinterSettingsModel(
              paperWidthMm: width,
              charsPerLine: width == 58 ? 32 : 48,
            ),
          );
          final text = TicketRenderer(
            layout: layout,
            company: company,
          ).buildLines(data).join('\n');
          final esc = FullPosEscPosReceiptRenderer(
            profile: width == 58
                ? ThermalPrinterProfile.mm58()
                : ThermalPrinterProfile.mm80(),
          ).previewLines(vm).join('\n');
          final html = HtmlThermalReceiptRenderer(
            paperWidthMm: width.toDouble(),
          ).render(vm);
          for (final output in [text, esc, html]) {
            expect(output, contains('ABONADO'));
            expect(output, contains('SALDO PENDIENTE'));
            expect(output, contains('COMPRA A CREDITO'));
          }
          final pdf = await TicketBuilder(
            layout: layout,
            company: company,
          ).buildPdf(data);
          final alternate = await HtmlThermalReceiptPdfRenderer(
            paperWidthMm: width.toDouble(),
          ).render(vm);
          expect(pdf.length, greaterThan(100));
          expect(alternate.length, greaterThan(100));
          final dir = Directory('../../.uat/credit-ticket')
            ..createSync(recursive: true);
          File(
            '${dir.path}/ticket-$width-${stage.paid.toInt()}.pdf',
          ).writeAsBytesSync(pdf);
          File(
            '${dir.path}/alternate-$width-${stage.paid.toInt()}.pdf',
          ).writeAsBytesSync(alternate);
        },
      );
    }
  }
  test(
    'cash, refund and fiscal credit note do not acquire a customer debt',
    () {
      expect(TicketData.fromSale(creditSale(method: 'cash')).credit, isNull);
      expect(TicketData.fromSale(creditSale(kind: 'refund')).credit, isNull);
      expect(
        TicketData(
          ticketNumber: 'E34',
          dateTime: nullDate,
          items: const [],
          total: 2500,
          type: TicketType.credit,
        ).credit,
        isNull,
      );
    },
  );
}

final nullDate = DateTime(2026, 11, 26);
