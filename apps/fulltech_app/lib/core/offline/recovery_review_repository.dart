import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import '../auth/operation_scope.dart';
import '../auth/token_storage.dart';
import '../errors/api_exception.dart';
import 'offline_store.dart';
import 'pending_sync_action.dart';
import 'sync_queue_service.dart';
import '../../modules/cash/cash_repository.dart';
import '../../modules/cash/cash_providers.dart';

final recoveryReviewRepositoryProvider = Provider<RecoveryReviewRepository>(
  (ref) => RecoveryReviewRepository(
    ref.watch(dioProvider),
    OfflineStore.instance,
    tokenStorage: ref.watch(tokenStorageProvider),
    onChanged: ref.read(syncQueueServiceProvider.notifier).refreshStats,
    onResolved: (action, confirmed) async {
      if (action.type.startsWith('cash.')) {
        await ref
            .read(cashRepositoryProvider)
            .applyReviewedOperation(action, financiallyConfirmed: confirmed);
        ref.invalidate(activeCashSessionControllerProvider);
      }
    },
  ),
);

/// Administrative requests never replay the original financial operation.
/// Failed requests leave the original durable incident available to resubmit.
class RecoveryReviewRepository {
  RecoveryReviewRepository(
    this._dio,
    this._store, {
    TokenStorage? tokenStorage,
    Future<void> Function()? onChanged,
    Future<void> Function(PendingSyncAction action, bool confirmed)? onResolved,
  }) : _tokenStorage = tokenStorage,
       _onChanged = onChanged,
       _onResolved = onResolved;
  final Dio _dio;
  final OfflineStore _store;
  final TokenStorage? _tokenStorage;
  final Future<void> Function()? _onChanged;
  final Future<void> Function(PendingSyncAction action, bool confirmed)?
  _onResolved;
  static const types = {
    'sales.attempt',
    'sales.create',
    'cash.open',
    'cash.close',
    'cash.movement',
  };
  static const fields = {
    'clientRequestId',
    'operationId',
    'clientSessionId',
    'sessionId',
    'originCashSessionId',
    'expectedTotalSold',
    'openingAmount',
    'closingAmount',
    'amount',
    'type',
    'movementType',
    'paymentMethod',
    'saleOccurredAt',
    'occurredAt',
    'createdAt',
    'openedAt',
  };

  Future<T> _owned<T>(Future<T> Function(OperationScope owner) work) async {
    final user = await (_tokenStorage ?? TokenStorage()).getUserSnapshot();
    if (user == null || (user.companyId ?? '').isEmpty || user.id.isEmpty) {
      throw ApiException('Vuelve a iniciar sesión para revisar incidencias.');
    }
    final owner = OperationScope(user.companyId!, user.id);
    return owner.run(() => work(owner));
  }

  static Map<String, dynamic> requestFor(PendingSyncAction action) {
    if (!types.contains(action.type) ||
        action.isAutomaticallyRetryable ||
        action.status == 'syncing') {
      throw ApiException(
        'Espera a que termine el envío antes de solicitar revisión.',
      );
    }
    final summary = <String, dynamic>{
      for (final entry in action.payload.entries)
        if (fields.contains(entry.key) &&
            (entry.value is String ||
                entry.value is num ||
                entry.value is bool))
          entry.key: entry.value,
    };
    final actionType = action.type == 'sales.attempt' ? 'sales.create' : action.type;
    if (action.type == 'sales.attempt') {
      summary['clientRequestId'] ??= action.idempotencyKey ?? action.entityId;
      if (summary['clientRequestId'] == null) {
        throw ApiException('No se pudo identificar el cobro original.');
      }
    }
    final operation = switch (actionType) {
      'sales.create' => summary['clientRequestId'],
      'cash.movement' => summary['operationId'],
      'cash.open' => summary['clientSessionId'],
      _ => summary['sessionId'],
    };
    final operationId = (operation ?? action.idempotencyKey ?? action.id)
        .toString();
    final amount = switch (actionType) {
      'sales.create' => summary['expectedTotalSold'],
      'cash.open' => summary['openingAmount'],
      'cash.close' => summary['closingAmount'],
      _ => summary['amount'],
    };
    final parsed = amount is num
        ? amount.toDouble()
        : double.tryParse('$amount');
    final session =
        summary['sessionId'] ??
        summary['originCashSessionId'] ??
        summary['clientSessionId'];
    return {
      'sourceActionId': action.id,
      'actionType': actionType,
      'operationId': operationId,
      if (session != null) 'originalSessionId': session,
      if (parsed != null && parsed.isFinite && parsed >= 0)
        'expectedAmount': parsed,
      'payloadSummary': summary,
    };
  }

  Future<void> submit(PendingSyncAction action) => _owned((owner) async {
    if (action.companyId != owner.companyId || action.userId != owner.userId) {
      throw ApiException('La incidencia pertenece a otra sesión.');
    }
    final body = requestFor(action);
    final result = await _dio.post('/recovery/reviews', data: body);
    await _attach(owner, result.data);
  });

  /// One user action: preserve an idempotent administrative snapshot, then
  /// check the original record. Never resubmits the financial operation.
  Future<Map<String, dynamic>> prepare(PendingSyncAction action) =>
      _owned((owner) async {
        final user = await (_tokenStorage ?? TokenStorage()).getUserSnapshot();
        if (user?.role != 'ADMIN' || action.companyId != owner.companyId ||
            action.userId != owner.userId) {
          throw ApiException('Solo el administrador de esta cuenta puede comprobar la operación.');
        }
        final response = await _dio.post('/recovery/reviews', data: requestFor(action));
        await _attach(owner, response.data);
        return Map<String, dynamic>.from(response.data as Map);
      });

  Future<void> check(PendingSyncAction action) async {
    final row = await prepare(action);
    await verify(row['id'] as String);
  }

  Future<void> resolveNotPerformed(PendingSyncAction action, String note) async {
    final row = await prepare(action);
    if (row['status'] != 'RESOLVED_NOT_PERFORMED') {
      await decide(row, 'NOT_PERFORMED', note);
    }
    final saved = await _store.listPendingActions(
      companyId: action.companyId, userId: action.userId, limit: null,
    );
    if (!saved.any((a) => a.id == action.id && a.status == 'review_resolved' &&
        a.payload['recoveryReviewStatus'] == 'RESOLVED_NOT_PERFORMED')) {
      throw ApiException('La decisión no está confirmada. La incidencia sigue guardada.');
    }
  }

  Future<List<Map<String, dynamic>>> list() => _owned((owner) async {
    final rows = <Map<String, dynamic>>[];
    final cursors = <String>{};
    String? cursor;
    do {
      final response = await _dio.get(
        '/recovery/reviews',
        queryParameters: {if (cursor != null) 'cursor': cursor},
      );
      if (response.data is! Map || response.data['items'] is! List) {
        throw ApiException('No pudimos comprobar las revisiones del servidor.');
      }
      for (final item in response.data['items'] as List) {
        if (item is! Map || item['companyId'] != owner.companyId) {
          throw ApiException(
            'La respuesta de revisión no coincide con tu empresa.',
          );
        }
        final row = Map<String, dynamic>.from(item);
        rows.add(row);
        if (row['sourceUserId'] == owner.userId) await _attach(owner, row);
      }
      cursor = response.data['nextCursor'] as String?;
      if (cursor != null && !cursors.add(cursor)) {
        throw ApiException('No pudimos completar la consulta de revisiones.');
      }
    } while (cursor != null);
    return rows;
  });

  Future<void> verify(String id) => _owned((owner) async {
    final response = await _dio.post('/recovery/reviews/$id/verify');
    if (response.data is! Map ||
        response.data['id'] != id ||
        response.data['companyId'] != owner.companyId) {
      throw ApiException('No pudimos comprobar la identidad de la revisión.');
    }
    if (response.data['sourceUserId'] == owner.userId) {
      await _attach(owner, response.data);
    }
  });

  Future<void> decide(Map<String, dynamic> row, String decision, String note) =>
      _owned((owner) async {
        if (row['companyId'] != owner.companyId) {
          throw ApiException('La revisión pertenece a otra empresa.');
        }
        final response = await _dio.post(
          '/recovery/reviews/${row['id']}/decision',
          data: {
            'decision': decision,
            'expectedVersion': row['version'],
            'note': note,
          },
        );
        if (response.data is! Map ||
            response.data['id'] != row['id'] ||
            response.data['companyId'] != owner.companyId) {
          throw ApiException('No pudimos comprobar la decisión guardada.');
        }
        if (response.data['sourceUserId'] == owner.userId) {
          await _attach(owner, response.data);
        }
      });

  Future<void> _attach(OperationScope owner, dynamic value) async {
    if (value is! Map ||
        value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        value['companyId'] != owner.companyId ||
        value['sourceUserId'] != owner.userId) {
      throw ApiException(
        'La respuesta no identifica la incidencia original. Se conserva para revisión.',
      );
    }
    final current = await (_tokenStorage ?? TokenStorage()).getUserSnapshot();
    if (current?.companyId != owner.companyId || current?.id != owner.userId) {
      return;
    }
    final actions = await _store.listPendingActions(
      companyId: owner.companyId,
      userId: owner.userId,
      limit: null,
    );
    final matching = actions.where(
      (action) => action.id == value['sourceActionId'],
    );
    if (matching.length != 1) return;
    final action = matching.single;
    if (action.status == 'review_resolved' || action.status == 'syncing' ||
        action.isAutomaticallyRetryable) { return; }
    final expected = requestFor(action);
    final amount = value['expectedAmount'];
    final wanted = expected['expectedAmount'];
    if (value['actionType'] != expected['actionType'] ||
        value['operationId'] != expected['operationId'] ||
        value['originalSessionId'] != expected['originalSessionId'] ||
        (wanted == null
            ? amount != null
            : amount is! num ||
                  !amount.isFinite ||
                  (amount - (wanted as num)).abs() > 0.005)) {
      throw ApiException(
        'Los datos revisados no coinciden con la operación original. Conserva la incidencia.',
      );
    }
    final status = value['status'];
    if (status == 'RESOLVED_REGISTERED' &&
        (action.type == 'cash.open' || action.type == 'cash.close') &&
        value['registeredEntityId'] is String &&
        (value['registeredEntityId'] as String).isNotEmpty &&
        value['registeredEntityId'] != expected['originalSessionId']) {
      throw ApiException(
        'El turno confirmado no coincide con la incidencia original. Se conserva para revisión.',
      );
    }
    final confirmed =
        status == 'RESOLVED_REGISTERED' &&
        value['financiallyConfirmed'] == true &&
        value['registeredEntityId'] is String &&
        (value['registeredEntityId'] as String).isNotEmpty &&
        wanted != null;
    final notPerformed =
        status == 'RESOLVED_NOT_PERFORMED' &&
        value['financiallyConfirmed'] == false;
    if (confirmed && action.type == 'sales.create') {
      await _store.markOfflineSaleSynced(
        companyId: owner.companyId,
        clientRequestId: expected['operationId'] as String,
        serverSaleId: value['registeredEntityId'] as String,
      );
    }
    if (confirmed || notPerformed) await _onResolved?.call(action, confirmed);
    await _store.updatePendingActionIfUnchanged(
      action,
      action.copyWith(
        status: confirmed || notPerformed
            ? 'review_resolved'
            : 'requires_action',
        permanent: true,
        updatedAt: DateTime.now().toUtc(),
        payload: {
          ...action.payload,
          'recoveryReviewId': value['id'],
          'recoveryReviewStatus': status,
        },
      ),
    );
    await _onChanged?.call();
  }
}
