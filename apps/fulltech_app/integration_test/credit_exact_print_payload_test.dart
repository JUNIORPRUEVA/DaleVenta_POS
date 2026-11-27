import 'dart:convert';
import 'dart:io';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/thermal_printer_service.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:printing/printing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: depend_on_referenced_packages
import 'package:syncfusion_flutter_pdf/pdf.dart' as pdfread;

class _Company implements CompanyInfoRepository {
  @override
  Future<CompanyInfo> getCurrentCompanyInfo() async => const CompanyInfo(
    name: 'FULLPOS LABORATORIO CREDITO', address: 'PRUEBA LOCAL SIN VALIDEZ FISCAL',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('exact Windows PDF sent to printer omits disabled tax breakdown', (tester) async {
    expect(Platform.isWindows, isTrue);
    const directory = String.fromEnvironment('CREDIT_TICKET_LAB_DIR');
    expect(directory, 'C:/t/fp-credit-20261126/.uat/credit-ticket');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final account = jsonDecode(await File('$directory/manual-account.json').readAsString()) as Map;
    final sale = SaleModel.fromJson(jsonDecode(await File('$directory/manual-current-sale.json').readAsString()) as Map<String,dynamic>);
    expect(sale.fiscalTaxEnabled, isFalse);
    expect(sale.taxAmount, 0);
    expect(sale.taxableBase, 0);
    final settings = PrinterSettingsRepository(companyId: (account['user'] as Map)['companyId'] as String);
    final saved = await settings.getOrCreate();
    expect(saved.selectedPrinterName, '2C-POS80-01-V8 Printer');
    var submissions = 0;
    final thermal = ThermalPrinterService(directPdfPrinter: ({
      required printer, required name, required format, required dynamicLayout,
      required usePrinterSettings, required onLayout,
    }) async {
      final bytes = await onLayout(format);
      await File('$directory/exact-windows-sent.pdf').writeAsBytes(bytes);
      final pdf = pdfread.PdfDocument(inputBytes: bytes);
      try {
        final text = pdfread.PdfTextExtractor(pdf).extractText().replaceAll(RegExp(r'\s+'), ' ');
        await File('$directory/exact-windows-sent.txt').writeAsString(text);
        expect(text.toUpperCase(), isNot(contains('EXENTO')));
        expect(text.toUpperCase(), isNot(contains('GRAVADO')));
        expect(text.toUpperCase(), isNot(contains('ITBIS')));
        expect(text, isNot(contains('LOGO')));
        if (sale.paymentMethod == 'credit') {
          expect(text, contains('ABONADO'));
          expect(text, contains('PENDIENTE'));
        } else if (sale.paymentMethod == 'cash') {
          for (final duplicate in ['ABONADO', 'PENDIENTE', 'PAGO:', 'EFECTIVO']) {
            expect(text, isNot(contains(duplicate)));
          }
          expect(text, contains('NOTA Pago: Efectivo'));
        }
        expect(text, isNot(contains('TOTAL COMPRA')));
        expect(text, isNot(contains('SUBTOTAL')));
        expect(text, contains('DEVUELTA'));
        expect(pdf.pages.count, 1);
        for (final line in pdfread.PdfTextExtractor(pdf).extractTextLines()) {
          expect(line.bounds.right, lessThanOrEqualTo(72 * 72 / 25.4), reason: line.text);
          expect(line.bounds.bottom, lessThanOrEqualTo(pdf.pages[0].size.height + .1));
        }
      } finally { pdf.dispose(); }
      submissions++;
      // Delegate to the real Windows plugin with the EXACT verified bytes.
      return Printing.directPrintPdf(printer: printer, name: name, format: format,
        dynamicLayout: dynamicLayout, usePrinterSettings: usePrinterSettings,
        onLayout: (_) async => bytes);
    });
    final scope = ProviderContainer(overrides: [
      companyInfoRepositoryProvider.overrideWithValue(_Company()),
      printerSettingsRepositoryProvider.overrideWithValue(settings),
      unifiedTicketPrinterProvider.overrideWith((ref) => UnifiedTicketPrinter(ref, thermalPrinterService: thermal)),
    ]);
    try {
      final result = await scope.read(unifiedTicketPrinterProvider).reprintSale(sale: sale, copies: 1);
      expect(result.success, isTrue, reason: result.message);
      expect(submissions, 1);
      await File('$directory/exact-windows-print-result.json').writeAsString(jsonEncode({
        'result': 'PASS_EXACT_PDF_AND_SUBMISSION', 'saleId': sale.id,
        'total': sale.totalSold, 'paid': sale.creditPaidAmount, 'balance': sale.creditBalance,
        'submissions': submissions, 'paperContentConfirmed': false,
      }));
    } finally { scope.dispose(); }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
