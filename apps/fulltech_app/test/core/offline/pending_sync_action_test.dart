import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PendingSyncAction', () {
    test('hydrates v1 rows and infers catalog company from scope', () {
      final action = PendingSyncAction.fromMap({
        'id': 'catalog.product.create:op-1',
        'type': 'catalog.product.create',
        'scope': 'catalog.company-1',
        'payload': {'operationId': 'op-1', 'id': 'product-1'},
        'status': 'pending',
        'attempts': 0,
        'createdAt': '2026-08-19T12:00:00Z',
        'updatedAt': '2026-08-19T12:00:00Z',
      });

      expect(action.companyId, 'company-1');
      expect(action.entityId, 'product-1');
      expect(action.idempotencyKey, 'op-1');
      expect(action.permanent, isFalse);
    });

    test('round trips retry metadata without payload changes', () {
      final nextAttempt = DateTime.utc(2026, 8, 19, 12, 5);
      final lastAttempt = DateTime.utc(2026, 8, 19, 12, 0);
      final action = PendingSyncAction(
        id: 'sales.create:request-1',
        type: 'sales.create',
        scope: 'sales',
        companyId: 'company-1',
        userId: 'user-1',
        entityType: 'sale',
        entityId: 'local-sale-1',
        idempotencyKey: 'request-1',
        payload: {'clientRequestId': 'request-1'},
        status: 'error',
        attempts: 2,
        error: 'network',
        nextAttemptAt: nextAttempt,
        lastAttemptAt: lastAttempt,
        createdAt: DateTime.utc(2026, 8, 19, 11, 59),
        updatedAt: DateTime.utc(2026, 8, 19, 12, 0),
      );

      final restored = PendingSyncAction.fromMap(action.toMap());

      expect(restored.companyId, 'company-1');
      expect(restored.userId, 'user-1');
      expect(restored.nextAttemptAt, nextAttempt);
      expect(restored.lastAttemptAt, lastAttempt);
      expect(restored.payload, {'clientRequestId': 'request-1'});
    });
  });
}
