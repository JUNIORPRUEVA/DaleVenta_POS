import 'dart:convert';

import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/utils/sales_pdf_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Web generates an ordinary taxed PDF without native printer storage',
    () async {
      // Keep this storage regression independent of the browser test server's
      // asset transport while still constructing the real PDF with a PNG logo.
      final messenger = TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger;
      messenger.setMockMessageHandler('flutter/assets', (message) async {
        if (message == null ||
            utf8.decode(message.buffer.asUint8List(
                  message.offsetInBytes,
                  message.lengthInBytes,
                )) !=
                'assets/image/logo.png') {
          return null;
        }
        return ByteData.sublistView(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
        ));
      });
      addTearDown(() => messenger.setMockMessageHandler('flutter/assets', null));
      SharedPreferences.setMockInitialValues({
        'fulltech_printer_settings_v1': jsonEncode({
          'headerBusinessName': 'Other legacy company',
          'headerRnc': 'DO-NOT-INHERIT',
        }),
      });
      await initializeDateFormatting('es_DO');
      final settings = await PrinterSettingsRepository(
        companyId: 'web-company-a',
      ).getOrCreate();
      expect(settings.headerRnc, isEmpty);
      final sale = SaleModel.fromJson({
        'id': 'web-normal-sale',
        'userId': 'web-owner',
        'saleDate': '2026-11-14T14:00:00Z',
        'paymentMethod': 'cash',
        'fiscalVoucherType': 'NORMAL',
        'fiscalTaxEnabled': true,
        'fiscalPriceMode': 'TAX_ADDED',
        'taxableBase': 100,
        'taxAmount': 18,
        'totalSold': 118,
        'issuerNameSnapshot': 'Web test company',
        'items': [
          {
            'productNameSnapshot': 'Ordinary service',
            'qty': 1,
            'priceSoldUnit': 100,
            'subtotalSold': 118,
            'taxableBase': 100,
            'taxAmount': 18,
          },
        ],
      });
      final bytes = await buildSaleInvoicePdf(
        sale: sale,
        warrantyPolicy: settings.warrantyPolicy,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(1000));
      expect(sale.taxAmount, 18);
      expect(sale.requiresElectronicPrint, isFalse);
    },
    skip: kIsWeb ? false : 'Browser-only regression: execute with --platform chrome',
  );
}
