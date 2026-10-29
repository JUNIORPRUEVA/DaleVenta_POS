import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_repository.dart';
import 'sale_attempt_declaration.dart';
import 'sync_queue_service.dart';

/// Cola local de declaraciones administrativas de cobro.
///
/// Reutiliza `pending_actions` (la misma cola con idempotencia, reintentos y
/// backoff que ya usa el resto de la app) para no introducir una migración de
/// SQLite ni un segundo mecanismo de sincronización.
final saleAttemptDeclarationOutboxProvider =
    Provider<SaleAttemptDeclarationOutbox>((ref) {
      return SaleAttemptDeclarationOutbox(
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
