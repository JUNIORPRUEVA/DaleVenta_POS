import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/offline/sync_status_menu_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sync header status prefers processing state', () {
    final state = const SyncQueueState(
      pendingCount: 3,
      errorCount: 1,
      isProcessing: true,
    );

    expect(resolveSyncHeaderStatus(state), SyncHeaderStatus.syncing);
  });

  test('sync header status reports errors before pending items', () {
    final state = const SyncQueueState(pendingCount: 3, errorCount: 1);

    expect(resolveSyncHeaderStatus(state), SyncHeaderStatus.error);
    expect(retryableSyncWorkCount(state), 4);
  });

  test('sync header status reports attention for permanent conflicts', () {
    final state = const SyncQueueState(conflictCount: 1);

    expect(resolveSyncHeaderStatus(state), SyncHeaderStatus.attention);
  });

  test('sync header status reports pending queue', () {
    final state = const SyncQueueState(pendingCount: 2);

    expect(resolveSyncHeaderStatus(state), SyncHeaderStatus.pending);
  });

  test('sync header status reports synced queue when clean', () {
    final state = SyncQueueState(
      lastSyncedAt: DateTime.now().subtract(const Duration(seconds: 5)),
    );

    expect(resolveSyncHeaderStatus(state), SyncHeaderStatus.synced);
    expect(formatSyncLastSeen(state.lastSyncedAt), 'Ahora');
  });

  test('friendly sync message hides Dio server internals', () {
    final message = friendlySyncStatusMessage(
      'DioException [bad response]: status code of 500 '
      'RequestOptions.validateStatus',
    );

    expect(message, contains('ventas están pendientes'));
    expect(message, isNot(contains('DioException')));
    expect(message, isNot(contains('RequestOptions')));
    expect(message, isNot(contains('500')));
  });

  test('friendly sync message hides authentication internals', () {
    final message = friendlySyncStatusMessage(
      'DioException [bad response]: status code of 401 '
      'RequestOptions.validateStatus',
    );

    expect(
      message,
      'Necesitas iniciar sesión nuevamente para continuar sincronizando.',
    );
    expect(message, isNot(contains('DioException')));
    expect(message, isNot(contains('401')));
  });

  test('friendly sync message maps business conflict codes', () {
    expect(
      friendlySyncStatusMessage('ORIGIN_SESSION_CLOSED'),
      'Esta operación pertenece a un turno que ya fue cerrado y necesita revisión.',
    );
    expect(
      friendlySyncStatusMessage('INSUFFICIENT_WAREHOUSE_STOCK'),
      'No hay existencia suficiente para completar esta venta.',
    );
    expect(
      friendlySyncStatusMessage('LEGACY_MISSING_SESSION'),
      'Actualiza Fullpos para completar esta operación.',
    );
  });

  test('customer action labels hide internal sync types', () {
    expect(customerSyncActionLabel('sales.create'), 'Venta pendiente');
    expect(customerSyncActionLabel('cash.close'), 'Cierre de turno pendiente');
    expect(
      customerSyncActionLabel('cash.movement'),
      'Movimiento de caja pendiente',
    );
    expect(customerSyncActionLabel('refund'), 'Devolución pendiente');
    expect(customerSyncActionLabel('sale.cancel'), 'Cancelación pendiente');
    expect(customerSyncActionLabel('credit.payment'), 'Abono pendiente');
  });
}
