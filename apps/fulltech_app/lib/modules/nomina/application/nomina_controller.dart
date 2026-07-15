import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/nomina_repository.dart';
import '../nomina_models.dart';

class NominaHomeState {
  final bool loading;
  final String? error;
  final List<PayrollPeriod> periods;
  final List<PayrollEmployee> employees;
  final List<PayrollServiceCommissionRequest> pendingServiceCommissionRequests;
  final double? openPeriodTotal;

  const NominaHomeState({
    this.loading = false,
    this.error,
    this.periods = const [],
    this.employees = const [],
    this.pendingServiceCommissionRequests = const [],
    this.openPeriodTotal,
  });

  PayrollPeriod? get openPeriod {
    for (final period in periods) {
      if (period.isOpen) return period;
    }
    return null;
  }

  NominaHomeState copyWith({
    bool? loading,
    String? error,
    List<PayrollPeriod>? periods,
    List<PayrollEmployee>? employees,
    List<PayrollServiceCommissionRequest>? pendingServiceCommissionRequests,
    double? openPeriodTotal,
    bool clearError = false,
    bool clearOpenPeriodTotal = false,
  }) {
    return NominaHomeState(
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      periods: periods ?? this.periods,
      employees: employees ?? this.employees,
      pendingServiceCommissionRequests:
          pendingServiceCommissionRequests ??
          this.pendingServiceCommissionRequests,
      openPeriodTotal: clearOpenPeriodTotal
          ? null
          : (openPeriodTotal ?? this.openPeriodTotal),
    );
  }
}

final nominaHomeControllerProvider =
    StateNotifierProvider<NominaHomeController, NominaHomeState>((ref) {
      return NominaHomeController(ref);
    });

class NominaHomeController extends StateNotifier<NominaHomeState> {
  NominaHomeController(this.ref) : super(const NominaHomeState()) {
    load();
  }

  final Ref ref;

  NominaRepository get _repo => ref.read(nominaRepositoryProvider);

  Future<void> load() async {
    state = state.copyWith(
      loading: true,
      clearError: true,
      clearOpenPeriodTotal: true,
    );
    try {
      await _repo.ensureCurrentOpenPeriod();
      final periods = await _repo.listPeriods();
      final employees = await _repo.listEmployees(activeOnly: false);
      final pendingServiceCommissionRequests = await _repo
          .listPendingServiceCommissionRequests();

      double? openTotal;
      PayrollPeriod? openPeriod;
      for (final period in periods) {
        if (period.isOpen) {
          openPeriod = period;
          break;
        }
      }

      if (openPeriod != null) {
        openTotal = await _repo.computePeriodTotalAllEmployees(openPeriod.id);
      }

      state = state.copyWith(
        loading: false,
        periods: periods,
        employees: employees,
        pendingServiceCommissionRequests: pendingServiceCommissionRequests,
        openPeriodTotal: openTotal,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo cargar nómina: $e',
      );
    }
  }

  Future<PayrollPeriod?> createPeriod({
    required DateTime start,
    required DateTime end,
    required String title,
  }) async {
    if (end.isBefore(start)) {
      throw Exception('La fecha final no puede ser menor que la inicial');
    }

    final overlaps = await _repo.hasOverlappingOpenPeriod(start, end);
    if (overlaps) {
      throw Exception(
        'Ya existe una quincena abierta que se solapa con esas fechas.',
      );
    }

    final period = await _repo.createPeriod(start, end, title);
    await load();
    return period;
  }

  Future<void> closePeriod(String periodId) async {
    final period = await _repo.getPeriodById(periodId);
    if (period == null) {
      throw Exception('Quincena no encontrada');
    }
    await _repo.closePeriod(periodId);
    await _repo.createNextOpenPeriod(period);
    await load();
  }

  Future<void> saveEmployee({
    String? id,
    required String nombre,
    String? telefono,
    String? puesto,
    double cuotaMinima = 0,
    double seguroLeyMonto = 0,
    bool allowSeguroLeyMontoEdit = false,
    double? salarioBase,
    bool activo = true,
  }) async {
    final trimmedName = nombre.trim();
    if (trimmedName.isEmpty) {
      throw Exception('El nombre del empleado es obligatorio');
    }

    if (cuotaMinima < 0) {
      throw Exception('La cuota mínima no puede ser negativa');
    }

    if (seguroLeyMonto < 0) {
      throw Exception('El seguro de ley no puede ser negativo');
    }

    if (salarioBase != null && salarioBase < 0) {
      throw Exception('El salario base no puede ser negativo');
    }

    final existing = id == null ? null : await _repo.getEmployeeById(id);

    final employee = PayrollEmployee(
      id: existing?.id ?? '',
      ownerId: _repo.ownerId,
      nombre: trimmedName,
      telefono: (telefono ?? '').trim().isEmpty ? null : telefono!.trim(),
      puesto: (puesto ?? '').trim().isEmpty ? null : puesto!.trim(),
      salarioBaseQuincenal: salarioBase ?? existing?.salarioBaseQuincenal ?? 0,
      cuotaMinima: cuotaMinima,
      seguroLeyMonto: seguroLeyMonto,
      seguroLeyMontoLocked: !allowSeguroLeyMontoEdit,
      activo: activo,
      createdAt: existing?.createdAt,
      updatedAt: DateTime.now(),
    );

    final savedEmployee = await _repo.upsertEmployee(employee);

    if (salarioBase != null) {
      final open = state.openPeriod;
      if (open == null) {
        throw Exception(
          'Debes crear una quincena abierta para registrar el salario base.',
        );
      }
      await _repo.upsertEmployeeConfig(
        periodId: open.id,
        employeeId: savedEmployee.id,
        baseSalary: salarioBase,
        includeCommissions: true,
      );
    }

    final nextEmployees = [...state.employees];
    final existingIndex = nextEmployees.indexWhere(
      (item) => item.id == savedEmployee.id,
    );
    if (existingIndex >= 0) {
      nextEmployees[existingIndex] = savedEmployee;
    } else {
      nextEmployees.add(savedEmployee);
    }
    nextEmployees.sort((left, right) => left.nombre.compareTo(right.nombre));

    state = state.copyWith(employees: nextEmployees, clearError: true);

    unawaited(load());
  }

  Future<void> deleteEmployee(String employeeId) async {
    final id = employeeId.trim();
    if (id.isEmpty) return;
    await _repo.deleteEmployee(id);
    await load();
  }
}
