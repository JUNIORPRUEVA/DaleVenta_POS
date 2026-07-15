import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import 'nomina_database_helper.dart';
import '../nomina_models.dart';

final nominaRepositoryProvider = Provider<NominaRepository>((ref) {
  return NominaRepository(ref, ref.watch(dioProvider));
});

class NominaRepository {
  NominaRepository(this.ref, this._dio);

  static const String _companyPayrollScope = 'cloud_company_payroll';
  static const Duration _requestTimeout = Duration(seconds: 15);
  static const Duration _localCacheTimeout = Duration(milliseconds: 600);

  final Ref ref;
  final Dio _dio;
  final LocalJsonCache _cache = LocalJsonCache();

  NominaDatabaseHelper get _localDb => NominaDatabaseHelper.instance;

  String get _currentUserId =>
      (ref.read(authStateProvider).user?.id ?? '').trim();

  String get _ownerId => _companyPayrollScope;

  String _myPayrollHistoryCacheKey(String userId) =>
      'nomina:my_payroll_history:$userId';

  Future<List<PayrollPeriod>> listPeriods() async {
    final rows = await _getList(ApiRoutes.payrollPeriods);
    return rows.map(PayrollPeriod.fromMap).toList();
  }

  Future<PayrollPeriod?> getPeriodById(String periodId) async {
    final data = await _getMapOrNull(ApiRoutes.payrollPeriodDetail(periodId));
    if (data == null) return null;
    return PayrollPeriod.fromMap(data);
  }

  Future<bool> hasOverlappingOpenPeriod(DateTime start, DateTime end) async {
    final res = await _getMap(
      ApiRoutes.payrollPeriodOpenOverlap,
      query: {'start': start.toIso8601String(), 'end': end.toIso8601String()},
    );
    return res['overlaps'] == true;
  }

  Future<PayrollPeriod> createPeriod(
    DateTime start,
    DateTime end,
    String title,
  ) async {
    final data = await _postMap(ApiRoutes.payrollPeriods, {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'title': title,
    });
    return PayrollPeriod.fromMap(data);
  }

  Future<PayrollPeriod> ensureCurrentOpenPeriod() async {
    final data = await _postMap(
      ApiRoutes.payrollPeriodEnsureCurrentOpen,
      const {},
    );
    return PayrollPeriod.fromMap(data);
  }

  Future<PayrollPeriod> createNextOpenPeriod(PayrollPeriod closed) async {
    final data = await _postMap(
      ApiRoutes.payrollPeriodNextOpen(closed.id),
      const {},
    );
    return PayrollPeriod.fromMap(data);
  }

  Future<void> closePeriod(String periodId) async {
    await _patch(ApiRoutes.payrollPeriodClose(periodId));
  }

  Future<List<PayrollEmployee>> listEmployees({bool activeOnly = true}) async {
    final rows = await _getList(
      ApiRoutes.payrollEmployees,
      query: {'activeOnly': activeOnly.toString()},
    );
    return rows.map(PayrollEmployee.fromMap).toList();
  }

  Future<PayrollEmployee?> getEmployeeById(String employeeId) async {
    final data = await _getMapOrNull(
      ApiRoutes.payrollEmployeeDetail(employeeId),
    );
    if (data == null) return null;
    return PayrollEmployee.fromMap(data);
  }

  Future<PayrollEmployee> upsertEmployee(PayrollEmployee employee) async {
    final data = await _postMap(ApiRoutes.payrollEmployeeUpsert, {
      if (employee.id.isNotEmpty) 'id': employee.id,
      'nombre': employee.nombre,
      'telefono': employee.telefono,
      'puesto': employee.puesto,
      'salarioBaseQuincenal': employee.salarioBaseQuincenal,
      'cuotaMinima': employee.cuotaMinima,
      'seguroLeyMonto': employee.seguroLeyMonto,
      'allowSeguroLeyMontoEdit': employee.seguroLeyMontoLocked == false,
      'activo': employee.activo,
    });
    return PayrollEmployee.fromMap(data);
  }

  Future<void> deleteEmployee(String employeeId) async {
    try {
      await _dio
          .delete(
            ApiRoutes.payrollEmployeeDetail(employeeId),
            options: _requestOptions(),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException(_timeoutMessage('eliminar el empleado de nómina'));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo eliminar el empleado de nómina'),
        e.response?.statusCode,
      );
    }
  }

  Future<PayrollEmployeeConfig?> getEmployeeConfig(
    String periodId,
    String employeeId,
  ) async {
    final data = await _getMapOrNull(
      ApiRoutes.payrollConfig,
      query: {'periodId': periodId, 'employeeId': employeeId},
    );
    if (data == null) return null;
    return PayrollEmployeeConfig.fromMap(data);
  }

  Future<PayrollEmployeeConfig> upsertEmployeeConfig({
    required String periodId,
    required String employeeId,
    required double baseSalary,
    required bool includeCommissions,
    String? notes,
  }) async {
    final data = await _postMap(ApiRoutes.payrollConfigUpsert, {
      'periodId': periodId,
      'employeeId': employeeId,
      'baseSalary': baseSalary,
      'includeCommissions': includeCommissions,
      'notes': notes,
    });
    return PayrollEmployeeConfig.fromMap(data);
  }

  Future<List<PayrollEntry>> listEntries(
    String periodId,
    String employeeId,
  ) async {
    final rows = await _getList(
      ApiRoutes.payrollEntries,
      query: {'periodId': periodId, 'employeeId': employeeId},
    );
    return rows.map(PayrollEntry.fromMap).toList();
  }

  Future<PayrollEntry> addEntry(PayrollEntry entry) async {
    final data = await _postMap(ApiRoutes.payrollEntries, {
      'periodId': entry.periodId,
      'employeeId': entry.employeeId,
      'date': entry.date.toIso8601String(),
      'type': entry.type.dbValue,
      'concept': entry.concept,
      'amount': entry.amount,
      'cantidad': entry.cantidad,
      'notifyUser': entry.notifyUser,
    });
    return PayrollEntry.fromMap(data);
  }

  Future<void> sendPayrollToWhatsApp({
    required String employeeId,
    required String periodId,
    required Uint8List bytes,
    String? fileName,
    String? messageText,
  }) async {
    try {
      await _dio
          .post(
            ApiRoutes.payrollSendWhatsapp,
            data: {
              'employeeId': employeeId,
              'periodId': periodId,
              'pdfBase64': base64Encode(bytes),
              if ((fileName ?? '').trim().isNotEmpty)
                'fileName': fileName!.trim(),
              if ((messageText ?? '').trim().isNotEmpty)
                'messageText': messageText!.trim(),
            },
            options: _requestOptions(),
          )
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw ApiException(
        'El envio de la nomina por WhatsApp tardo demasiado. Revisa la instancia de la empresa y vuelve a intentar.',
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo enviar la nomina por WhatsApp'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> schedulePayrollToWhatsApp({
    required String employeeId,
    required String periodId,
    required Uint8List bytes,
    required DateTime scheduledFor,
    String? fileName,
    String? messageText,
  }) async {
    try {
      await _dio
          .post(
            ApiRoutes.payrollSendWhatsappSchedule,
            data: {
              'employeeId': employeeId,
              'periodId': periodId,
              'pdfBase64': base64Encode(bytes),
              'scheduledFor': scheduledFor.toUtc().toIso8601String(),
              if ((fileName ?? '').trim().isNotEmpty)
                'fileName': fileName!.trim(),
              if ((messageText ?? '').trim().isNotEmpty)
                'messageText': messageText!.trim(),
            },
            options: _requestOptions(),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(
        'No se pudo programar la nomina porque el servidor tardo demasiado.',
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo programar la nomina por WhatsApp'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PayrollServiceCommissionRequest>>
  listPendingServiceCommissionRequests() async {
    final rows = await _getList(ApiRoutes.payrollPendingServiceCommissions);
    return rows.map(PayrollServiceCommissionRequest.fromMap).toList();
  }

  Future<PayrollServiceCommissionRequest> approveServiceCommissionRequest(
    String requestId,
  ) async {
    final data = await _postMap(
      ApiRoutes.payrollApproveServiceCommission(requestId),
      const {},
    );
    return PayrollServiceCommissionRequest.fromMap(data);
  }

  Future<PayrollServiceCommissionRequest> rejectServiceCommissionRequest(
    String requestId, {
    String? note,
  }) async {
    final data = await _postMap(
      ApiRoutes.payrollRejectServiceCommission(requestId),
      {if ((note ?? '').trim().isNotEmpty) 'note': note!.trim()},
    );
    return PayrollServiceCommissionRequest.fromMap(data);
  }

  Future<void> deleteEntry(String entryId) async {
    await _delete(ApiRoutes.payrollEntryDetail(entryId));
  }

  Future<List<PayrollPaymentRecord>> listPaymentStatuses({
    required String periodId,
    String? employeeId,
  }) async {
    final rows = await _getList(
      ApiRoutes.payrollPaymentStatus,
      query: {
        'periodId': periodId,
        if ((employeeId ?? '').trim().isNotEmpty)
          'employeeId': employeeId!.trim(),
      },
    );
    return rows.map(PayrollPaymentRecord.fromMap).toList();
  }

  Future<PayrollPaymentRecord> markPayrollPaid({
    required String periodId,
    required String employeeId,
  }) async {
    final data = await _postMap(ApiRoutes.payrollPaymentStatusMarkPaid, {
      'periodId': periodId,
      'employeeId': employeeId,
    });
    return PayrollPaymentRecord.fromMap(data);
  }

  Future<PayrollTotals> computeTotals(
    String periodId,
    String employeeId,
  ) async {
    final map = await _getMap(
      ApiRoutes.payrollTotals,
      query: {'periodId': periodId, 'employeeId': employeeId},
    );

    return PayrollTotals(
      baseSalary: _num(map['baseSalary']),
      commissions: _num(map['commissions']),
      serviceCommissions: _num(map['serviceCommissions']),
      salesCommissionAuto: _num(map['salesCommissionAuto']),
      salesAmountThisPeriod: _num(map['salesAmountThisPeriod']),
      salesGoal: _num(map['salesGoal']),
      salesGoalReached: map['salesGoalReached'] == true,
      salesCommissionSource: (map['salesCommissionSource'] ?? 'manual')
          .toString(),
      bonuses: _num(map['bonuses']),
      holidayWorked: _num(map['holidayWorked']),
      otherAdditions: _num(map['otherAdditions']),
      absences: _num(map['absences']),
      late: _num(map['late']),
      advances: _num(map['advances']),
      otherDeductions: _num(map['otherDeductions']),
      seguroLey: _num(map['seguroLey']),
      additions: _num(map['additions']),
      deductions: _num(map['deductions']),
      total: _num(map['total']),
    );
  }

  Future<double> computePeriodTotalAllEmployees(String periodId) async {
    final map = await _getMap(ApiRoutes.payrollPeriodTotalAll(periodId));
    return _num(map['total']);
  }

  Future<List<PayrollHistoryItem>> listMyPayrollHistory({
    DateTime? from,
    DateTime? to,
    String? status,
    String? periodId,
    String? period,
  }) async {
    if (_currentUserId.isEmpty) return const [];
    try {
      final normalizedStatus = (status ?? '').trim().toUpperCase();
      final rows = await _getList(
        ApiRoutes.payrollMyHistory,
        query: {
          if (from != null) 'from': from.toIso8601String(),
          if (to != null) 'to': to.toIso8601String(),
          if (normalizedStatus.isNotEmpty) 'status': normalizedStatus,
          if ((periodId ?? '').trim().isNotEmpty) 'periodId': periodId!.trim(),
          if ((period ?? '').trim().isNotEmpty) 'period': period!.trim(),
        },
      );
      return rows.map(PayrollHistoryItem.fromMap).toList();
    } on FormatException {
      throw ApiException(_invalidResponseMessage('consultar Mis Pagos'));
    } on TypeError {
      throw ApiException(_invalidResponseMessage('consultar Mis Pagos'));
    }
  }

  Future<List<PayrollHistoryItem>> getCachedMyPayrollHistory() async {
    if (_currentUserId.isEmpty) return const [];

    if (kIsWeb) {
      final cached = await _cache.readMap(
        _myPayrollHistoryCacheKey(_currentUserId),
      );
      final items = cached?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((row) => PayrollHistoryItem.fromMap(row.cast<String, dynamic>()))
          .toList(growable: false);
    }

    try {
      return await _localDb
          .listCachedPayrollHistoryForUser(_currentUserId)
          .timeout(_localCacheTimeout);
    } catch (_) {
      final cached = await _cache.readMap(
        _myPayrollHistoryCacheKey(_currentUserId),
      );
      final items = cached?['items'];
      if (items is! List) return const [];
      return items
          .whereType<Map>()
          .map((row) => PayrollHistoryItem.fromMap(row.cast<String, dynamic>()))
          .toList(growable: false);
    }
  }

  Future<List<PayrollHistoryItem>> listMyPayrollHistoryAndCache() async {
    final rows = await listMyPayrollHistory();
    if (_currentUserId.isNotEmpty) {
      final payload = {
        'items': rows.map((item) => item.toMap()).toList(growable: false),
      };
      await _cache.writeMap(_myPayrollHistoryCacheKey(_currentUserId), payload);
      if (!kIsWeb) {
        unawaited(
          _localDb.replaceCachedPayrollHistoryForUser(_currentUserId, rows),
        );
      }
    }
    return rows;
  }

  Future<double> getCuotaMinimaForUser() async {
    try {
      final map = await _getMap(ApiRoutes.payrollMyGoal);
      return _num(map['cuota_minima']);
    } on ApiException catch (e) {
      if (e.code == 404) {
        return 0;
      }
      rethrow;
    }
  }

  String get ownerId => _ownerId;

  Future<Map<String, dynamic>> _getMap(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio
          .get(path, queryParameters: query, options: _requestOptions())
          .timeout(_requestTimeout);
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del servidor');
    } on FormatException {
      throw ApiException(_invalidResponseMessage('consultar nómina'));
    } on TypeError {
      throw ApiException(_invalidResponseMessage('consultar nómina'));
    } on TimeoutException {
      throw ApiException(_timeoutMessage('consultar nómina'));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'Error consultando nómina'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>?> _getMapOrNull(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio
          .get(path, queryParameters: query, options: _requestOptions())
          .timeout(_requestTimeout);
      if (res.data == null) return null;
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      return null;
    } on FormatException {
      throw ApiException(_invalidResponseMessage('consultar nómina'));
    } on TypeError {
      throw ApiException(_invalidResponseMessage('consultar nómina'));
    } on TimeoutException {
      throw ApiException(_timeoutMessage('consultar nómina'));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      throw ApiException(
        _extractMessage(e, 'Error consultando nómina'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _getList(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    try {
      final res = await _dio
          .get(path, queryParameters: query, options: _requestOptions())
          .timeout(_requestTimeout);
      final data = res.data;
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
    } on FormatException {
      throw ApiException(_invalidResponseMessage('consultar nómina'));
    } on TypeError {
      throw ApiException(_invalidResponseMessage('consultar nómina'));
    } on TimeoutException {
      throw ApiException(_timeoutMessage('consultar nómina'));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'Error consultando nómina'),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> _postMap(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await _dio
          .post(path, data: body, options: _requestOptions())
          .timeout(_requestTimeout);
      if (res.data is Map<String, dynamic>) {
        return res.data as Map<String, dynamic>;
      }
      if (res.data is Map) {
        return (res.data as Map).cast<String, dynamic>();
      }
      throw ApiException('Respuesta inválida del servidor');
    } on FormatException {
      throw ApiException(_invalidResponseMessage('guardar cambios de nómina'));
    } on TypeError {
      throw ApiException(_invalidResponseMessage('guardar cambios de nómina'));
    } on TimeoutException {
      throw ApiException(_timeoutMessage('guardar cambios de nómina'));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo guardar nómina'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> _patch(String path) async {
    try {
      await _dio
          .patch(path, options: _requestOptions())
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException(_timeoutMessage('actualizar nómina'));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo actualizar nómina'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> _delete(String path) async {
    try {
      await _dio
          .delete(path, options: _requestOptions())
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException(_timeoutMessage('eliminar el movimiento'));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e, 'No se pudo eliminar movimiento'),
        e.response?.statusCode,
      );
    }
  }

  String _extractMessage(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
    }
    return fallback;
  }

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  Options _requestOptions({Map<String, dynamic>? extra}) {
    return Options(extra: {'skipLoader': true, ...?extra});
  }

  String _timeoutMessage(String action) {
    return 'La operación de nómina tardó demasiado al $action. Inténtalo de nuevo.';
  }

  String _invalidResponseMessage(String action) {
    return 'El servidor devolvió una respuesta inválida al $action. Revisa el endpoint de nómina o inténtalo de nuevo más tarde.';
  }
}
