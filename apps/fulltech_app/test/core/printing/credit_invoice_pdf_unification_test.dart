import 'dart:io';

import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'credit_ticket_test.dart' show creditSale;

class _Company implements CompanySettingsRepository {
  @override
  Future<CompanySettings?> getCachedSettings() async => CompanySettings.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Printer implements PrinterSettingsRepository {
  @override
  Future<PrinterSettingsModel> getOrCreate() async => const PrinterSettingsModel();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('es_DO'));
  for (final stage in [(paid: 0.0,balance: 2500.0), (paid: 1000.0,balance: 1500.0), (paid: 1500.0,balance: 1000.0), (paid: 2500.0,balance: 0.0)]) {
    test('one A4 invoice template for billing and credit: paid ${stage.paid}', () async {
      final container = ProviderContainer(overrides: [
        companySettingsRepositoryProvider.overrideWithValue(_Company()),
        printerSettingsRepositoryProvider.overrideWithValue(_Printer()),
      ]);
      addTearDown(container.dispose);
      final sale = creditSale(paid: stage.paid,balance: stage.balance);
      final original = TicketData.fromSale(sale);
      final fromSharedService = await container.read(unifiedTicketPrinterProvider).buildSaleInvoicePdf(sale: sale);
      final fromInvoiceTemplate = await buildSaleInvoicePdf(sale: sale,company: CompanySettings.empty(),warrantyPolicy: const PrinterSettingsModel().warrantyPolicy);
      expect(original.credit!.paid,stage.paid);
      expect(original.credit!.balance,stage.balance);
      final dir = Directory('../../.uat/credit-ticket')..createSync(recursive:true);
      await File('${dir.path}/a4-shared-${stage.paid.toInt()}.pdf').writeAsBytes(fromSharedService);
      await File('${dir.path}/a4-invoice-${stage.paid.toInt()}.pdf').writeAsBytes(fromInvoiceTemplate);
      expect(fromSharedService.length,greaterThan(1000));
    });
  }
}
