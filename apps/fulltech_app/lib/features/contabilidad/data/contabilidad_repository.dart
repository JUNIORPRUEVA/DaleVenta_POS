import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_parser/http_parser.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/close_model.dart';
import '../deposit_bank_catalog.dart';
import '../models/close_financial_summary_model.dart';
import '../models/deposit_order_model.dart';
import '../models/fiscal_invoice_model.dart';
import '../models/payable_models.dart';

final contabilidadRepositoryProvider = Provider<ContabilidadRepository>((ref) {
  return ContabilidadRepository(ref.watch(dioProvider));
});

class ContabilidadRepository {
  final Dio _dio;

  ContabilidadRepository(this._dio);

  Future<List<NcfSequenceModel>> listNcfSequences() async {
    try {
      final res = await _dio.get(ApiRoutes.ncfSequences);
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => NcfSequenceModel.fromJson(row.cast<String, dynamic>()))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar las secuencias NCF',
        ),
        e.response?.statusCode,
      );
    }
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
    }
    return fallback;
  }

  String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  String _normalizeObjectUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/public/contabilidad/object?')) {
      final base = _dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
      return '$base$value';
    }
    final base = _dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final encodedKey = Uri.encodeQueryComponent(value.replaceAll('\\', '/'));
    return '$base/public/contabilidad/object?key=$encodedKey';
  }

  Map<String, dynamic> _normalizeCloseJson(Map<String, dynamic> json) {
    final normalized = Map<String, dynamic>.from(json);
    normalized['evidenceUrl'] = _normalizeObjectUrl(
      json['evidenceUrl'] as String?,
    );
    normalized['pdfUrl'] = _normalizeObjectUrl(json['pdfUrl'] as String?);

    final transfersRaw = json['transfers'];
    if (transfersRaw is List) {
      normalized['transfers'] = transfersRaw.map((t) {
        if (t is! Map) return t;
        final transfer = Map<String, dynamic>.from(t.cast<String, dynamic>());
        final vouchersRaw = transfer['vouchers'];
        if (vouchersRaw is List) {
          transfer['vouchers'] = vouchersRaw.map((v) {
            if (v is! Map) return v;
            final voucher = Map<String, dynamic>.from(
              v.cast<String, dynamic>(),
            );
            voucher['fileUrl'] = _normalizeObjectUrl(
              voucher['fileUrl'] as String?,
            );
            return voucher;
          }).toList();
        }
        return transfer;
      }).toList();
    }

    final expenseDetailsRaw = json['expenseDetails'];
    if (expenseDetailsRaw is List) {
      normalized['expenseDetails'] = expenseDetailsRaw.map((row) {
        if (row is! Map) return row;
        final detail = Map<String, dynamic>.from(row.cast<String, dynamic>());
        final vouchersRaw = detail['vouchers'];
        if (vouchersRaw is List) {
          detail['vouchers'] = vouchersRaw.map((v) {
            if (v is! Map) return v;
            final voucher = Map<String, dynamic>.from(
              v.cast<String, dynamic>(),
            );
            voucher['fileUrl'] = _normalizeObjectUrl(
              voucher['fileUrl'] as String?,
            );
            return voucher;
          }).toList();
        }
        return detail;
      }).toList();
    }

    return normalized;
  }

  Future<List<CloseModel>> listCloses({
    required DateTime from,
    required DateTime to,
    CloseType? type,
  }) async {
    try {
      final res = await _dio
          .get(
            ApiRoutes.contabilidadCloses,
            queryParameters: {
              'from': _dateOnly(from),
              'to': _dateOnly(to),
              if (type != null) 'type': type.apiValue,
            },
            options: Options(
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 10),
            ),
          )
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () => throw DioException(
              requestOptions: RequestOptions(
                path: ApiRoutes.contabilidadCloses,
              ),
              error: 'Tiempo agotado al cargar los cierres (>35s)',
              type: DioExceptionType.receiveTimeout,
            ),
          );

      final rows = res.data is List ? (res.data as List) : const [];
      try {
        return rows
            .whereType<Map>()
            .map(
              (row) => CloseModel.fromJson(
                _normalizeCloseJson(row.cast<String, dynamic>()),
              ),
            )
            .toList();
      } catch (e) {
        throw ApiException(
          'Se recibieron cierres con formato inválido. Detalle: $e',
        );
      }
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          e.error?.toString() ?? 'No se pudieron cargar los cierres',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseFinancialSummaryModel> getCloseFinancialSummary({
    required DateTime fromDate,
    required DateTime toDate,
    CloseType? businessType,
    String? companyId,
  }) async {
    try {
      final res = await _dio
          .get(
            ApiRoutes.contabilidadCloseFinancialSummary,
            queryParameters: {
              'fromDate': _dateOnly(fromDate),
              'toDate': _dateOnly(toDate),
              if (businessType != null) 'businessType': businessType.apiValue,
              if ((companyId ?? '').trim().isNotEmpty) 'companyId': companyId,
            },
            options: Options(
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 10),
            ),
          )
          .timeout(
            const Duration(seconds: 35),
            onTimeout: () => throw DioException(
              requestOptions: RequestOptions(
                path: ApiRoutes.contabilidadCloseFinancialSummary,
              ),
              error: 'Tiempo agotado al cargar el resumen financiero (>35s)',
              type: DioExceptionType.receiveTimeout,
            ),
          );

      if (res.data is! Map) {
        throw ApiException(
          'Se recibió un resumen financiero con formato inválido.',
        );
      }

      return CloseFinancialSummaryModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          e.error?.toString() ??
              'No se pudo cargar el resumen financiero de cierres',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> createClose({
    required CloseType type,
    required DateTime date,
    required double cash,
    required double transfer,
    required List<Map<String, dynamic>> transfers,
    String? transferBank,
    required double card,
    double otherIncome = 0,
    required double expenses,
    required double cashDelivered,
    String? notes,
    String? evidenceUrl,
    String? evidenceFileName,
    String? evidenceStorageKey,
    String? evidenceMimeType,
    List<Map<String, dynamic>> expenseDetails = const [],
    String? correctionOfCloseId,
    String? correctionReason,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadCloses,
        data: {
          'type': type.apiValue,
          'date': date.toIso8601String(),
          'cash': cash,
          'transfer': transfer,
          'transfers': transfers,
          if (transfer > 0) 'transferBank': transferBank?.trim(),
          'card': card,
          'otherIncome': otherIncome,
          'expenses': expenses,
          'cashDelivered': cashDelivered,
          if (notes != null) 'notes': notes.trim(),
          if (evidenceUrl != null) 'evidenceUrl': evidenceUrl,
          if (evidenceFileName != null) 'evidenceFileName': evidenceFileName,
          if (evidenceStorageKey != null)
            'evidenceStorageKey': evidenceStorageKey,
          if (evidenceMimeType != null) 'evidenceMimeType': evidenceMimeType,
          if (expenseDetails.isNotEmpty) 'expenseDetails': expenseDetails,
          if ((correctionOfCloseId ?? '').trim().isNotEmpty)
            'correctionOfCloseId': correctionOfCloseId!.trim(),
          if ((correctionReason ?? '').trim().isNotEmpty)
            'correctionReason': correctionReason!.trim(),
        },
      );
      return CloseModel.fromJson(
        _normalizeCloseJson((res.data as Map).cast<String, dynamic>()),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> updateClose({
    required String id,
    required double cash,
    required double transfer,
    required List<Map<String, dynamic>> transfers,
    String? transferBank,
    required double card,
    required double otherIncome,
    required double expenses,
    required double cashDelivered,
    String? notes,
    String? evidenceUrl,
    String? evidenceFileName,
    String? evidenceStorageKey,
    String? evidenceMimeType,
    List<Map<String, dynamic>> expenseDetails = const [],
  }) async {
    try {
      final res = await _dio.put(
        ApiRoutes.contabilidadCloseDetail(id),
        data: {
          'cash': cash,
          'transfer': transfer,
          'transfers': transfers,
          'transferBank': transfer > 0 ? transferBank?.trim() : null,
          'card': card,
          'otherIncome': otherIncome,
          'expenses': expenses,
          'cashDelivered': cashDelivered,
          if (notes != null) 'notes': notes.trim(),
          if (evidenceUrl != null) 'evidenceUrl': evidenceUrl,
          if (evidenceFileName != null) 'evidenceFileName': evidenceFileName,
          if (evidenceStorageKey != null)
            'evidenceStorageKey': evidenceStorageKey,
          if (evidenceMimeType != null) 'evidenceMimeType': evidenceMimeType,
          if (expenseDetails.isNotEmpty) 'expenseDetails': expenseDetails,
        },
      );
      return CloseModel.fromJson(
        _normalizeCloseJson((res.data as Map).cast<String, dynamic>()),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteClose(String id, {required String adminPassword}) async {
    try {
      await _dio.delete(
        ApiRoutes.contabilidadCloseDetail(id),
        data: {'adminPassword': adminPassword},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteClosesBulk({
    required List<String> closeIds,
    required String adminPassword,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.contabilidadCloseDeleteBulk,
        data: {'closeIds': closeIds, 'adminPassword': adminPassword},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron eliminar los cierres seleccionados',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<Uint8List> downloadClosePdfBytes(String rawUrl) async {
    final resolvedUrl = _normalizeObjectUrl(rawUrl);
    if (resolvedUrl.isEmpty) {
      throw ApiException('No hay un PDF disponible para exportar');
    }

    try {
      final response = await _dio.getUri<List<int>>(
        Uri.parse(resolvedUrl),
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        return Uint8List.fromList(data);
      }
      throw ApiException('El PDF se recibio vacio');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo descargar el PDF'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseTransferVoucherModel> uploadPosVoucher(PlatformFile file) async {
    try {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw ApiException('No se pudo leer el voucher seleccionado');
      }
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: file.extension == null
              ? null
              : MediaType.parse(_contentTypeForExtension(file.extension!)),
        ),
      });
      final res = await _dio.post(
        ApiRoutes.contabilidadCloseVoucherUpload,
        data: form,
      );
      return CloseTransferVoucherModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir el voucher POS'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseTransferVoucherModel> uploadCloseVoucher(
    PlatformFile file,
  ) async {
    try {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw ApiException('No se pudo leer el voucher seleccionado');
      }
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: file.name,
          contentType: file.extension == null
              ? null
              : MediaType.parse(_contentTypeForExtension(file.extension!)),
        ),
      });
      final res = await _dio.post(
        ApiRoutes.contabilidadCloseVoucherUpload,
        data: form,
      );
      return CloseTransferVoucherModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir el voucher'),
        e.response?.statusCode,
      );
    }
  }

  String _contentTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  Future<CloseModel> approveClose(String id, {String? reviewNote}) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadCloseApprove(id),
        data: {
          if ((reviewNote ?? '').trim().isNotEmpty)
            'reviewNote': reviewNote!.trim(),
        },
      );
      return CloseModel.fromJson(
        _normalizeCloseJson((res.data as Map).cast<String, dynamic>()),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo aprobar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> rejectClose(String id, {String? reviewNote}) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadCloseReject(id),
        data: {
          if ((reviewNote ?? '').trim().isNotEmpty)
            'reviewNote': reviewNote!.trim(),
        },
      );
      return CloseModel.fromJson(
        _normalizeCloseJson((res.data as Map).cast<String, dynamic>()),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo rechazar el cierre'),
        e.response?.statusCode,
      );
    }
  }

  Future<CloseModel> generateCloseAiReport(String id) async {
    final res = await _dio.post(ApiRoutes.contabilidadCloseAiReport(id));
    return CloseModel.fromJson(
      _normalizeCloseJson((res.data as Map).cast<String, dynamic>()),
    );
  }

  Future<CloseModel> toggleCloseCashDeposit({
    required String id,
    required bool cashDeposited,
  }) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.contabilidadCloseCashDeposit(id),
        data: {'cashDeposited': cashDeposited},
      );
      return CloseModel.fromJson(
        _normalizeCloseJson((res.data as Map).cast<String, dynamic>()),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo actualizar el estado de depósito del cierre',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> createDepositOrder({
    required DateTime windowFrom,
    required DateTime windowTo,
    required String bankName,
    String? bankAccount,
    String? collaboratorName,
    String? note,
    required double reserveAmount,
    required double totalAvailableCash,
    required double depositTotal,
    required Map<String, int> closesCountByType,
    required Map<String, double> depositByType,
    required Map<String, String> accountByType,
    String? correctionOfDepositOrderId,
    String? correctionReason,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadDepositOrders,
        data: {
          'windowFrom': windowFrom.toIso8601String(),
          'windowTo': windowTo.toIso8601String(),
          'bankName': bankName,
          if (bankAccount != null && bankAccount.trim().isNotEmpty)
            'bankAccount': bankAccount.trim(),
          if (collaboratorName != null && collaboratorName.trim().isNotEmpty)
            'collaboratorName': collaboratorName.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          'reserveAmount': reserveAmount,
          'totalAvailableCash': totalAvailableCash,
          'depositTotal': depositTotal,
          'closesCountByType': closesCountByType,
          'depositByType': depositByType,
          'accountByType': accountByType,
          if (correctionOfDepositOrderId != null &&
              correctionOfDepositOrderId.trim().isNotEmpty)
            'correctionOfDepositOrderId': correctionOfDepositOrderId.trim(),
          if (correctionReason != null && correctionReason.trim().isNotEmpty)
            'correctionReason': correctionReason.trim(),
        },
      );
      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo registrar la orden de depósito en nube',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<DepositBankOption>> listDepositBanks() async {
    try {
      final res = await _dio.get(ApiRoutes.contabilidadDepositBanks);
      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => DepositBankOption.fromJson(row.cast<String, dynamic>()))
          .where(
            (bank) => bank.id.trim().isNotEmpty && bank.label.trim().isNotEmpty,
          )
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar los bancos'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> createDepositBank(String name) async {
    try {
      await _dio.post(
        ApiRoutes.contabilidadDepositBanks,
        data: {'name': name.trim()},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el banco'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> updateDepositBank({
    required String id,
    required String name,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.contabilidadDepositBankDetail(id),
        data: {'name': name.trim()},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el banco'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteDepositBank(String id) async {
    try {
      await _dio.delete(ApiRoutes.contabilidadDepositBankDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el banco'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> createDepositBankAccount({
    required String bankId,
    required String label,
    String? accountNumber,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.contabilidadDepositBankAccounts(bankId),
        data: {
          'label': label.trim(),
          if (accountNumber != null && accountNumber.trim().isNotEmpty)
            'accountNumber': accountNumber.trim(),
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear la cuenta'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> updateDepositBankAccount({
    required String bankId,
    required String accountId,
    required String label,
    String? accountNumber,
  }) async {
    try {
      await _dio.patch(
        ApiRoutes.contabilidadDepositBankAccountDetail(bankId, accountId),
        data: {
          'label': label.trim(),
          'accountNumber': accountNumber?.trim() ?? '',
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar la cuenta'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteDepositBankAccount({
    required String bankId,
    required String accountId,
  }) async {
    try {
      await _dio.delete(
        ApiRoutes.contabilidadDepositBankAccountDetail(bankId, accountId),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar la cuenta'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<DepositOrderModel>> listDepositOrders({
    DateTime? from,
    DateTime? to,
    DepositOrderStatus? status,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadDepositOrders,
        queryParameters: {
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          if (status != null) 'status': status.apiValue,
        },
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => DepositOrderModel.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los depósitos',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> getDepositOrder(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.contabilidadDepositOrderDetail(id));
      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> updateDepositOrder({
    required String id,
    DateTime? windowFrom,
    DateTime? windowTo,
    String? bankName,
    String? bankAccount,
    String? collaboratorName,
    String? note,
    double? reserveAmount,
    double? totalAvailableCash,
    double? depositTotal,
    Map<String, int>? closesCountByType,
    Map<String, double>? depositByType,
    Map<String, String>? accountByType,
    DepositOrderStatus? status,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (windowFrom != null) 'windowFrom': windowFrom.toIso8601String(),
        if (windowTo != null) 'windowTo': windowTo.toIso8601String(),
        if (bankName != null) 'bankName': bankName.trim(),
        if (bankAccount != null) 'bankAccount': bankAccount.trim(),
        if (collaboratorName != null)
          'collaboratorName': collaboratorName.trim(),
        if (note != null) 'note': note.trim(),
        if (reserveAmount != null) 'reserveAmount': reserveAmount,
        if (totalAvailableCash != null)
          'totalAvailableCash': totalAvailableCash,
        if (depositTotal != null) 'depositTotal': depositTotal,
        if (closesCountByType != null) 'closesCountByType': closesCountByType,
        if (depositByType != null) 'depositByType': depositByType,
        if (accountByType != null) 'accountByType': accountByType,
        if (status != null) 'status': status.apiValue,
      };
      final res = await _dio.put(
        ApiRoutes.contabilidadDepositOrderDetail(id),
        data: payload,
      );

      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> approveDepositOrder({
    required String id,
    String? reviewNote,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadDepositOrderApprove(id),
        data: {
          if (reviewNote != null && reviewNote.trim().isNotEmpty)
            'reviewNote': reviewNote.trim(),
        },
      );
      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo ejecutar el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> cancelDepositOrder({
    required String id,
    required String reason,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadDepositOrderCancel(id),
        data: {'reviewNote': reason.trim()},
      );
      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo anular el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteDepositOrder(String id) async {
    try {
      await _dio.delete(ApiRoutes.contabilidadDepositOrderDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el depósito'),
        e.response?.statusCode,
      );
    }
  }

  Future<DepositOrderModel> uploadDepositVoucher({
    required String id,
    required PlatformFile file,
  }) async {
    try {
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw ApiException('No se pudo leer el voucher seleccionado');
      }

      final ext = (file.extension ?? '').toLowerCase();
      final mediaType = ext == 'pdf'
          ? MediaType('application', 'pdf')
          : ext == 'png'
          ? MediaType('image', 'png')
          : ext == 'webp'
          ? MediaType('image', 'webp')
          : MediaType('image', 'jpeg');

      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          file.bytes!,
          filename: file.name,
          contentType: mediaType,
        ),
      });

      final res = await _dio.post(
        '${ApiRoutes.contabilidadDepositOrderDetail(id)}/voucher',
        data: form,
      );

      return DepositOrderModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir el voucher'),
        e.response?.statusCode,
      );
    }
  }

  Future<String> uploadFiscalInvoiceImage(PlatformFile file) async {
    try {
      if (file.bytes == null || file.bytes!.isEmpty) {
        throw ApiException('No se pudo leer la imagen seleccionada');
      }

      final ext = (file.extension ?? '').toLowerCase();
      final mediaType = ext == 'pdf'
          ? MediaType('application', 'pdf')
          : ext == 'png'
          ? MediaType('image', 'png')
          : ext == 'webp'
          ? MediaType('image', 'webp')
          : MediaType('image', 'jpeg');

      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          file.bytes!,
          filename: file.name,
          contentType: mediaType,
        ),
      });

      final res = await _dio.post(
        ApiRoutes.contabilidadFiscalInvoicesUpload,
        data: form,
      );

      final url = (res.data is Map ? res.data['url'] : null) as String?;
      if (url == null || url.trim().isEmpty) {
        throw ApiException('La API no devolvió URL de imagen');
      }
      return url.trim();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo subir la imagen de la factura',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<FiscalInvoiceModel> createFiscalInvoice({
    required FiscalInvoiceKind kind,
    required DateTime invoiceDate,
    required String imageUrl,
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadFiscalInvoices,
        data: {
          'kind': kind.apiValue,
          'invoiceDate': invoiceDate.toIso8601String(),
          'imageUrl': imageUrl,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );

      return FiscalInvoiceModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo guardar la factura fiscal',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<FiscalInvoiceModel>> listFiscalInvoices({
    required DateTime from,
    required DateTime to,
    FiscalInvoiceKind? kind,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadFiscalInvoices,
        queryParameters: {
          'from': _dateOnly(from),
          'to': _dateOnly(to),
          if (kind != null) 'kind': kind.apiValue,
        },
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map(
            (row) => FiscalInvoiceModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar las facturas fiscales',
        ),
        e.response?.statusCode,
      );
    }
  }

  // --- Pagos pendientes (Payables) ---

  Future<PayableService> createPayableService({
    required String title,
    required PayableProviderKind providerKind,
    required String providerName,
    String? description,
    required PayableFrequency frequency,
    double? defaultAmount,
    required DateTime nextDueDate,
    bool active = true,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadPayableServices,
        data: {
          'title': title.trim(),
          'providerKind': providerKind.apiValue,
          'providerName': providerName.trim(),
          if (description != null && description.trim().isNotEmpty)
            'description': description.trim(),
          'frequency': frequency.apiValue,
          if (defaultAmount != null) 'defaultAmount': defaultAmount,
          'nextDueDate': nextDueDate.toIso8601String(),
          'active': active,
        },
      );

      return PayableService.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo crear el servicio por pagar',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PayableService>> listPayableServices({bool? active}) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadPayableServices,
        queryParameters: {if (active != null) 'active': active},
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => PayableService.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron cargar los servicios por pagar',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<PayablePayment> registerPayablePayment({
    required String serviceId,
    required double amount,
    DateTime? paidAt,
    String? note,
  }) async {
    try {
      final res = await _dio.post(
        ApiRoutes.contabilidadPayableServicePayments(serviceId),
        data: {
          'amount': amount,
          if (paidAt != null) 'paidAt': paidAt.toIso8601String(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );

      return PayablePayment.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo registrar el pago'),
        e.response?.statusCode,
      );
    }
  }

  Future<PayableService> updatePayableService({
    required String id,
    String? title,
    PayableProviderKind? providerKind,
    String? providerName,
    String? description,
    PayableFrequency? frequency,
    double? defaultAmount,
    DateTime? nextDueDate,
    bool? active,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (title != null) 'title': title.trim(),
        if (providerKind != null) 'providerKind': providerKind.apiValue,
        if (providerName != null) 'providerName': providerName.trim(),
        if (description != null) 'description': description,
        if (frequency != null) 'frequency': frequency.apiValue,
        if (defaultAmount != null) 'defaultAmount': defaultAmount,
        if (nextDueDate != null) 'nextDueDate': nextDueDate.toIso8601String(),
        if (active != null) 'active': active,
      };
      final res = await _dio.put(
        ApiRoutes.contabilidadPayableServiceDetail(id),
        data: payload,
      );

      return PayableService.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo actualizar el servicio por pagar',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<List<PayablePayment>> listPayablePayments({
    DateTime? from,
    DateTime? to,
    String? serviceId,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.contabilidadPayablePayments,
        queryParameters: {
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          if (serviceId != null && serviceId.trim().isNotEmpty)
            'serviceId': serviceId,
        },
      );

      final rows = res.data is List ? (res.data as List) : const [];
      return rows
          .whereType<Map>()
          .map((row) => PayablePayment.fromJson(row.cast<String, dynamic>()))
          .toList();
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo cargar el historial de pagos',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deletePayableService(String id) async {
    try {
      await _dio.delete(ApiRoutes.contabilidadPayableServiceDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el servicio'),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deletePayablePayment(String id) async {
    try {
      await _dio.delete(ApiRoutes.contabilidadPayablePaymentDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el pago'),
        e.response?.statusCode,
      );
    }
  }

  Future<PayablePayment> updatePayablePayment({
    required String id,
    double? amount,
    DateTime? paidAt,
    String? note,
  }) async {
    final payload = <String, dynamic>{
      if (amount != null) 'amount': amount,
      if (paidAt != null) 'paidAt': paidAt.toIso8601String(),
      if (note != null) 'note': note,
    };
    try {
      final res = await _dio.put(
        ApiRoutes.contabilidadPayablePaymentDetail(id),
        data: payload,
      );
      return PayablePayment.fromJson((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el pago'),
        e.response?.statusCode,
      );
    }
  }
}

class NcfSequenceModel {
  const NcfSequenceModel({
    required this.id,
    required this.voucherType,
    required this.prefix,
    required this.startNumber,
    required this.nextNumber,
    required this.endNumber,
    required this.active,
    required this.status,
    this.validUntil,
  });

  factory NcfSequenceModel.fromJson(Map<String, dynamic> json) {
    return NcfSequenceModel(
      id: (json['id'] ?? '').toString(),
      voucherType: (json['voucherType'] ?? json['voucher_type'] ?? '')
          .toString(),
      prefix: (json['prefix'] ?? '').toString(),
      startNumber: _intValue(json['startNumber'] ?? json['start_number'], 1),
      nextNumber: _intValue(json['nextNumber'] ?? json['next_number'], 1),
      endNumber: _intValue(json['endNumber'] ?? json['end_number'], 0),
      validUntil: DateTime.tryParse(
        (json['validUntil'] ?? json['valid_until'] ?? '').toString(),
      ),
      active: json['active'] != false,
      status: (json['status'] ?? '').toString(),
    );
  }

  final String id;
  final String voucherType;
  final String prefix;
  final int startNumber;
  final int nextNumber;
  final int endNumber;
  final DateTime? validUntil;
  final bool active;
  final String status;

  int get remaining {
    final value = endNumber - nextNumber + 1;
    return value < 0 ? 0 : value;
  }

  String get possibleNextNcf =>
      '$prefix${nextNumber.toString().padLeft(8, '0')}';

  static int _intValue(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? fallback;
  }
}
