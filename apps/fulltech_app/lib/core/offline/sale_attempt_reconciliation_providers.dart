import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_repository.dart';
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

  return SaleAttemptReconciler(
    listAttempts: ({companyId, userId}) => store.listPendingActions(
      companyId: companyId,
      userId: userId,
      limit: 50,
    ),
    removeAttempt: store.removePendingAction,
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
  );
});
