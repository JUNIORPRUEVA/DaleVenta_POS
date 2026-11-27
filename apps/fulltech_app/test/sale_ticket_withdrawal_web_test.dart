@TestOn('browser')
library;

import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/pos_sale_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final status in [
    'OPEN',
    'RESOLVED_NOT_PERFORMED',
    'RESOLVED_REGISTERED',
  ]) {
    test(
      'PWA retains the archived identity and advances only a confirmed withdrawal: $status',
      () async {
        final store = OfflineStore.instance;
        final key = posSaleRequestId(
          companyId: 'c',
          userId: 'u',
          deviceId: 'd',
          ticketId: 't',
        )!;
        final now = DateTime.now().toUtc();
        await store.putPendingAction(
          PendingSyncAction(
            id: 'sales.create:$key',
            type: 'sales.create',
            scope: 'sales',
            companyId: 'c',
            userId: 'u',
            idempotencyKey: key,
            payload: {
              'posTicketId': 't',
              'deviceFingerprint': 'd',
              'recoveryReviewStatus': status,
              'recoveryReviewId': 'review',
            },
            status: status == 'OPEN' ? 'requires_action' : 'review_resolved',
            attempts: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
        expect(
          await store.saleAttemptRevisionForTicket(
            companyId: 'c',
            userId: 'u',
            deviceId: 'd',
            ticketId: 't',
          ),
          status == 'RESOLVED_NOT_PERFORMED' ? 1 : 0,
        );
        final rows = await store.listPendingActions(
          companyId: 'c',
          userId: 'u',
          limit: null,
        );
        expect(rows.single.idempotencyKey, key);
        expect(rows.single.payload['recoveryReviewStatus'], status);
        expect(
          await store.saleAttemptRevisionForTicket(
            companyId: 'other',
            userId: 'u',
            deviceId: 'd',
            ticketId: 't',
          ),
          0,
        );
      },
    );
  }
}
