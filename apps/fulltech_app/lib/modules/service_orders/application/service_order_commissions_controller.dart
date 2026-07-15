import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../commissions_models.dart';
import '../data/service_order_commissions_api.dart';

enum ServiceOrderCommissionPeriod { current, previous }

extension ServiceOrderCommissionPeriodX on ServiceOrderCommissionPeriod {
  String get apiValue =>
      this == ServiceOrderCommissionPeriod.previous ? 'previous' : 'current';

  String get label => this == ServiceOrderCommissionPeriod.previous
      ? 'Quincena anterior'
      : 'Esta quincena';
}

class ServiceOrderCommissionsState {
  final bool loading;
  final bool refreshing;
  final bool loadingMore;
  final String? error;
  final ServiceOrderCommissionPeriod selectedPeriod;
  final ServiceOrderCommissionsRange? range;
  final ServiceOrderCommissionsSummary summary;
  final ServiceOrderCommissionsPagination pagination;
  final List<ServiceOrderCommissionItem> items;

  const ServiceOrderCommissionsState({
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.selectedPeriod = ServiceOrderCommissionPeriod.current,
    this.range,
    this.summary = const ServiceOrderCommissionsSummary.empty(),
    this.pagination = const ServiceOrderCommissionsPagination.empty(),
    this.items = const [],
  });

  ServiceOrderCommissionsState copyWith({
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    String? error,
    bool clearError = false,
    ServiceOrderCommissionPeriod? selectedPeriod,
    ServiceOrderCommissionsRange? range,
    ServiceOrderCommissionsSummary? summary,
    ServiceOrderCommissionsPagination? pagination,
    List<ServiceOrderCommissionItem>? items,
  }) {
    return ServiceOrderCommissionsState(
      loading: loading ?? this.loading,
      refreshing: refreshing ?? this.refreshing,
      loadingMore: loadingMore ?? this.loadingMore,
      error: clearError ? null : (error ?? this.error),
      selectedPeriod: selectedPeriod ?? this.selectedPeriod,
      range: range ?? this.range,
      summary: summary ?? this.summary,
      pagination: pagination ?? this.pagination,
      items: items ?? this.items,
    );
  }
}

final serviceOrderCommissionsControllerProvider = StateNotifierProvider
    .autoDispose
    .family<
      ServiceOrderCommissionsController,
      ServiceOrderCommissionsState,
      String?
    >((ref, userId) {
      return ServiceOrderCommissionsController(ref, userId);
    });

class ServiceOrderCommissionsController
    extends StateNotifier<ServiceOrderCommissionsState> {
  ServiceOrderCommissionsController(this.ref, this.userId)
    : super(const ServiceOrderCommissionsState()) {
    ref.listen<AuthState>(authStateProvider, (previous, next) {
      final previousUserId = previous?.user?.id;
      final nextUserId = next.user?.id;

      if (previousUserId == nextUserId) {
        return;
      }

      state = const ServiceOrderCommissionsState();
      if (next.isAuthenticated && nextUserId != null) {
        unawaited(load());
      }
    });

    if (userId == null) {
      return;
    }

    unawaited(load());
  }

  final Ref ref;
  final String? userId;
  Future<void>? _inFlightLoad;

  Future<void> load({
    ServiceOrderCommissionPeriod? period,
    bool refresh = false,
    bool loadMore = false,
  }) async {
    if (userId == null) {
      state = const ServiceOrderCommissionsState();
      return;
    }

    if (_inFlightLoad != null) {
      return _inFlightLoad!;
    }

    final selectedPeriod = period ?? state.selectedPeriod;
    final nextPage = loadMore ? state.pagination.page + 1 : 1;

    state = state.copyWith(
      loading: !refresh && !loadMore && state.items.isEmpty,
      refreshing: refresh,
      loadingMore: loadMore,
      selectedPeriod: selectedPeriod,
      clearError: true,
    );

    _inFlightLoad = () async {
      try {
        final response = await ref
            .read(serviceOrderCommissionsApiProvider)
            .list(
              period: selectedPeriod.apiValue,
              page: nextPage,
              pageSize: state.pagination.pageSize,
            );

        final items = loadMore
            ? [...state.items, ...response.items]
            : response.items;

        state = state.copyWith(
          loading: false,
          refreshing: false,
          loadingMore: false,
          selectedPeriod: selectedPeriod,
          range: response.range,
          summary: response.summary,
          pagination: response.pagination,
          items: items,
        );
      } catch (error) {
        state = state.copyWith(
          loading: false,
          refreshing: false,
          loadingMore: false,
          error: error.toString().replaceFirst('Exception: ', ''),
        );
      } finally {
        _inFlightLoad = null;
      }
    }();

    return _inFlightLoad!;
  }

  Future<void> refresh() => load(refresh: true);

  Future<void> changePeriod(ServiceOrderCommissionPeriod period) {
    if (period == state.selectedPeriod && state.items.isNotEmpty) {
      return Future.value();
    }
    return load(period: period);
  }

  Future<void> loadMore() {
    if (state.loadingMore || !state.pagination.hasMore) {
      return Future.value();
    }
    return load(loadMore: true);
  }
}
