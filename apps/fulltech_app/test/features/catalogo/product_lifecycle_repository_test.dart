import 'dart:convert';
import 'dart:typed_data';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/auth/operation_scope.dart';
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
  String companyId = 'company-a';
  String userId = 'owner-a';
  @override
  Future<UserModel?> getUserSnapshot() async => UserModel(id: userId, companyId: companyId, email: 'test@example.test', nombreCompleto: 'Test', telefono: '');
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
  CatalogRepository repository(Future<ResponseBody> Function(RequestOptions) handle, [_Storage? storage]) => CatalogRepository(
    Dio(BaseOptions(baseUrl:'https://fixture.invalid'))..httpClientAdapter=_Adapter(handle), storage ?? _Storage());
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
  test('wrong archive identity cannot resolve a pending deletion', () async {
    final now=DateTime.now().toUtc();
    final action=PendingSyncAction(id:'wrong-identity',type:'catalog.products.delete',scope:'catalog',companyId:'company-a',userId:'owner-a',entityId:'protected-product',
      payload:{'id':'protected-product'},status:'conflict',attempts:1,createdAt:now,updatedAt:now);
    await OfflineStore.instance.putPendingAction(action);
    final original=(await OfflineStore.instance.listPendingActions(limit:null)).single;
    final repo=repository((_) async=>response({'ok':true,'archived':true,'product':{'id':'another-product','nombre':'Other','precio':1,'costo':0,'archivedAt':'2026-11-20T00:00:00Z'}}));
    await expectLater(repo.archivePendingDeleteConflict(original),throwsA(isA<ApiException>()));
    expect((await OfflineStore.instance.listPendingActions(limit:null)).single.toMap(),original.toMap());
  });
  test('company switch during archive never resolves the previous company queue', () async {
    final now=DateTime.now().toUtc();final storage=_Storage();
    final action=PendingSyncAction(id:'switch-owner',type:'catalog.products.delete',scope:'catalog',companyId:'company-a',userId:'owner-a',entityId:'protected-product',
      payload:{'id':'protected-product'},status:'conflict',attempts:1,createdAt:now,updatedAt:now);
    await OfflineStore.instance.putPendingAction(action);
    final original=(await OfflineStore.instance.listPendingActions(limit:null)).single;
    final repo=repository((_) async {storage.companyId='company-b';return response({'ok':true,'archived':true,'product':{'id':'protected-product','nombre':'Original','precio':1,'costo':0,'archivedAt':'2026-11-20T00:00:00Z'}});},storage);
    await expectLater(repo.archivePendingDeleteConflict(original),throwsA(isA<ApiException>()));
    expect((await OfflineStore.instance.listPendingActions(limit:null)).single.toMap(),original.toMap());
  });
  test('generic success is insufficient to confirm annulment', () async {
    final repo=repository((_) async=>response({'ok':true}));
    await expectLater(repo.annulProduct('protected-product',operationId:'operation',expectedVersion:1,reason:'Synthetic reason'),throwsA(isA<ApiException>()));
  });
  test('user switch inside the same company cannot confirm restoration', () async {
    final storage=_Storage();
    final repo=repository((_)async {
      storage.userId='another-user';
      return response({'ok':true,'archived':false,'product':{'id':'protected-product','nombre':'Original','precio':1,'costo':0,'archivedAt':null,'activo':true}});
    },storage);
    await expectLater(repo.restoreProduct('protected-product'),throwsA(isA<ApiException>()));
  });
  test('archive refuses an active product or a negative acknowledgement', () async {
    for(final data in [
      {'ok':true,'product':{'id':'protected-product','nombre':'Original','precio':1,'costo':0,'archivedAt':null,'activo':true}},
      {'ok':false,'product':{'id':'protected-product','nombre':'Original','precio':1,'costo':0,'archivedAt':'2026-11-20T00:00:00Z'}},
    ]) {
      final repo=repository((_)async=>response(data));
      await expectLater(repo.archiveProduct('protected-product'),throwsA(isA<ApiException>()));
    }
  });
  test('annulment verifies operation identity, reason and final state', () async {
    final product={'id':'protected-product','companyId':'company-a','nombre':'Original','precio':1,'costo':0,
      'stock':0,'archivedAt':'2026-11-20T00:00:00Z','annulledAt':'2026-11-20T00:00:00Z',
      'annulmentOperationId':'operation','annulmentReason':'Synthetic reason'};
    for(final change in [{'id':'other'},{'companyId':'company-b'},{'stock':1},
      {'annulmentOperationId':'different'},{'annulmentReason':'different'}, {'annulledAt':null}]) {
      final repo=repository((_)async=>response({'ok':true,'annulled':true,'product':{...product,...change}}));
      await expectLater(repo.annulProduct('protected-product',operationId:'operation',expectedVersion:1,reason:'Synthetic reason'),throwsA(isA<ApiException>()));
    }
    final repo=repository((_)async {
      expect(OperationScope.current?.companyId,'company-a');expect(OperationScope.current?.userId,'owner-a');
      return response({'ok':true,'annulled':true,'product':product});
    });
    await repo.annulProduct('protected-product',operationId:'operation',expectedVersion:1,reason:'Synthetic reason');
  });
  test('lifecycle rejects foreign identity or an invalid version before presenting actions', () async {
    final state={'productId':'protected-product','companyId':'company-a','status':'ACTIVE','lifecycleVersion':1};
    for(final change in [{'productId':'other'},{'companyId':'company-b'},{'lifecycleVersion':null},{'status':'unexpected'}]) {
      final repo=repository((_)async=>response({...state,...change}));
      await expectLater(repo.productLifecycle('protected-product'),throwsA(isA<ApiException>()));
    }
    final repo=repository((_)async=>response(state));
    expect((await repo.productLifecycle('protected-product')).productId,'protected-product');
  });
  test('archived list rejects foreign rows rather than silently showing them', () async {
    final repo=repository((_)async=>response({'items':[{'id':'other','companyId':'company-b'}]}));
    await expectLater(repo.archivedProducts(),throwsA(isA<ApiException>()));
  });
  test('restoration cannot confirm another product or one still archived', () async {
    for(final product in [
      {'id':'another-product','nombre':'Other','precio':1,'costo':0},
      {'id':'protected-product','nombre':'Original','precio':1,'costo':0,'archivedAt':'2026-11-20T00:00:00Z'},
    ]) {
      final repo=repository((_)async=>response({'ok':true,'product':product}));
      await expectLater(repo.restoreProduct('protected-product'),throwsA(isA<ApiException>()));
    }
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
