import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:daleventa_pos/core/offline/recovery_sale_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 20);
  final action = PendingSyncAction(id: 'attempt', type: 'sales.attempt', scope: 'sales',
    idempotencyKey: 'original', companyId: 'company', userId: 'owner', status: 'requires_action', attempts: 0,
    createdAt: now, updatedAt: now, payload: const {'expectedTotalSold': 7});
  final absent = {'status': 'NOT_FOUND', 'clientRequestId': 'original', 'guidance': 'NOT_REGISTERED'};
  setUp(SaleAttemptReconciler.resetInFlightForTests);
  for (final mode in ['absent', 'confirmed', 'network', '401', '429', 'mismatch']) {
    test('strong read-only check: $mode', () async {
      var calls = 0;
      var resolved = 0;
      final reconciler = SaleAttemptReconciler(
        lookup: (_, _) async {
          calls++;
          if (mode == '401' || mode == '429') return {'status':'UNKNOWN', 'clientRequestId':'original', 'guidance':'LOOKUP_HTTP_$mode'};
          if (mode == 'mismatch') return {'status':'CONFIRMED', 'clientRequestId':'another', 'matchesExpected':true, 'sale':{'id':'sale','totalSold':7}};
          if (calls == 1) return absent;
          if (mode == 'network') return null;
          if (mode == 'confirmed') return {'status':'CONFIRMED', 'clientRequestId':'original', 'matchesExpected':true, 'sale':{'id':'sale','totalSold':7}};
          return absent;
        },
        listAttempts: ({companyId, userId}) async => [action],
        recordEvidence: ({required action, required clientRequestId, required result, required decision, actorUserId, actorRole, note}) async {},
        resolveAttempt: ({required action, required clientRequestId, required result, required decision, actorUserId, actorRole, note}) async { resolved++; return true; },
      );
      final result = await reconciler.verifyThoroughly(action);
      expect(calls, ['401','429','mismatch'].contains(mode) ? 1 : 2);
      expect(resolved, mode == 'confirmed' ? 1 : 0);
      if (mode == 'network') expect(result, isNull);
      if (mode == 'absent') expect(result?.status, SaleAttemptReconciliationStatus.notFound);
    });
  }
  test('draft validation rejects incomplete or invalid lines without changing the original', () {
    for (final lines in [null, [], [{'qty':0,'priceSoldUnit':7}], [{'qty':1,'priceSoldUnit':-1}], [{'qty':1,'priceSoldUnit':'NaN'}]]) {
      expect(recoverySaleItemsAreValid(action.copyWith(payload:{'items':lines})), isFalse);
    }
    expect(recoverySaleItemsAreValid(action.copyWith(payload:{'items':[{'qty':2,'priceSoldUnit':7}]})), isTrue);
    expect(action.payload, {'expectedTotalSold':7});
  });
  for (final kind in ['local-delay','server-delay','legacy-delay']) {
    test('manual verification distinguishes $kind without bypassing server waits', () async {
      var calls=0;
      final delayed=action.copyWith(nextAttemptAt:DateTime.now().toUtc().add(const Duration(minutes:1)),
        payload:{...action.payload,if(kind!='legacy-delay')'reconciliationRetryAfterIsServer':kind=='server-delay'});
      final reconciler=SaleAttemptReconciler(lookup:(_,_)async{calls++;return absent;},
        listAttempts:({companyId,userId})async=>[delayed],
        recordEvidence:({required action,required clientRequestId,required result,required decision,actorUserId,actorRole,note})async{},
        resolveAttempt:({required action,required clientRequestId,required result,required decision,actorUserId,actorRole,note})async=>false);
      await reconciler.verifyThoroughly(delayed);
      expect(calls,kind=='local-delay'?2:0);
      expect(delayed.nextAttemptAt,isNotNull);
    });
  }
}
