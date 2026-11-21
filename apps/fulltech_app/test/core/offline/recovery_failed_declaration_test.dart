import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineStore store;
  late PendingSyncAction action;
  setUp(() async {
    sqfliteFfiInit(); databaseFactory=databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    store=OfflineStore.forTesting('failed_decl_${DateTime.now().microsecondsSinceEpoch}.db');
    final now=DateTime.now().toUtc();
    action=PendingSyncAction(id:'declaration',type:'sales.declaration',scope:'sales',companyId:'company',userId:'admin',
      idempotencyKey:'original',payload:const {'clientRequestId':'original','totalDeclared':7,'occurredAt':'2026-11-20T10:00:00Z'},
      status:'failed',permanent:true,attempts:1,createdAt:now,updatedAt:now);
    await store.putPendingAction(action,requireDatabase:true);
  });
  tearDown(() => store.closeForTesting());
  test('withdrawing a rejected declaration conserves all original data after reopen', () async {
    await store.archiveFailedDeclaration(id:action.id,companyId:'company',userId:'admin',actorRole:'ADMIN',note:'La declaración fue rechazada y era incorrecta.');
    await store.closeForTesting();
    final saved=(await store.listPendingActions(companyId:'company',userId:'admin')).single;
    expect(saved.status,'review_resolved');
    expect(saved.idempotencyKey,'original');
    for(final entry in action.payload.entries){expect(saved.payload[entry.key],entry.value);}
    expect(saved.createdAt.millisecondsSinceEpoch,action.createdAt.millisecondsSinceEpoch);
    expect((saved.payload['administrativeWithdrawal'] as Map)['actorRole'],'ADMIN');
    expect((await store.listPendingActions(companyId:'company',userId:'admin',processableOnly:true)),isEmpty);
  });
  for(final kind in ['cashier','other-company','uncertain']) {
    test('$kind cannot withdraw this evidence', () async {
      if(kind=='uncertain')await store.updatePendingAction(action.copyWith(status:'error',permanent:false));
      await expectLater(store.archiveFailedDeclaration(id:action.id,companyId:kind=='other-company'?'another':'company',
        userId:'admin',actorRole:kind=='cashier'?'CAJERO':'ADMIN',note:'Motivo de prueba válido'),throwsStateError);
      final saved=(await store.listPendingActions()).single;
      expect(saved.payload,action.payload);
      expect(saved.status,kind=='uncertain'?'error':'failed');
    });
  }
}
