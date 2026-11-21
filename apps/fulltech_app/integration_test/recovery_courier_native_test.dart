import 'dart:convert';
import 'dart:io';
import 'package:daleventa_pos/core/auth/operation_scope.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/recovery_review_publisher.dart';
import 'package:daleventa_pos/core/offline/recovery_review_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native courier reconnect, source restart and administrator decision without financial replay', (tester) async {
    expect(Platform.isAndroid || Platform.isWindows, true);
    if (Platform.isWindows) {sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;}
    final fixtureFile = Platform.isAndroid
      ? File('${(await getApplicationSupportDirectory()).path}/courier-auth.json')
      : File(const String.fromEnvironment('COURIER_AUTH_FILE'));
    final fixture = jsonDecode(await fixtureFile.readAsString()) as Map;
    final base = const String.fromEnvironment('API_BASE_URL').isEmpty
      ? fixture['api'] as String : const String.fromEnvironment('API_BASE_URL');
    final target = Uri.parse(base);
    expect(['127.0.0.1', '::1', '[::1]'], contains(target.host)); expect(target.port, 4004);
    final storage = TokenStorage(); final store = OfflineStore.instance;
    final source = Dio(BaseOptions(baseUrl:base));
    final admin = Dio(BaseOptions(baseUrl:base,headers:{'authorization':'Bearer ${fixture['admin']['access']}'}));
    final foreign = Dio(BaseOptions(baseUrl:base,headers:{'authorization':'Bearer ${fixture['foreign']['access']}'}));
    var now = DateTime.now().toUtc(); final run = '${now.microsecondsSinceEpoch}';
    var offline = true; var calls = 0;
    Future<void> select(String name) async {
      await storage.saveUserSnapshot(UserModel.fromJson(Map<String,dynamic>.from(fixture[name]['user'] as Map)));
      await storage.saveTokens(fixture[name]['access'] as String);
      source.options.headers['authorization'] = 'Bearer ${fixture[name]['access']}';
    }
    await select('cashier');
    final user = (await storage.getUserSnapshot())!;
    final id = 'native-courier-$run';
    final action = PendingSyncAction(id:id,type:'sales.attempt',scope:'sales',
      companyId:user.companyId,userId:user.id,idempotencyKey:id,
      payload:{'expectedTotalSold':7,'paymentMethod':'cash'},status:'requires_action',
      permanent:true,attempts:0,createdAt:now,updatedAt:now);
    await store.putPendingAction(action,requireDatabase:true);
    final repository = RecoveryReviewRepository(source,store,tokenStorage:storage);
    RecoveryReviewPublisher publisher() => RecoveryReviewPublisher(
      owner:() async {final u=await storage.getUserSnapshot();return u==null?null:OperationScope(u.companyId!,u.id);},
      list:(scope)=>store.listPendingActions(companyId:scope.companyId,userId:scope.userId,limit:null),
      clock:()=>now,submit:(a) async {
        calls++;
        if(offline) throw DioException(requestOptions:RequestOptions(path:'/recovery/reviews'),type:DioExceptionType.connectionError);
        await repository.submit(a);
      });
    await publisher().runOnce(); expect(calls,1);
    var saved=(await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null)).singleWhere((a)=>a.id==id);
    expect(saved.status,'requires_action'); expect(saved.payload,action.payload);
    offline=false; now=now.add(const Duration(seconds:31)); await publisher().runOnce();
    saved=(await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null)).singleWhere((a)=>a.id==id);
    final caseId=saved.payload['recoveryReviewId']; expect(caseId,isA<String>());
    final row=(await admin.get('/recovery/reviews/$caseId')).data as Map;
    expect(row['sourceUserId'],user.id); expect(row['expectedAmount'],7); expect(row['status'],'OPEN');
    for(final path in ['/recovery/reviews','/recovery/reviews/$caseId']) {
      await expectLater(source.get(path),throwsA(isA<DioException>().having((e)=>e.response?.statusCode,'status',403)));
    }
    await expectLater(source.post('/recovery/reviews/$caseId/verify'),throwsA(isA<DioException>().having((e)=>e.response?.statusCode,'status',403)));
    await expectLater(foreign.get('/recovery/reviews/$caseId'),throwsA(isA<DioException>().having((e)=>e.response?.statusCode,'status',anyOf(403,404))));
    final check=(await admin.post('/recovery/reviews/$caseId/verify')).data as Map;
    expect(check['verification'],'NOT_FOUND'); expect(check['financiallyConfirmed'],false);
    final decision=(await admin.post('/recovery/reviews/$caseId/decision',data:{
      'decision':'NOT_PERFORMED','expectedVersion':check['version'],'note':'Synthetic native acceptance: operation never performed',
    })).data as Map;
    expect(decision['status'],'RESOLVED_NOT_PERFORMED');
    await select('foreign'); final beforeSwitch=calls;
    now=now.add(const Duration(minutes:6)); await publisher().runOnce(); expect(calls,beforeSwitch);
    await store.closeForTesting(); await select('cashier');
    await publisher().runOnce();
    saved=(await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null)).singleWhere((a)=>a.id==id);
    expect(saved.status,'review_resolved'); expect(saved.payload['expectedTotalSold'],7);
    expect(saved.payload['recoveryReviewStatus'],'RESOLVED_NOT_PERFORMED');
    final events=(await admin.get('/recovery/reviews/$caseId')).data['events'] as List;
    expect(events.where((e)=>e['kind']=='SUBMITTED').length,1);
    expect(events.where((e)=>e['kind']=='NOT_PERFORMED').length,1);
    binding.reportData={'platform':Platform.operatingSystem,'run':run,'result':'PASS','caseId':caseId,
      'scenarios':['disconnect preserved','reconnect published','cashier admin endpoints denied','foreign tenant denied',
        'admin checked and resolved','different principal did not publish old queue','SQLite reopened and decision received',
        'original payload preserved','single submission event'],'financialPostPerformed':false};
    if (Platform.isWindows) {
      await File('${fixtureFile.parent.path}/windows-$run.json')
        .writeAsString(jsonEncode(binding.reportData));
    }
    source.close(force:true);admin.close(force:true);foreign.close(force:true);
  },timeout:const Timeout(Duration(minutes:3)));
}
