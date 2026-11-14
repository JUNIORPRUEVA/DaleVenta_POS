import 'dart:io';
import 'dart:ui' as ui;
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_production_activation_action.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthController {
  _Auth(super.ref, String role) {
    state = AuthState(initialized: true, isAuthenticated: true,
      user: UserModel.fromJson({'id':'actor','companyId':'company','email':'fixture@test.invalid','role':role}));
  }
}
class _Repo extends EcfRepository {
  _Repo() : super(Dio());
  bool available=true;
  int calls=0;
  @override
  Future<EcfCapabilities> capabilities() async => EcfCapabilities.fromJson({
    'enabled':true,'environment':'SANDBOX','certificationStatus':'PRODUCTION_READY','canActivateProduction':available});
  @override
  Future<void> enableProduction({required String expectedCompanyId}) async {
    expect(expectedCompanyId, 'company');
    calls++; available=false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader=FontLoader('Manrope');
    for(final weight in ['Regular','Medium','SemiBold','Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await loader.load();
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(()=>SharedPreferences.setMockInitialValues({}));
  tearDown(AppFeedback.clearToasts);
  final capture=GlobalKey();
  Future<void> pump(WidgetTester tester,_Repo repo,{double width=320,String role='ADMIN'}) async {
    tester.view.physicalSize=Size(width,850);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides:[
      authStateProvider.overrideWith((ref)=>_Auth(ref,role)), ecfRepositoryProvider.overrideWithValue(repo)],
      child:RepaintBoundary(key:capture,child:MaterialApp(debugShowCheckedModeBanner:false,theme:AppTheme.light,
        home:const Scaffold(body:Padding(padding:EdgeInsets.all(12),child:EcfProductionActivationAction()))))));
    await tester.pumpAndSettle();
  }
  for(final width in [320.0,1280.0]) {
    testWidgets('certified company activation requires confirmation at $width',(tester) async {
      final repo=_Repo();await pump(tester,repo,width:width);
      await tester.tap(find.text('Habilitar producción'));await tester.pumpAndSettle();
      expect(repo.calls,0);expect(tester.takeException(),isNull);
      final output=Platform.environment['FULLPOS_ECF_NORMAL_QA'];
      if(output!=null) {
        final boundary=capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final picture=await boundary.toImage();final bytes=await picture.toByteData(format:ui.ImageByteFormat.png);
          await Directory(output).create(recursive:true);
          await File('$output/production-confirm-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());picture.dispose();
        });
      }
      await tester.tap(find.text('Habilitar'));await tester.pumpAndSettle();
      expect(repo.calls,1);expect(find.text('Habilitar producción'),findsNothing);
      await tester.pump(const Duration(seconds:5));
    });
  }
  testWidgets('server-disabled or unprivileged users cannot see activation',(tester) async {
    await pump(tester,_Repo()..available=false);
    expect(find.text('Habilitar producción'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pump(tester,_Repo(),role:'CASHIER');
    expect(find.text('Habilitar producción'),findsNothing);
  });
}
