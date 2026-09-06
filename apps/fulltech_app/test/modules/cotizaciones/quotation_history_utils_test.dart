import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/quotation_history_utils.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
  });

  group('quotation history timezone formatting', () {
    test('formats UTC API timestamps using device local time', () {
      final utc = DateTime.parse('2026-09-05T15:43:00.000Z');
      final expectedLocal = utc.toLocal();

      expect(quotationHistoryLocalDate(utc), expectedLocal);
      expect(
        formatQuotationHistoryDate(utc, pattern: 'HH:mm'),
        '${expectedLocal.hour.toString().padLeft(2, '0')}:43',
      );
    });

    test('keeps local/offline timestamps local without manual offset', () {
      final offlineLocal = DateTime(2026, 9, 5, 11, 43);

      expect(quotationHistoryLocalDate(offlineLocal).isUtc, isFalse);
      expect(quotationHistoryLocalDate(offlineLocal).hour, 11);
      expect(
        formatQuotationHistoryDate(offlineLocal, pattern: 'HH:mm'),
        '11:43',
      );
    });

    test('does not double-convert a parsed local cache timestamp', () {
      final parsed = DateTime.parse('2026-09-05T11:43:00.000');
      final displayed = quotationHistoryLocalDate(parsed);

      expect(parsed.isUtc, isFalse);
      expect(displayed.hour, 11);
      expect(displayed.minute, 43);
    });
  });

  group('quotation client search', () {
    test('matches by name case-insensitively', () {
      expect(
        matchesQuotationClientSearch(
          label: 'Manuel Rodríguez',
          phone: '829-260-9061',
          query: 'manuel',
        ),
        isTrue,
      );
    });

    test('matches by phone ignoring whitespace and punctuation', () {
      expect(
        matchesQuotationClientSearch(
          label: 'Manuel Rodríguez',
          phone: '(829) 260-9061',
          query: '260 9061',
        ),
        isTrue,
      );
      expect(
        matchesQuotationClientSearch(
          label: 'Manuel Rodríguez',
          phone: '(829) 260-9061',
          query: '829',
        ),
        isTrue,
      );
    });
  });

  group('quotation history panel summary', () {
    test('metrics and chart follow the provided visible quotation set', () {
      final visible = [
        _quote(
          id: 'q-1',
          customerId: 'client-manuel',
          customerName: 'Manuel',
          createdAt: DateTime.utc(2026, 9, 5, 15, 43),
          total: 1200,
          lineCount: 2,
        ),
        _quote(
          id: 'q-2',
          customerId: 'client-manuel',
          customerName: 'Manuel',
          createdAt: DateTime.utc(2026, 9, 5, 16, 10),
          total: 800,
          lineCount: 1,
        ),
      ];

      final summary = buildQuotationHistoryPanelSummary(
        visible,
        clientKeyFor: (item) => item.customerId ?? item.customerName,
        isOwnClient: (item) => item.customerId == 'client-manuel',
      );

      expect(summary.visibleCount, 2);
      expect(summary.uniqueClientsCount, 1);
      expect(summary.totalLines, 3);
      expect(summary.totalAmount, 2000);
      expect(summary.ownClientsCount, 2);
      expect(summary.topClients.single.name, 'Manuel');
      expect(summary.topClients.single.total, 2000);
      expect(summary.chartBuckets, hasLength(1));
      expect(summary.chartBuckets.single.total, 2000);
    });
  });
}

CotizacionModel _quote({
  required String id,
  required String customerId,
  required String customerName,
  required DateTime createdAt,
  required double total,
  required int lineCount,
}) {
  return CotizacionModel(
    id: id,
    createdAt: createdAt,
    customerId: customerId,
    customerName: customerName,
    customerPhone: '8292609061',
    note: '',
    includeItbis: false,
    itbisRate: 0.18,
    totalSnapshot: total,
    items: [
      for (var index = 0; index < lineCount; index++)
        CotizacionItem(
          productId: 'product-$index',
          nombre: 'Producto $index',
          imageUrl: null,
          unitPrice: total / lineCount,
          qty: 1,
          lineTotalSnapshot: total / lineCount,
        ),
    ],
  );
}
