import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_provider.dart';
import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';

// ── Admin list state ──────────────────────────────────────────────────────────

class WarningsListState {
  final bool loading;
  final String? error;
  final List<EmployeeWarning> items;
  final int total;
  final int page;
  final int limit;
  final String? filterStatus;
  final String? filterWarningType;
  final String search;

  const WarningsListState({
    this.loading = false,
    this.error,
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.limit = 20,
    this.filterStatus,
    this.filterWarningType,
    this.search = '',
  });

  WarningsListState copyWith({
    bool? loading,
    String? error,
    List<EmployeeWarning>? items,
    int? total,
    int? page,
    int? limit,
    Object? filterStatus = _sentinel,
    Object? filterWarningType = _sentinel,
    String? search,
  }) {
    return WarningsListState(
      loading: loading ?? this.loading,
      error: error,
      items: items ?? this.items,
      total: total ?? this.total,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      filterStatus: filterStatus == _sentinel
          ? this.filterStatus
          : filterStatus as String?,
      filterWarningType: filterWarningType == _sentinel
          ? this.filterWarningType
          : filterWarningType as String?,
      search: search ?? this.search,
    );
  }
}

const _sentinel = Object();

class WarningsListController extends StateNotifier<WarningsListState> {
  final EmployeeWarningsRepository _repo;

  WarningsListController(this._repo) : super(const WarningsListState()) {
    load();
  }

  Future<void> load({bool reset = false}) async {
    final nextPage = reset ? 1 : state.page;
    state = state.copyWith(loading: true, error: null, page: nextPage);
    try {
      final page = await _repo.listAll(
        status: state.filterStatus,
        warningType: state.filterWarningType,
        search: state.search.isEmpty ? null : state.search,
        page: nextPage,
        limit: state.limit,
      );
      state = state.copyWith(
        loading: false,
        items: page.items,
        total: page.total,
        page: page.page,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  void setSearch(String v) {
    state = state.copyWith(search: v, page: 1);
    load(reset: true);
  }

  void setFilterStatus(String? v) {
    state = state.copyWith(filterStatus: v, page: 1);
    load(reset: true);
  }

  void setFilterWarningType(String? v) {
    state = state.copyWith(filterWarningType: v, page: 1);
    load(reset: true);
  }

  Future<void> deleteWarning(String id) async {
    await _repo.delete(id);
    await load(reset: true);
  }
}

final warningsListControllerProvider =
    StateNotifierProvider<WarningsListController, WarningsListState>((ref) {
      return WarningsListController(
        ref.watch(employeeWarningsRepositoryProvider),
      );
    });

// ── Warning detail (Admin only) ───────────────────────────────────────────────
// Nota: Solo Admin puede acceder a detalles. Los empleados no tienen acceso.

final warningDetailProvider = FutureProvider.family<EmployeeWarning, String>((
  ref,
  id,
) async {
  return ref.watch(employeeWarningsRepositoryProvider).getOne(id);
});

// ── Employee pending ──────────────────────────────────────────────────────────
// Flujo de firma desactivado: badge de pendientes no se usa.

final myPendingWarningsProvider = FutureProvider<List<EmployeeWarning>>((
  ref,
) async {
  return const <EmployeeWarning>[];
});

final myPendingWarningsCountProvider = Provider<int>((ref) {
  return ref
      .watch(myPendingWarningsProvider)
      .maybeWhen(data: (list) => list.length, orElse: () => 0);
});

// ── Verificar si usuario es Admin ─────────────────────────────────────────────

final isUserAdminProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.user?.role == 'ADMIN';
});

// ── Guard: Solo Admin puede ver el módulo de amonestaciones ──────────────────

final canAccessAmonestacionesProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.user?.role == 'ADMIN';
});
