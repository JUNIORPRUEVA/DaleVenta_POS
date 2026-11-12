import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../debug/trace_log.dart';
import 'offline_store.dart';
import 'pending_sync_action.dart';
import 'sale_attempt_declaration.dart';
import 'sync_queue_service.dart';

/// Cola local de declaraciones administrativas de cobro.
///
/// Reutiliza `pending_actions` (la misma cola con idempotencia, reintentos y
/// backoff que ya usa el resto de la app) para no introducir una migración de
/// SQLite ni un segundo mecanismo de sincronización.
final saleAttemptDeclarationOutboxProvider =
    Provider<SaleAttemptDeclarationOutbox>((ref) {
      Future<PendingSyncAction?> findExisting(String id) async {
        final actions = await OfflineStore.instance.listPendingActions(
          limit: 500,
        );
        for (final action in actions) {
          if (action.id == id) return action;
        }
        return null;
      }

      return SaleAttemptDeclarationOutbox(
        findExisting: findExisting,
        enqueueAction: (action) => ref
            .read(syncQueueServiceProvider.notifier)
            .enqueue(
              id: action.id,
              type: action.type,
              scope: action.scope,
              payload: action.payload,
              companyId: action.companyId,
              userId: action.userId,
              terminalId: action.terminalId,
              entityType: action.entityType,
              entityId: action.entityId,
              idempotencyKey: action.idempotencyKey,
              requireDatabase: true,
            ),
      );
    });

/// Envía al backend las declaraciones pendientes de la cola.
final saleAttemptDeclarationSyncHandlersProvider =
    Provider<SaleAttemptDeclarationSyncHandlers>((ref) {
      return SaleAttemptDeclarationSyncHandlers(
        ref.read(syncQueueServiceProvider.notifier),
        ref.watch(dioProvider),
      )..register();
    });

/// Tras volver a iniciar sesión, las declaraciones que quedaron bloqueadas por un
/// 401 vuelven a intentarse solas.
///
/// Es seguro porque una declaración no depende de un turno de caja ni del estado
/// de la sesión anterior: es una afirmación del encargado con su propia clave de
/// idempotencia.
final saleAttemptDeclarationAuthRecoveryProvider = Provider<void>((ref) {
  ref.listen<AuthState>(authStateProvider, (previous, next) {
    final wasAuthenticated = previous?.isAuthenticated ?? false;
    if (wasAuthenticated || !next.isAuthenticated) return;
    final queue = ref.read(syncQueueServiceProvider.notifier);
    unawaited(
      queue
          .releaseAuthBlocked(type: SaleAttemptDeclaration.actionType)
          .catchError((Object error) {
            TraceLog.log('reconcile', 'declaraciones.no.rehabilitadas: $error');
            return 0;
          }),
    );
  }, fireImmediately: true);
});
