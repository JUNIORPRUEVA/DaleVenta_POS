import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/offline/sale_attempt_recovery_screen.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:daleventa_pos/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final binding=IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows recovery verifies and opens an editable independent ticket without charging', (tester) async {
    expect(Platform.isWindows, isTrue);
    final api=Uri.parse(const String.fromEnvironment('API_BASE_URL'));
    expect(['127.0.0.1','::1','[::1]'],contains(api.host)); expect(api.port,4004);
    final directory=Directory(const String.fromEnvironment('RECOVERY_EVIDENCE_DIR'));
    await directory.create(recursive:true);
    sqfliteFfiInit(); databaseFactory=databaseFactoryFfi;
    final storage=TokenStorage();
    final auth=jsonDecode(await File(const String.fromEnvironment('UAT_NATIVE_AUTH_FILE')).readAsString()) as Map;
    await storage.saveTokens(auth['access'] as String);
    final originalHandler=FlutterError.onError;
    final originalWidget=ErrorWidget.builder;
    await app.main();
    FlutterError.onError=originalHandler; ErrorWidget.builder=originalWidget;
    for(var i=0;i<35;i++){await tester.pump(const Duration(milliseconds:100));}
    FlutterError.onError=originalHandler; ErrorWidget.builder=originalWidget;
    final user=await storage.getUserSnapshot(); expect(user?.role,'ADMIN');
    final store=OfflineStore.instance;
    final before=await store.listPendingActions(companyId:user!.companyId,userId:user.id,limit:null);
    final id='ui-native-${DateTime.now().microsecondsSinceEpoch}';
    final now=DateTime.now().toUtc();
    final action=PendingSyncAction(id:'sales.attempt:$id',type:'sales.attempt',scope:'sales',
      companyId:user.companyId,userId:user.id,idempotencyKey:id,entityId:id,
      operationFingerprint:'native-recovery-ui-$id',status:'requires_action',attempts:0,createdAt:now,updatedAt:now,
      payload:const {'expectedTotalSold':14.0,'paymentMethod':'cash',
        'items':[{'productId':'','productName':'Artículo recuperado UAT','qty':2.0,'priceSoldUnit':7.0,'costUnitSnapshot':0.0}]});
    await store.reserveRemoteSaleAttempt(action);
    await tester.pumpWidget(ProviderScope(child:MaterialApp(theme:AppTheme.light,home:const SaleAttemptRecoveryScreen())));
    Future<void> until(Finder finder) async {
      for(var i=0;i<180&&finder.evaluate().isEmpty;i++){
        await tester.pump(const Duration(milliseconds:100));
        await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));
      }
      expect(finder,findsWidgets);
    }
    Future<void> capture(String name) async {
      final view=binding.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final picture=await (view.layer! as OffsetLayer).toImage(view.paintBounds);
      final data=await picture.toByteData(format:ui.ImageByteFormat.png);
      await File('${directory.path}/$name.png').writeAsBytes(data!.buffer.asUint8List()); picture.dispose();
    }
    final card=find.byKey(ValueKey('sale-incident:${action.id}'));
    final verifyButton=find.descendant(of:card,matching:find.text('Verificar ahora'));
    await until(verifyButton);
    expect(find.text('Más opciones'),findsNothing);
    expect(find.text('Eliminar pendiente'),findsNothing);
    await capture('01-check-only');
    await tester.ensureVisible(verifyButton);
    await tester.tap(verifyButton);
    await until(find.text('Resultado de la verificación'));
    await tester.tap(find.text('Entendido'));
    await until(find.text('Hacer el cobro de nuevo'));
    expect(verifyButton,findsNothing);
    await capture('02-two-solutions');
    await tester.ensureVisible(find.text('Hacer el cobro de nuevo'));
    await tester.tap(find.text('Hacer el cobro de nuevo'));
    await until(find.text('Autorizar venta nueva'));
    await tester.tap(find.text('Autorizar venta nueva'));
    await until(find.byType(CotizacionesScreen));
    await until(find.text('Artículo recuperado UAT'));
    await capture('03-editable-sales-ticket');
    final after=await store.listPendingActions(companyId:user.companyId,userId:user.id,limit:null);
    for(final original in before){
      final retained=after.singleWhere((row)=>row.id==original.id);
      expect(retained.payload,original.payload); expect(retained.createdAt,original.createdAt);
    }
    for(final entry in action.payload.entries){expect(after.singleWhere((row)=>row.id==action.id).payload[entry.key],entry.value);}
    expect(after.singleWhere((row)=>row.id==action.id).status,'requires_action');
    final audit=await store.listSaleAttemptAudit(companyId:user.companyId,clientRequestId:id);
    expect(audit.any((row)=>row.decision.code=='MANUAL_AUTHORIZED_NEW_SALE'),isTrue);
    await File('${directory.path}/native-ui.json').writeAsString(jsonEncode({
      'result':'PASS','companyId':user.companyId,'userId':user.id,'requestId':id,
      'originalIncidents':before.length,'retainedIncidents':after.length,'editableDraftVisible':true,
      'originalAttemptStillPending':true,'financialPostPerformed':false,
    }));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
