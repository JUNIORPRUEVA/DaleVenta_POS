import 'package:intl/intl.dart';

import 'cotizacion_models.dart';

DateTime quotationHistoryLocalDate(DateTime value) => value.toLocal();

String formatQuotationHistoryDate(
  DateTime value, {
  String pattern = 'dd/MM/yy · h:mm a',
}) {
  return DateFormat(pattern, 'es_DO').format(quotationHistoryLocalDate(value));
}

String normalizeQuotationClientSearchText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String normalizeQuotationClientPhoneSearch(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '');
}

bool matchesQuotationClientSearch({
  required String label,
  required String phone,
  required String query,
}) {
  final textQuery = normalizeQuotationClientSearchText(query);
  if (textQuery.isEmpty) return true;

  final textHaystack = normalizeQuotationClientSearchText('$label $phone');
  if (textHaystack.contains(textQuery)) return true;

  final compactTextHaystack = textHaystack.replaceAll(' ', '');
  final compactTextQuery = textQuery.replaceAll(' ', '');
  if (compactTextQuery.isNotEmpty &&
      compactTextHaystack.contains(compactTextQuery)) {
    return true;
  }

  final phoneQuery = normalizeQuotationClientPhoneSearch(query);
  if (phoneQuery.isEmpty) return false;
  return normalizeQuotationClientPhoneSearch(phone).contains(phoneQuery);
}

class QuotationHistoryPanelSummary {
  const QuotationHistoryPanelSummary({
    required this.visibleCount,
    required this.uniqueClientsCount,
    required this.totalLines,
    required this.totalAmount,
    required this.ownClientsCount,
    required this.chartBuckets,
    required this.topClients,
  });

  final int visibleCount;
  final int uniqueClientsCount;
  final int totalLines;
  final double totalAmount;
  final int ownClientsCount;
  final List<QuotationHistoryChartBucket> chartBuckets;
  final List<QuotationHistoryClientTotal> topClients;
}

class QuotationHistoryChartBucket {
  const QuotationHistoryChartBucket({
    required this.key,
    required this.label,
    required this.total,
  });

  final DateTime key;
  final String label;
  final double total;
}

class QuotationHistoryClientTotal {
  const QuotationHistoryClientTotal({
    required this.clientKey,
    required this.name,
    required this.total,
  });

  final String clientKey;
  final String name;
  final double total;
}

QuotationHistoryPanelSummary buildQuotationHistoryPanelSummary(
  List<CotizacionModel> items, {
  required String Function(CotizacionModel item) clientKeyFor,
  required bool Function(CotizacionModel item) isOwnClient,
}) {
  final uniqueClients = <String>{};
  final totalsByClient = <String, double>{};
  final namesByClient = <String, String>{};
  var totalAmount = 0.0;
  var totalLines = 0;
  var ownClientsCount = 0;

  for (final item in items) {
    final clientKey = clientKeyFor(item);
    uniqueClients.add(clientKey);
    totalAmount += item.total;
    totalLines += item.items.length;
    if (isOwnClient(item)) ownClientsCount++;
    totalsByClient[clientKey] = (totalsByClient[clientKey] ?? 0) + item.total;
    final name = item.customerName.trim();
    namesByClient[clientKey] = name.isEmpty ? 'Cliente sin nombre' : name;
  }

  final topClients =
      totalsByClient.entries
          .map(
            (entry) => QuotationHistoryClientTotal(
              clientKey: entry.key,
              name: namesByClient[entry.key] ?? 'Cliente sin nombre',
              total: entry.value,
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => b.total.compareTo(a.total));

  return QuotationHistoryPanelSummary(
    visibleCount: items.length,
    uniqueClientsCount: uniqueClients.length,
    totalLines: totalLines,
    totalAmount: totalAmount,
    ownClientsCount: ownClientsCount,
    chartBuckets: buildQuotationHistoryChartBuckets(items),
    topClients: topClients.take(5).toList(growable: false),
  );
}

List<QuotationHistoryChartBucket> buildQuotationHistoryChartBuckets(
  List<CotizacionModel> items,
) {
  if (items.isEmpty) return const [];

  final localDates =
      items
          .map((item) => quotationHistoryLocalDate(item.createdAt))
          .toList(growable: false)
        ..sort();
  final first = localDates.first;
  final last = localDates.last;
  final useDaily = last.difference(first).inDays <= 31;
  final totals = <DateTime, double>{};

  for (final item in items) {
    final local = quotationHistoryLocalDate(item.createdAt);
    final key = useDaily
        ? DateTime(local.year, local.month, local.day)
        : DateTime(local.year, local.month);
    totals[key] = (totals[key] ?? 0) + item.total;
  }

  final keys = totals.keys.toList(growable: false)..sort();
  final recentKeys = keys.length <= 8
      ? keys
      : keys.sublist(keys.length - 8, keys.length);
  final formatter = DateFormat(useDaily ? 'dd/MM' : 'MMM yy', 'es_DO');
  return [
    for (final key in recentKeys)
      QuotationHistoryChartBucket(
        key: key,
        label: formatter.format(key),
        total: totals[key] ?? 0,
      ),
  ];
}
