import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/catalogo/data/catalog_repository.dart';
import 'package:daleventa_pos/features/products/ui/product_lifecycle_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

class _FixtureStorage extends TokenStorage {
  _FixtureStorage(this.user);
  final UserModel user;
  @override
  Future<UserModel?> getUserSnapshot() async => user;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real product lifecycle buttons preserve stock, identity and Kardex', (tester) async {
    expect(Platform.isWindows || Platform.isAndroid, true);
    if (Platform.isWindows) { sqfliteFfiInit(); databaseFactory = databaseFactoryFfi; }
    final support = await getApplicationSupportDirectory();
    final file = Platform.isAndroid ? File('${support.path}/product-lifecycle-auth.json')
      : File(const String.fromEnvironment('PRODUCT_LIFECYCLE_AUTH_FILE'));
    final fixture = jsonDecode(await file.readAsString()) as Map;
    final base = Platform.isAndroid ? 'http://127.0.0.1:4004' : 'http://127.0.0.1:4017';
    final dio = Dio(BaseOptions(baseUrl: base));
    final login = await dio.post('/auth/login', data: {'email':fixture['email'], 'password':fixture['password']});
    expect(login.data['user']['companyId'], fixture['user']['companyId']);
    dio.options.headers['Authorization'] = 'Bearer ${login.data['accessToken']}';
    final user = UserModel.fromJson(Map<String, dynamic>.from(fixture['user'] as Map));
    final repo = CatalogRepository(dio, _FixtureStorage(user));
    final pendingBefore = (await OfflineStore.instance.listPendingActions(limit: null)).map((a)=>a.toMap()).toList();
    final evidence = Directory(Platform.isAndroid ? '${support.path}/product-lifecycle-evidence'
      : const String.fromEnvironment('PRODUCT_LIFECYCLE_EVIDENCE_DIR'));
    await evidence.create(recursive: true);
    final boundary = GlobalKey();
    late BuildContext host;
    var changed = 0;
    await tester.pumpWidget(ProviderScope(overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: RepaintBoundary(key: boundary, child: MaterialApp(theme: AppTheme.light,
        home: Builder(builder: (context) {host = context; return const Scaffold(body: Center(child: Text('Productos · Pruebas locales')));})))));
    Future<void> settle() async {
      for (var n=0; n<30; n++) { await tester.pump(const Duration(milliseconds: 100)); }
      expect(tester.takeException(), isNull);
    }
    Future<void> capture(String name) async {
      await tester.pump();
      final image = await (boundary.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${evidence.path}/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }
    Future<Map> create(String label, double stock) async {
      final response = await dio.post('/products', data: {'nombre':'Native $label ${const Uuid().v4()}',
        'categoria':'UAT', 'precio':10, 'costo':5, 'stock':stock, 'operationId':const Uuid().v4()});
      return response.data as Map;
    }
    Future<Map> inspect(String id) async => (await dio.get('/products/$id/lifecycle')).data as Map;
    final previousFile=File('${evidence.path}/native-result.json');
    if(await previousFile.exists()) {
      final previous=jsonDecode(await previousFile.readAsString()) as Map;
      if(previous['companyId']==user.companyId) {
        final retained=await inspect('${previous['productId']}');
        expect(retained['status'],'ANNULLED');expect(retained['stock'],0);
        expect(retained['references']['inventoryMovements'],2);
      }
    }
    Future<void> manage(Map product) async {
      // The shipped widget uses the real repository and HTTP API, without mock eligibility.
      showDialog<void>(context: host, builder: (_) => ProductLifecycleDialog(
        productId: '${product['id']}', name: '${product['nombre']}', onChanged: () async {changed++;}));
      await settle();
    }
    Future<void> action(String label) async {
      await tester.ensureVisible(find.text(label).first);
      await tester.tap(find.text(label).first); await settle();
      await tester.tap(find.widgetWithText(ElevatedButton, label)); await settle();
      await capture('after-$label');
    }
    final product = await create('stock', 7);
    final id = '${product['id']}';
    final original = await inspect(id);
    expect(original['canAnnul'], true);
    await manage(product); expect(find.text('Archivar'), findsOneWidget);
    expect(find.text('Eliminar definitivamente'), findsNothing);
    await capture('01-active');
    await action('Archivar');
    final archived = await inspect(id); expect(archived['status'], 'ARCHIVED'); expect(archived['stock'], 7);
    expect(archived['references'], original['references']);
    showDialog<void>(context: host, builder: (_) => ArchivedProductsDialog(onChanged: () async {changed++;}));
    await settle(); expect(find.text('${product['nombre']}'), findsOneWidget);
    await capture('02-archived-list');
    await tester.tap(find.text('${product['nombre']}')); await settle();
    await action('Restaurar');
    expect((await inspect(id))['status'], 'ACTIVE');
    await tester.tap(find.text('Cerrar')); await settle();
    await manage(product);
    await tester.enterText(find.byType(TextField), 'Alta de prueba creada por error');
    await capture('03-annul-confirmation-ready');
    await action('Anular alta');
    final annulled = await inspect(id); expect(annulled['status'], 'ANNULLED'); expect(annulled['stock'], 0);
    expect(annulled['references']['inventoryMovements'], 2);
    await manage(product); expect(find.text('Restaurar'), findsNothing); expect(find.text('Archivar'), findsNothing);
    expect(find.text('Anular alta'), findsNothing); await capture('04-annulled');
    await tester.tap(find.text('Cerrar')); await settle();
    final empty = await create('zero', 0); await manage(empty);
    expect(find.text('Eliminar definitivamente'), findsOneWidget);
    await tester.tap(find.text('Eliminar definitivamente')); await settle();
    await tester.tap(find.text('Eliminar').last); await settle();
    await expectLater(dio.get('/products/${empty['id']}/lifecycle'), throwsA(isA<DioException>().having((e)=>e.response?.statusCode,'deleted',404)));
    final pendingAfter = (await OfflineStore.instance.listPendingActions(limit: null)).map((a)=>a.toMap()).toList();
    expect(pendingAfter, pendingBefore);
    // Exercise the shipped SQLite outbox and real HTTP handlers across a
    // disconnected pass, storage reopen, permanent rejection and valid replay.
    final valid=await create('reconnect',0);
    final store=OfflineStore.instance;
    final staleId='lifecycle-stale:${const Uuid().v4()}';
    final validId='lifecycle-valid:${const Uuid().v4()}';
    final now=DateTime.now().toUtc();
    for(final entry in [(staleId,id),(validId,'${valid['id']}')]) {
      await store.putPendingAction(PendingSyncAction(id:entry.$1,type:'catalog.products.stock',scope:'catalog',
        companyId:user.companyId,userId:user.id,entityId:entry.$2,entityType:'product',
        payload:{'id':entry.$2,'delta':5,'operationId':const Uuid().v4(),'reason':'Synthetic reconnect regression'},
        status:'pending',attempts:0,createdAt:now,updatedAt:now));
    }
    var offline=true;
    dio.interceptors.add(InterceptorsWrapper(onRequest:(options,handler) {
      if(offline) {handler.reject(DioException(requestOptions:options,type:DioExceptionType.connectionError));}
      else {handler.next(options);}
    }));
    SyncQueueService queue()=>SyncQueueService(store,scopeResolver:()async=>OfflineSyncScope(companyId:user.companyId,userId:user.id));
    var sync=queue();CatalogRepository(dio,_FixtureStorage(user),sync).registerSyncHandlers();
    await sync.processPending();sync.dispose();await store.closeForTesting();
    final scoped=await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null);
    expect(scoped.any((a)=>a.id==staleId),true);expect(scoped.any((a)=>a.id==validId),true);
    for(final action in scoped.where((a)=>a.id==staleId||a.id==validId)) {
      await store.updatePendingAction(action.copyWith(clearNextAttemptAt:true));
    }
    offline=false;sync=queue();CatalogRepository(dio,_FixtureStorage(user),sync).registerSyncHandlers();
    await sync.processPending();
    final saved=(await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null)).singleWhere((a)=>a.id==staleId);
    expect(saved.isAutomaticallyRetryable,false);expect(saved.payload['id'],id);
    expect((await inspect('${valid['id']}'))['stock'],5);
    expect((await inspect(id))['stock'],0);
    await sync.processPending();sync.dispose();await store.closeForTesting();
    final finalRows=await store.listPendingActions(limit:null);
    expect(finalRows.singleWhere((a)=>a.id==staleId).attempts,saved.attempts);
    for(final original in pendingBefore) {expect(finalRows.singleWhere((a)=>a.id==original['id']).toMap(),original);}
    final pendingProduct=await create('archive pending deletion',3);
    final archivedActionId='lifecycle-archive-resolution:${const Uuid().v4()}';
    await store.putPendingAction(PendingSyncAction(id:archivedActionId,type:'catalog.products.delete',scope:'catalog',
      companyId:user.companyId,userId:user.id,entityId:'${pendingProduct['id']}',entityType:'product',
      payload:{'id':pendingProduct['id'],'originalEvidence':'preserved'},status:'conflict',attempts:2,createdAt:now,updatedAt:now));
    final pendingDelete=(await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null)).singleWhere((a)=>a.id==archivedActionId);
    await repo.archivePendingDeleteConflict(pendingDelete);
    final resolved=(await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null)).singleWhere((a)=>a.id==archivedActionId);
    expect(resolved.status,'review_resolved');expect(resolved.attempts,2);expect(resolved.createdAt,pendingDelete.createdAt);
    expect(resolved.payload['originalEvidence'],'preserved');expect((await inspect('${pendingProduct['id']}'))['stock'],3);
    expect((await inspect('${pendingProduct['id']}'))['status'],'ARCHIVED');
    await File('${evidence.path}/native-result.json').writeAsString(jsonEncode({
      'result':'PASS','platform':Platform.operatingSystem,'companyId':user.companyId,'productId':id,
      'deletedProductId':empty['id'],'annulmentOperationId':annulled['annulmentOperationId'],
      'changedCallbacks':changed,'realHttp':true,'originalStock':7,'finalStock':0,'movements':2,
      'localPendingBefore':pendingBefore.length,'localPendingAfter':pendingAfter.length,'localPendingUnchanged':true,
      'reconnectPermanentIncidentPreserved':true,'validStockAfterReconnect':5,'staleActionId':staleId,
      'reconnectProductId':valid['id'],
      'archivePendingDeletePreserved':true,'archivedResolutionProductId':pendingProduct['id'],
      'reconnectProductId':valid['id'],
    }));
    await tester.pumpWidget(const SizedBox.shrink()); dio.close();
  });
}
