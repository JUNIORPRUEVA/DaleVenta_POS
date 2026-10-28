import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_repository.dart';
import 'pending_sync_action.dart';
import 'sale_attempt_audit.dart';
import 'sale_attempt_reconciliation.dart';
import 'sync_queue_service.dart';

/// Reconciliador de intentos de cobro.
///
/// La consulta al backend es de SOLO LECTURA. Si no hay red, el servidor falla o
/// responde algo que no se entiende, se devuelve `null` y el intento se queda
/// intacto: nunca se resuelve un cobro por descarte.
final saleAttemptReconcilerProvider = Provider<SaleAttemptReconciler>((ref) {
  final dio = ref.watch(dioProvider);
  final store = ref.watch(offlineStoreProvider);

  SaleAttemptAuditEntry buildEntry({
    required PendingSyncAction action,
    required String clientRequestId,
    required SaleAttemptReconciliationResult result,
    required SaleAttemptDecision decision,
    String? actorUserId,
    String? actorRole,
    String? note,
    required DateTime checkedAt,
  }) {
    return SaleAttemptAuditEntry(
      id: '${action.id}#${checkedAt.millisecondsSinceEpoch}#${decision.code}',
      pendingActionId: action.id,
      clientRequestId: clientRequestId,
      decision: decision,
      checkedAt: checkedAt,
      companyId: action.companyId,
      userId: action.userId,
      serverStatus: result.status.name.toUpperCase(),
      guidance: result.guidance,
      voided: result.voided,
      saleId: result.saleId,
      totalSold: result.totalSold,
      paymentMethod: result.paymentMethod,
      movementId: result.movementId,
      actorUserId: actorUserId,
      actorRole: actorRole,
      note: note,
      operationFingerprint: action.operationFingerprint,
      mechanism: SaleAttemptReconciler.mechanism,
    );
  }

  return SaleAttemptReconciler(
    listAttempts: ({companyId, userId}) => store.listUnresolvedSaleAttempts(
      companyId: companyId,
      userId: userId,
    ),
    lookup: (clientRequestId, expectedTotalSold) async {
      try {
        final res = await dio.get(
          '${ApiRoutes.sales}/attempts/$clientRequestId/reconciliation',
          queryParameters: expectedTotalSold == null
              ? null
              : {'expectedTotalSold': expectedTotalSold.toStringAsFixed(2)},
          options: Options(extra: const {'skipLoader': true}),
        );
        final data = res.data;
        if (data is Map) return data.cast<String, dynamic>();
        return null;
      } on DioException {
        return null;
      } catch (_) {
        return null;
      }
    },
    recordEvidence:
        ({
          required action,
          required clientRequestId,
          required result,
          required decision,
          actorUserId,
          actorRole,
          note,
        }) async {
          await store.appendSaleAttemptAudit(
            buildEntry(
              action: action,
              clientRequestId: clientRequestId,
              result: result,
              decision: decision,
              actorUserId: actorUserId,
              actorRole: actorRole,
              note: note,
              checkedAt: DateTime.now().toUtc(),
            ),
          );
        },
    resolveAttempt:
        ({
          required action,
          required clientRequestId,
          required result,
          required decision,
          actorUserId,
          actorRole,
          note,
        }) {
          return store.resolveSaleAttemptAtomically(
            pendingActionId: action.id,
            entry: buildEntry(
              action: action,
              clientRequestId: clientRequestId,
              result: result,
              decision: decision,
              actorUserId: actorUserId,
              actorRole: actorRole,
              note: note,
              checkedAt: DateTime.now().toUtc(),
            ),
          );
        },
    readAudit: ({companyId, clientRequestId, limit = 50}) =>
        store.listSaleAttemptAudit(
          companyId: companyId,
          clientRequestId: clientRequestId,
          limit: limit,
        ),
  );
});
