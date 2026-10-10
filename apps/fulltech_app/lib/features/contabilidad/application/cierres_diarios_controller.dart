import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/models/close_model.dart';
import '../data/contabilidad_repository.dart';

enum CierresRangePreset { today, quincena, custom }

class CierresDateRange {
  final DateTime from;
  final DateTime to;

  const CierresDateRange({required this.from, required this.to});
}

class CierresDiariosState {
  final bool loading;
  final bool loadingMore;
  final bool saving;
  final String? deletingId;
  final String? error;
  final List<CloseModel> closes;
  final bool hasMore;
  final int nextPage;
  final DateTime from;
  final DateTime to;
  final CierresRangePreset preset;
  final CloseType? typeFilter;
  final CloseModel? editingClose;

  const CierresDiariosState({
    this.loading = false,
    this.loadingMore = false,
    this.saving = false,
    this.deletingId,
    this.error,
    this.closes = const [],
    this.hasMore = false,
    this.nextPage = 2,
    required this.from,
    required this.to,
    required this.preset,
    this.typeFilter,
    this.editingClose,
  });

  factory CierresDiariosState.initial() {
    final now = DateTime.now();
    final range = _currentQuincena(now);
    return CierresDiariosState(
      from: range.from,
      to: range.to,
      preset: CierresRangePreset.quincena,
      typeFilter: CloseType.tienda,
    );
  }

  CierresDiariosState copyWith({
    bool? loading,
    bool? loadingMore,
    bool? saving,
    String? deletingId,
    String? error,
    List<CloseModel>? closes,
    bool? hasMore,
    int? nextPage,
    DateTime? from,
    DateTime? to,
    CierresRangePreset? preset,
    CloseType? typeFilter,
    CloseModel? editingClose,
    bool clearError = false,
    bool clearDeleting = false,
    bool clearTypeFilter = false,
    bool clearEditing = false,
  }) {
    return CierresDiariosState(
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      saving: saving ?? this.saving,
      deletingId: clearDeleting ? null : (deletingId ?? this.deletingId),
      error: clearError ? null : (error ?? this.error),
      closes: closes ?? this.closes,
      hasMore: hasMore ?? this.hasMore,
      nextPage: nextPage ?? this.nextPage,
      from: from ?? this.from,
      to: to ?? this.to,
      preset: preset ?? this.preset,
      typeFilter: clearTypeFilter ? null : (typeFilter ?? this.typeFilter),
      editingClose: clearEditing ? null : (editingClose ?? this.editingClose),
    );
  }
}

final cierresDiariosControllerProvider =
    StateNotifierProvider<CierresDiariosController, CierresDiariosState>((ref) {
      return CierresDiariosController(ref);
    });

class CierresDiariosController extends StateNotifier<CierresDiariosState> {
  final Ref ref;
  static const _pageLimit = 50;

  CierresDiariosController(this.ref) : super(CierresDiariosState.initial()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final rows = await ref
          .read(contabilidadRepositoryProvider)
          .listClosesPage(
            from: state.from,
            to: state.to,
            type: null,
            page: 1,
            limit: _pageLimit,
          );

      state = state.copyWith(
        loading: false,
        closes: rows.items,
        hasMore: rows.hasMore,
        nextPage: rows.nextPage ?? 2,
      );
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar los cierres';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<void> refresh() => load();

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final rows = await ref
          .read(contabilidadRepositoryProvider)
          .listClosesPage(
            from: state.from,
            to: state.to,
            type: null,
            page: state.nextPage,
            limit: _pageLimit,
          );

      final existingIds = state.closes.map((item) => item.id).toSet();
      final merged = [
        ...state.closes,
        ...rows.items.where((item) => !existingIds.contains(item.id)),
      ];
      state = state.copyWith(
        loadingMore: false,
        closes: merged,
        hasMore: rows.hasMore,
        nextPage: rows.nextPage ?? (state.nextPage + 1),
      );
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron cargar más cierres';
      state = state.copyWith(loadingMore: false, error: message);
    }
  }

  Future<void> setTypeFilter(CloseType type) async {
    state = state.copyWith(typeFilter: type, clearError: true);
  }

  Future<void> setPreset(CierresRangePreset preset) async {
    final now = DateTime.now();
    CierresDateRange range;

    switch (preset) {
      case CierresRangePreset.today:
        final day = DateTime(now.year, now.month, now.day);
        range = CierresDateRange(from: day, to: day);
        break;
      case CierresRangePreset.quincena:
        range = _currentQuincena(now);
        break;
      case CierresRangePreset.custom:
        return;
    }

    state = state.copyWith(preset: preset, from: range.from, to: range.to);
    await load();
  }

  Future<void> setCustomRange(DateTime from, DateTime to) async {
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    if (end.isBefore(start)) return;

    state = state.copyWith(
      from: start,
      to: end,
      preset: CierresRangePreset.custom,
    );
    await load();
  }

  Future<void> loadAdminHistory() async {
    final now = DateTime.now();
    await setCustomRange(
      DateTime(now.year - 2, 1, 1),
      DateTime(now.year, now.month, now.day + 1),
    );
  }

  void startEditing(CloseModel close) {
    state = state.copyWith(editingClose: close, clearError: true);
  }

  void cancelEditing() {
    state = state.copyWith(clearEditing: true, clearError: true);
  }

  void _replaceClose(CloseModel updated) {
    final index = state.closes.indexWhere((item) => item.id == updated.id);
    if (index < 0) {
      state = state.copyWith(closes: [updated, ...state.closes]);
      return;
    }
    final next = [...state.closes];
    next[index] = updated;
    state = state.copyWith(closes: next);
  }

  Future<void> saveClose({
    required CloseType type,
    required DateTime date,
    required double cash,
    required double transfer,
    required List<Map<String, dynamic>> transfers,
    String? transferBank,
    required double card,
    required double otherIncome,
    required double expenses,
    required double cashDelivered,
    String? notes,
    CloseTransferVoucherModel? posVoucher,
    List<Map<String, dynamic>> expenseDetails = const [],
    String? correctionOfCloseId,
    String? correctionReason,
  }) async {
    state = state.copyWith(saving: true, clearError: true);

    try {
      final editing = state.editingClose;
      if (editing == null) {
        final isCorrection = (correctionOfCloseId ?? '').trim().isNotEmpty;
        if (!isCorrection) {
          final day = DateTime(date.year, date.month, date.day);
          final sameDayRows = await ref
              .read(contabilidadRepositoryProvider)
              .listCloses(from: day, to: day, type: type);
          final alreadyExists = sameDayRows.any((row) => !row.isRejected);
          if (alreadyExists) {
            state = state.copyWith(
              saving: false,
              error:
                  'Ya existe un cierre activo para esta categoria en esa fecha. Selecciona otra fecha o categoria.',
            );
            return;
          }
        }

        await ref
            .read(contabilidadRepositoryProvider)
            .createClose(
              type: type,
              date: date,
              cash: cash,
              transfer: transfer,
              transfers: transfers,
              transferBank: transferBank,
              card: card,
              otherIncome: otherIncome,
              expenses: expenses,
              cashDelivered: cashDelivered,
              notes: notes,
              evidenceUrl: posVoucher?.fileUrl,
              evidenceFileName: posVoucher?.fileName,
              evidenceStorageKey: posVoucher?.storageKey,
              evidenceMimeType: posVoucher?.mimeType,
              expenseDetails: expenseDetails,
              correctionOfCloseId: correctionOfCloseId,
              correctionReason: correctionReason,
            );
      } else {
        if (!editing.isPending) {
          state = state.copyWith(
            saving: false,
            error: 'Este cierre ya fue revisado y no se puede editar.',
          );
          return;
        }
        await ref
            .read(contabilidadRepositoryProvider)
            .updateClose(
              id: editing.id,
              cash: cash,
              transfer: transfer,
              transfers: transfers,
              transferBank: transferBank,
              card: card,
              otherIncome: otherIncome,
              expenses: expenses,
              cashDelivered: cashDelivered,
              notes: notes,
              evidenceUrl: posVoucher?.fileUrl,
              evidenceFileName: posVoucher?.fileName,
              evidenceStorageKey: posVoucher?.storageKey,
              evidenceMimeType: posVoucher?.mimeType,
              expenseDetails: expenseDetails,
            );
      }

      state = state.copyWith(saving: false, clearEditing: true);
      await load();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo guardar el cierre';
      state = state.copyWith(saving: false, error: message);
    }
  }

  Future<void> deleteClose(String id, {required String adminPassword}) async {
    state = state.copyWith(deletingId: id, clearError: true);
    try {
      await ref
          .read(contabilidadRepositoryProvider)
          .deleteClose(id, adminPassword: adminPassword);
      state = state.copyWith(clearDeleting: true);
      await load();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo eliminar el cierre';
      state = state.copyWith(error: message, clearDeleting: true);
    }
  }

  Future<void> deleteClosesBulk({
    required List<String> ids,
    required String adminPassword,
  }) async {
    state = state.copyWith(clearError: true);
    try {
      await ref
          .read(contabilidadRepositoryProvider)
          .deleteClosesBulk(closeIds: ids, adminPassword: adminPassword);
      await load();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudieron eliminar los cierres';
      state = state.copyWith(error: message);
    }
  }

  Future<void> approveClose(String id, {String? reviewNote}) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final updated = await ref
          .read(contabilidadRepositoryProvider)
          .approveClose(id, reviewNote: reviewNote);
      state = state.copyWith(saving: false);
      _replaceClose(updated);
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo aprobar el cierre';
      state = state.copyWith(saving: false, error: message);
    }
  }

  Future<void> rejectClose(String id, {String? reviewNote}) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final updated = await ref
          .read(contabilidadRepositoryProvider)
          .rejectClose(id, reviewNote: reviewNote);
      state = state.copyWith(saving: false);
      _replaceClose(updated);
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo rechazar el cierre';
      state = state.copyWith(saving: false, error: message);
    }
  }

  Future<void> generateAiReport(String id) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      await ref.read(contabilidadRepositoryProvider).generateCloseAiReport(id);
      state = state.copyWith(saving: false);
      await load();
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo generar el informe IA';
      state = state.copyWith(saving: false, error: message);
    }
  }

  Future<void> toggleCloseCashDeposited({
    required String id,
    required bool cashDeposited,
  }) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final updated = await ref
          .read(contabilidadRepositoryProvider)
          .toggleCloseCashDeposit(id: id, cashDeposited: cashDeposited);
      _replaceClose(updated);
      state = state.copyWith(saving: false);
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo actualizar el estado de depósito';
      state = state.copyWith(saving: false, error: message);
      throw ApiException(message);
    }
  }
}

CierresDateRange _currentQuincena(DateTime now) {
  DateTime safeDate(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = day > lastDay ? lastDay : day;
    return DateTime(year, month, safeDay);
  }

  if (now.day >= 15 && now.day <= 29) {
    return CierresDateRange(
      from: safeDate(now.year, now.month, 15),
      to: DateTime(now.year, now.month, 29),
    );
  }

  if (now.day >= 30) {
    return CierresDateRange(
      from: safeDate(now.year, now.month, 30),
      to: DateTime(now.year, now.month + 1, 14),
    );
  }

  return CierresDateRange(
    from: safeDate(now.year, now.month - 1, 30),
    to: DateTime(now.year, now.month, 14),
  );
}
