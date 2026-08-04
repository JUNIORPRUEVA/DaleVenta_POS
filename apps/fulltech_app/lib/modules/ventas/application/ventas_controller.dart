import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../data/ventas_repository.dart';
import '../sales_models.dart';

enum SalesRangePreset { today, week, quincena, custom }

class VentasState {
  final bool loading;
  final String? error;
  final List<SaleModel> sales;
  final SalesSummaryModel summary;
  final SalesRangePreset preset;
  final DateTime from;
  final DateTime to;
  final String? customerIdFilter;

  const VentasState({
    this.loading = false,
    this.error,
    this.sales = const [],
    required this.summary,
    required this.preset,
    required this.from,
    required this.to,
    this.customerIdFilter,
  });

  factory VentasState.initial() {
    final now = DateTime.now();
    final range = _currentQuincena(now);
    return VentasState(
      loading: false,
      summary: SalesSummaryModel.empty(),
      preset: SalesRangePreset.quincena,
      from: range.from,
      to: range.to,
    );
  }

  VentasState copyWith({
    bool? loading,
    String? error,
    List<SaleModel>? sales,
    SalesSummaryModel? summary,
    SalesRangePreset? preset,
    DateTime? from,
    DateTime? to,
    String? customerIdFilter,
    bool clearCustomerIdFilter = false,
    bool clearError = false,
  }) {
    return VentasState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      sales: sales ?? this.sales,
      summary: summary ?? this.summary,
      preset: preset ?? this.preset,
      from: from ?? this.from,
      to: to ?? this.to,
      customerIdFilter: clearCustomerIdFilter
          ? null
          : (customerIdFilter ?? this.customerIdFilter),
    );
  }
}

final ventasControllerProvider =
    StateNotifierProvider<VentasController, VentasState>((ref) {
      return VentasController(ref);
    });

class VentasController extends StateNotifier<VentasState> {
  final Ref ref;

  VentasController(this.ref) : super(VentasState.initial()) {
    load();
  }

  Future<void> load() async {
    final repo = ref.read(ventasRepositoryProvider);
    final cachedResults = await Future.wait([
      repo.cachedSales(
        from: state.from,
        to: state.to,
        customerId: state.customerIdFilter,
        includeDeleted: true,
      ),
      repo.cachedSummary(
        from: state.from,
        to: state.to,
        customerId: state.customerIdFilter,
      ),
    ]);
    final cachedSales = cachedResults[0] as List<SaleModel>;
    final cachedSummary = cachedResults[1] as SalesSummaryModel?;
    final hasCached = cachedSales.isNotEmpty || cachedSummary != null;

    state = state.copyWith(
      loading: !hasCached,
      sales: cachedSales.isNotEmpty ? cachedSales : state.sales,
      summary: cachedSummary ?? state.summary,
      clearError: true,
    );

    try {
      final results = await Future.wait([
        repo.listSales(
          from: state.from,
          to: state.to,
          customerId: state.customerIdFilter,
          includeDeleted: true,
        ),
        repo.summary(
          from: state.from,
          to: state.to,
          customerId: state.customerIdFilter,
        ),
      ]);

      state = state.copyWith(
        loading: false,
        sales: results[0] as List<SaleModel>,
        summary: results[1] as SalesSummaryModel,
      );
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar las ventas';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> refresh() => load();

  Future<void> setCustomerFilter(String? customerId) async {
    final normalized = (customerId ?? '').trim();
    final nextFilter = normalized.isEmpty ? null : normalized;
    if (nextFilter == state.customerIdFilter) {
      return;
    }

    state = state.copyWith(
      customerIdFilter: nextFilter,
      clearCustomerIdFilter: nextFilter == null,
      clearError: true,
    );
    await load();
  }

  Future<void> deleteSale(String id) async {
    final previous = state.sales;
    state = state.copyWith(
      sales: state.sales.where((sale) => sale.id != id).toList(),
    );

    try {
      await ref.read(ventasRepositoryProvider).deleteSale(id);
      await load();
    } catch (_) {
      state = state.copyWith(sales: previous);
      rethrow;
    }
  }

  Future<void> returnSale(String id) async {
    final previous = state.sales;
    try {
      final returned = await ref.read(ventasRepositoryProvider).returnSale(id);
      state = state.copyWith(
        sales: [
          for (final sale in state.sales)
            if (sale.id == id) returned else sale,
        ],
      );
      await load();
    } catch (_) {
      state = state.copyWith(sales: previous);
      rethrow;
    }
  }

  Future<int> purgeAllDebug() async {
    final result = await ref.read(ventasRepositoryProvider).purgeAllDebug();
    state = state.copyWith(
      sales: const [],
      summary: SalesSummaryModel.empty(),
      clearError: true,
    );
    return (result['deletedSales'] as num?)?.toInt() ?? 0;
  }

  Future<void> setPreset(SalesRangePreset preset) async {
    final now = DateTime.now();
    SalesDateRange nextRange;

    switch (preset) {
      case SalesRangePreset.today:
        final day = DateTime(now.year, now.month, now.day);
        nextRange = SalesDateRange(from: day, to: day);
        break;
      case SalesRangePreset.week:
        final day = DateTime(now.year, now.month, now.day);
        final start = day.subtract(Duration(days: day.weekday - 1));
        final end = start.add(const Duration(days: 6));
        nextRange = SalesDateRange(from: start, to: end);
        break;
      case SalesRangePreset.quincena:
        nextRange = _currentQuincena(now);
        break;
      case SalesRangePreset.custom:
        return;
    }

    state = state.copyWith(
      preset: preset,
      from: nextRange.from,
      to: nextRange.to,
    );

    await load();
  }

  Future<void> setCustomRange(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return;

    state = state.copyWith(
      preset: SalesRangePreset.custom,
      from: start,
      to: end,
    );
    await load();
  }
}

SalesDateRange _currentQuincena(DateTime now) {
  DateTime safeDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day > lastDay ? lastDay : day;
    return DateTime(year, month, safeDay);
  }

  if (now.day >= 15 && now.day <= 29) {
    return SalesDateRange(
      from: safeDate(now.year, now.month, 15),
      to: DateTime(now.year, now.month, 29),
    );
  }

  if (now.day >= 30) {
    return SalesDateRange(
      from: safeDate(now.year, now.month, 30),
      to: DateTime(now.year, now.month + 1, 14),
    );
  }

  return SalesDateRange(
    from: safeDate(now.year, now.month - 1, 30),
    to: DateTime(now.year, now.month, 14),
  );
}
