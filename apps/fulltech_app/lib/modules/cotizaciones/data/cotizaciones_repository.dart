import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/offline/sync_queue_service.dart';
import '../cotizacion_models.dart';
import '../quotation_history_utils.dart';
import 'cotizaciones_local_repository.dart';

final cotizacionesRepositoryProvider = Provider<CotizacionesRepository>((ref) {
  final repository = CotizacionesRepository(
    ref.watch(dioProvider),
    ref.read(cotizacionesLocalRepositoryProvider),
    ref.read(syncQueueServiceProvider.notifier),
    () => ref.read(authStateProvider).user?.companyId,
  );
  repository.registerSyncHandlers();
  return repository;
});

class CotizacionesRepository {
  final Dio _dio;
  final CotizacionesLocalRepository _local;
  final SyncQueueService _syncQueue;
  final String? Function() _companyIdReader;

  static const String _createSyncType = 'quotes.create';
  static const String _updateSyncType = 'quotes.update';
  static const String _deleteSyncType = 'quotes.delete';

  bool _handlersRegistered = false;

  CotizacionesRepository(
    this._dio,
    this._local,
    this._syncQueue, [
    String? Function()? companyIdReader,
  ]) : _companyIdReader = companyIdReader ?? (() => null);

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;

    _syncQueue.registerHandler(_createSyncType, (payload) async {
      final localId = (payload['localId'] ?? '').toString();
      final draft = CotizacionModel.fromMap(
        ((payload['quote'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      );
      final companyId = _companyIdFromPayload(payload, requiredForWrite: true);
      final remote = await create(draft.copyWith(id: ''));
      await _local.deleteById(localId, companyId: companyId);
      await _local.upsert(remote, companyId: companyId);
    });

    _syncQueue.registerHandler(_updateSyncType, (payload) async {
      final id = (payload['id'] ?? '').toString();
      final draft = CotizacionModel.fromMap(
        ((payload['quote'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      );
      final companyId = _companyIdFromPayload(payload, requiredForWrite: true);
      final remote = await update(id, draft);
      await _local.upsert(remote, companyId: companyId);
    });

    _syncQueue.registerHandler(_deleteSyncType, (payload) async {
      final id = (payload['id'] ?? '').toString();
      final companyId = _companyIdFromPayload(payload, requiredForWrite: true);
      await deleteById(id);
      await _local.deleteById(id, companyId: companyId);
    });
  }

  String? _currentCompanyId() {
    final value = _companyIdReader()?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String _requireCompanyId() {
    final value = _currentCompanyId();
    if (value == null) {
      throw ApiException('Empresa activa requerida para cotizaciones locales');
    }
    return value;
  }

  String _companyIdFromPayload(
    Map<String, dynamic> payload, {
    required bool requiredForWrite,
  }) {
    final value = (payload['companyId'] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
    if (!requiredForWrite) return _currentCompanyId() ?? '';
    return _requireCompanyId();
  }

  bool _shouldQueueSync(ApiException error) {
    final code = error.code;
    return code == null || code >= 500;
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    if (data is String && data.trim().isNotEmpty) {
      final text = data.trim();
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final message = decoded['message'];
          if (message is String && message.trim().isNotEmpty) {
            return message;
          }
          if (message is List && message.isNotEmpty) {
            final first = message.first;
            if (first is String && first.trim().isNotEmpty) {
              return first;
            }
          }
          final error = decoded['error'];
          if (error is String && error.trim().isNotEmpty) {
            return error;
          }
        }
      } catch (_) {
        // Fallback to original raw string when it's not JSON.
      }
      return text;
    }
    return fallback;
  }

  String _dateOnly(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<List<CotizacionModel>> list({
    String? customerPhone,
    String? userId,
    DateTime? from,
    DateTime? to,
    int take = 80,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.cotizaciones,
        queryParameters: {
          if (customerPhone != null && customerPhone.trim().isNotEmpty)
            'customerPhone': customerPhone.trim(),
          if (userId != null && userId.trim().isNotEmpty)
            'userId': userId.trim(),
          if (from != null) 'from': _dateOnly(from),
          if (to != null) 'to': _dateOnly(to),
          'take': take,
        },
      );

      final data = res.data;
      if (data is Map && data['items'] is List) {
        final rows = (data['items'] as List).whereType<Map>();
        return rows
            .map((row) => CotizacionModel.fromApi(row.cast<String, dynamic>()))
            .toList();
      }

      if (data is List) {
        final rows = data.whereType<Map>();
        return rows
            .map((row) => CotizacionModel.fromApi(row.cast<String, dynamic>()))
            .toList();
      }

      return const [];
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudieron cargar cotizaciones'),
        e.response?.statusCode,
      );
    }
  }

  Future<List<CotizacionModel>> getCachedList({
    String? customerPhone,
    String? userId,
    DateTime? from,
    DateTime? to,
    int take = 80,
  }) async {
    final companyId = _currentCompanyId();
    if (companyId == null) return const [];
    final items = await _local.listAll(companyId: companyId);
    final phone = (customerPhone ?? '').trim();
    final normalizedUserId = (userId ?? '').trim();
    final filteredByPhone = phone.isEmpty
        ? items
        : items
              .where((item) => (item.customerPhone ?? '').trim() == phone)
              .toList(growable: false);
    final filtered = normalizedUserId.isEmpty
        ? filteredByPhone
        : filteredByPhone
              .where(
                (item) =>
                    (item.createdByUserId ?? '').trim() == normalizedUserId,
              )
              .toList(growable: false);
    final filteredByDate = filtered
        .where((item) {
          final localCreatedAt = quotationHistoryLocalDate(item.createdAt);
          final created = DateTime(
            localCreatedAt.year,
            localCreatedAt.month,
            localCreatedAt.day,
          );
          if (from != null) {
            final start = DateTime(from.year, from.month, from.day);
            if (created.isBefore(start)) return false;
          }
          if (to != null) {
            final end = DateTime(to.year, to.month, to.day);
            if (created.isAfter(end)) return false;
          }
          return true;
        })
        .toList(growable: false);
    return filteredByDate.take(take).toList(growable: false);
  }

  Future<List<CotizacionModel>> listAndCache({
    String? customerPhone,
    String? userId,
    DateTime? from,
    DateTime? to,
    int take = 80,
  }) async {
    final items = await list(
      customerPhone: customerPhone,
      userId: userId,
      from: from,
      to: to,
      take: take,
    );
    final companyId = _requireCompanyId();
    for (final item in items) {
      await _local.upsert(item, companyId: companyId);
    }
    return items;
  }

  Future<CotizacionModel?> getCachedById(String id) async {
    final companyId = _currentCompanyId();
    if (companyId == null) return null;
    final items = await _local.listAll(companyId: companyId);
    for (final item in items) {
      if (item.id.trim() == id.trim()) return item;
    }
    return null;
  }

  Future<CotizacionModel> create(CotizacionModel draft) async {
    try {
      final res = await _dio.post(
        ApiRoutes.cotizaciones,
        data: draft.toCreateDto(),
      );
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<CotizacionModel> getById(String id) async {
    try {
      final res = await _dio.get(ApiRoutes.cotizacionDetail(id));
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<CotizacionModel> getByIdAndCache(String id) async {
    final item = await getById(id);
    await _local.upsert(item, companyId: _requireCompanyId());
    return item;
  }

  Future<CotizacionModel> update(String id, CotizacionModel draft) async {
    try {
      final res = await _dio.patch(
        ApiRoutes.cotizacionDetail(id),
        data: draft.toCreateDto(),
      );
      return CotizacionModel.fromApi((res.data as Map).cast<String, dynamic>());
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo actualizar la cotización',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> purgeAllDebug() async {
    try {
      final res = await _dio.delete(ApiRoutes.cotizacionesDebugPurge);
      await _local.clearAll(companyId: _requireCompanyId());
      return Map<String, dynamic>.from(
        (res.data as Map?) ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron limpiar las cotizaciones',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<void> deleteById(String id) async {
    try {
      await _dio.delete(ApiRoutes.cotizacionDetail(id));
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar la cotización'),
        e.response?.statusCode,
      );
    }
  }

  Future<bool> createOrQueue(CotizacionModel draft) async {
    final localId = draft.id.trim().isEmpty
        ? 'local_quote_${DateTime.now().microsecondsSinceEpoch}'
        : draft.id;
    final companyId = _requireCompanyId();
    final optimistic = draft.copyWith(id: localId);
    await _local.upsert(optimistic, companyId: companyId);
    try {
      final remote = await create(draft);
      await _local.deleteById(localId, companyId: companyId);
      await _local.upsert(remote, companyId: companyId);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) {
        await _local.deleteById(localId, companyId: companyId);
        rethrow;
      }
      await _syncQueue.enqueue(
        id: '$_createSyncType:$localId',
        type: _createSyncType,
        scope: 'quotes',
        payload: {
          'companyId': companyId,
          'localId': localId,
          'quote': optimistic.toMap(),
        },
      );
      return true;
    }
  }

  Future<bool> updateOrQueue(String id, CotizacionModel draft) async {
    final optimistic = draft.copyWith(id: id);
    final companyId = _requireCompanyId();
    await _local.upsert(optimistic, companyId: companyId);
    try {
      final remote = await update(id, draft);
      await _local.upsert(remote, companyId: companyId);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_updateSyncType:$id',
        type: _updateSyncType,
        scope: 'quotes',
        payload: {
          'companyId': companyId,
          'id': id,
          'quote': optimistic.toMap(),
        },
      );
      return true;
    }
  }

  Future<bool> deleteOrQueue(String id) async {
    final companyId = _requireCompanyId();
    await _local.deleteById(id, companyId: companyId);
    try {
      await deleteById(id);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: '$_deleteSyncType:$id',
        type: _deleteSyncType,
        scope: 'quotes',
        payload: {'companyId': companyId, 'id': id},
      );
      return true;
    }
  }

  Future<void> sendWhatsAppQuotation({
    required String quotationId,
    required String destinationType,
    required List<int> pdfBytes,
    String? fileName,
    String? messageText,
  }) async {
    try {
      await _dio.post(
        ApiRoutes.cotizacionSendWhatsapp,
        data: {
          'quotationId': quotationId.trim(),
          'destinationType': destinationType.trim().toLowerCase(),
          'pdfBase64': base64Encode(pdfBytes),
          if (fileName != null && fileName.trim().isNotEmpty)
            'fileName': fileName.trim(),
          if (messageText != null && messageText.trim().isNotEmpty)
            'messageText': messageText.trim(),
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo enviar la cotización por WhatsApp',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<String> createPdfShareLink({
    required String quotationId,
    required List<int> pdfBytes,
    String? fileName,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        ApiRoutes.cotizacionPdfShareLink,
        data: {
          'quotationId': quotationId.trim(),
          'pdfBase64': base64Encode(pdfBytes),
          if (fileName != null && fileName.trim().isNotEmpty)
            'fileName': fileName.trim(),
        },
      );
      final pdfUrl = (response.data?['pdfUrl'] ?? '').toString().trim();
      if (pdfUrl.isEmpty) {
        throw ApiException('No se pudo generar el enlace del PDF');
      }
      return pdfUrl;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo generar el enlace del PDF',
        ),
        e.response?.statusCode,
      );
    }
  }
}
