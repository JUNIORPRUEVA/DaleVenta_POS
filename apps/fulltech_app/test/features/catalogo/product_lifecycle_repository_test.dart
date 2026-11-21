import 'dart:convert';
import 'dart:typed_data';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Storage extends TokenStorage {
  @override
  Future<UserModel?> getUserSnapshot() async => UserModel(id: 'owner-a', companyId: 'company-a', email: 'test@example.test', nombreCompleto: 'Test', telefono: '');
}
class _Adapter implements HttpClientAdapter {
  _Adapter(this.handle);
  final Future<ResponseBody> Function(RequestOptions) handle;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream, Future<void>? cancel) => handle(options);
  @override
  void close({bool force = false}) {}
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {sqfliteFfiInit(); databaseFactory = databaseFactoryFfi;});
  // SQLite tests run in an ephemeral Flutter-test database, never app data.
  setUp(() async {SharedPreferences.setMockInitialValues({}); await OfflineStore.instance.clearAll();});
  PendingSyncAction pending(String company, {String status = 'requires_action'}) {
    final now=DateTime.now().toUtc();
    return PendingSyncAction(id: 'test-$company', type:'sales.attempt', scope:'sales', companyId:company,
      userId:'owner-a', payload:{'items':[{'productId':'protected-product'}]}, status:status,
      attempts:1, createdAt:now, updatedAt:now);
  }
  CatalogRepository repository(Future<ResponseBody> Function(RequestOptions) handle) => CatalogRepository(
    Dio(BaseOptions(baseUrl:'https://fixture.invalid'))..httpClientAdapter=_Adapter(handle), _Storage());
  ResponseBody response(Object value) => ResponseBody.fromString(jsonEncode(value),200,
    headers:{Headers.contentTypeHeader:[Headers.jsonContentType]});
  test('unresolved local sale blocks archive, delete, restore and annul without changing queue', () async {
    final action=pending('company-a'); await OfflineStore.instance.putPendingAction(action);
    final before=(await OfflineStore.instance.listPendingActions(limit:null)).single.toMap();
    var calls=0; final repo=repository((_) async {calls++; return response({'ok':true});});
    for(final operation in [() => repo.deleteProduct('protected-product'), () => repo.archiveProduct('protected-product'),
      () => repo.restoreProduct('protected-product'), () => repo.annulProduct('protected-product',operationId:'op',expectedVersion:0,reason:'Synthetic reason')]) {
      await expectLater(operation(), throwsA(isA<ApiException>().having((e)=>e.message,'reason',contains('pendientes'))));
    }
    expect(calls,0);
    final saved=(await OfflineStore.instance.listPendingActions(limit:null)).single;
    expect(saved.toMap(),before);
  });
  test('another tenant pending sale does not block the current tenant', () async {
    await OfflineStore.instance.putPendingAction(pending('company-b'));
    var calls=0; final repo=repository((_) async {calls++; return response({'ok':true});});
    await repo.deleteProduct('protected-product'); expect(calls,1);
    expect((await OfflineStore.instance.listPendingActions(companyId:'company-b',limit:null)).length,1);
  });
  test('legacy archived success is never interpreted as physical deletion', () async {
    final repo=repository((_) async => response({'ok':true,'archived':true}));
    await expectLater(repo.deleteProduct('zero'),throwsA(isA<ApiException>().having((e)=>e.message,'confirmation',contains('No se confirmó'))));
  });
  test('annul submits original command and never creates an offline operation on timeout', () async {
    Object? body; final repo=repository((options) async {body=options.data; throw DioException(requestOptions:options,type:DioExceptionType.connectionTimeout);});
    await expectLater(repo.annulProduct('zero',operationId:'original-op',expectedVersion:12,reason:'  Synthetic original reason  '),throwsA(isA<ApiException>()));
    expect(body,{'operationId':'original-op','expectedVersion':12,'reason':'Synthetic original reason'});
    expect(await OfflineStore.instance.listPendingActions(limit:null),isEmpty);
  });
  test('archived search filters on server before pagination', () async {
    final repo=repository((options) async {
      expect(options.queryParameters, {'archivedOnly':'true','page':2,'limit':50,'search':'texto'});
      return response({'items':<Map<String,dynamic>>[]});
    });
    expect(await repo.archivedProducts(search:' texto ',page:2),isEmpty);
  });
  test('archiving a pending delete retains its original evidence and resolves only that row', () async {
    final now=DateTime.now().toUtc();
    final action=PendingSyncAction(id:'delete-original',type:'catalog.products.delete',scope:'catalog',
      companyId:'company-a',userId:'owner-a',entityId:'protected-product',
      payload:{'id':'protected-product','operationId':'original-command'},status:'conflict',attempts:3,createdAt:now,updatedAt:now);
    await OfflineStore.instance.putPendingAction(action);
    final original=(await OfflineStore.instance.listPendingActions(limit:null)).single;
    final repo=repository((options) async {
      expect(options.path,'/products/protected-product/archive');
      return response({'ok':true,'product':{'id':'protected-product','nombre':'Prueba','precio':1,'costo':0,'stock':4,'archivedAt':'2026-11-20T00:00:00Z','activo':false}});
    });
    await repo.archivePendingDeleteConflict(original);
    final saved=(await OfflineStore.instance.listPendingActions(limit:null)).single;
    expect(saved.id,original.id);expect(saved.createdAt,original.createdAt);expect(saved.attempts,3);
    expect(saved.status,'review_resolved');expect(saved.permanent,true);
    for(final entry in original.payload.entries){expect(saved.payload[entry.key],entry.value);}
    expect(saved.payload['productResolution'],{'decision':'ARCHIVED','productId':'protected-product'});
  });
  test('foreign owner cannot resolve a pending delete', () async {
    final action=pending('company-b');var calls=0;
    final repo=repository((_) async {calls++;return response({});});
    await expectLater(repo.archivePendingDeleteConflict(action),throwsA(isA<ApiException>()));
    expect(calls,0);
  });
  test('a concurrent queue change is preserved after archive acknowledgement', () async {
    final now=DateTime.now().toUtc();
    final action=PendingSyncAction(id:'racing',type:'catalog.products.delete',scope:'catalog',companyId:'company-a',userId:'owner-a',entityId:'protected-product',
      payload:{'id':'protected-product'},status:'conflict',attempts:1,createdAt:now,updatedAt:now);
    await OfflineStore.instance.putPendingAction(action);
    final original=(await OfflineStore.instance.listPendingActions(limit:null)).single;
    final changed=original.copyWith(attempts:2,payload:{...original.payload,'newEvidence':'retained'});
    final repo=repository((_) async {
      await OfflineStore.instance.updatePendingAction(changed);
      return response({'ok':true,'product':{'id':'protected-product','nombre':'Prueba','precio':1,'costo':0,'stock':4,'archivedAt':'2026-11-20T00:00:00Z','activo':false}});
    });
    await expectLater(repo.archivePendingDeleteConflict(original),throwsA(isA<ApiException>()));
    final saved=(await OfflineStore.instance.listPendingActions(limit:null)).single;
    expect(saved.payload,changed.payload);expect(saved.attempts,2);expect(saved.status,'conflict');
  });
}
