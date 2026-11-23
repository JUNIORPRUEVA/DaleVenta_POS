import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NoLocalAccess extends AuthController {
  NoLocalAccess(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      loading: false,
    );
  }
  @override
  Future<UserModel?> login(String email, String password) async {
    throw const ApiException.detailed(
      message: 'Necesitas conexión para iniciar sesión en este equipo.',
      type: ApiErrorType.noInternet,
      displayCode: 'LOCAL_LOGIN_UNAVAILABLE',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    const aliases = {
      'regular': 'Regular',
      '500': 'Medium',
      '600': 'SemiBold',
      '700': 'Bold',
    };
    for (final entry in aliases.entries) {
      final alias = FontLoader('Manrope_${entry.key}')
        ..addFont(
          rootBundle.load('assets/fonts/manrope/Manrope-${entry.value}.ttf'),
        );
      await alias.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AppFeedback.dismissPersistentNotification);
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'accurate offline access notice on ${platform.name}',
      (tester) async {
        final desktop = platform == TargetPlatform.windows;
        tester.view.physicalSize = desktop
            ? const Size(1280, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ProviderScope(
              overrides: [
                authStateProvider.overrideWith((ref) => NoLocalAccess(ref)),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                home: const LoginScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).first,
          'demo@example.test',
        );
        await tester.enterText(
          find.byType(TextFormField).last,
          'fixture-local-access',
        );
        await tester.tap(find.text('Iniciar sesión'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Puedes vender 48', findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining(
            'Necesitas conexión para iniciar sesión en este equipo.',
            findRichText: true,
          ),
          findsOneWidget,
        );
        final notice = find.byKey(const ValueKey('persistent_feedback_card'));
        expect(notice, findsOneWidget);
        expect(
          find.descendant(of: find.byType(Form), matching: notice),
          findsNothing,
        );
        expect(
          tester.getRect(notice).right,
          lessThanOrEqualTo(tester.view.physicalSize.width),
        );
        expect(tester.takeException(), isNull);
        const output = String.fromEnvironment('EVIDENCE_DIR');
        if (output.isNotEmpty) {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final dir = Directory(output);
            await dir.create(recursive: true);
            await File(
              '${dir.path}/login-offline-${platform.name}.png',
            ).writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
