import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/config/product_config.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/auth/presentation/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailedLogin extends AuthController {
  _FailedLogin(super.ref, this.type) {
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      loading: false,
    );
  }
  final ApiErrorType type;
  @override
  Future<UserModel?> login(String email, String password) async {
    throw ApiException.detailed(message: 'Test failure', type: type);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AppFeedback.dismissPersistentNotification);

  Future<void> pumpLogin(
    WidgetTester tester,
    ApiErrorType type,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => _FailedLogin(ref, type)),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final type in [
    ApiErrorType.unauthorized,
    ApiErrorType.noInternet,
    ApiErrorType.server,
  ]) {
    testWidgets(
      '$type appears once outside the form without moving the button',
      (tester) async {
        await pumpLogin(tester, type, const Size(1280, 900));
        await tester.enterText(
          find.byType(TextFormField).first,
          'test@example.com',
        );
        await tester.enterText(
          find.byType(TextFormField).last,
          'test-password',
        );
        final before = tester.getRect(find.text('Iniciar sesión'));
        await tester.tap(find.text('Iniciar sesión'));
        await tester.pumpAndSettle();
        final notice = find.byKey(const ValueKey('persistent_feedback_card'));
        expect(notice, findsOneWidget);
        expect(
          find.descendant(of: find.byType(Form), matching: notice),
          findsNothing,
        );
        expect(tester.getRect(find.text('Iniciar sesión')), before);
        expect(tester.getTopLeft(notice).dx, greaterThan(800));
        expect(tester.getTopLeft(notice).dy, lessThan(40));
        await tester.enterText(
          find.byType(TextFormField).first,
          'other@example.com',
        );
        await tester.pump();
        expect(notice, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'small-screen validation uses a dismissible paragraph above the form',
    (tester) async {
      await pumpLogin(tester, ApiErrorType.unauthorized, const Size(320, 640));
      await tester.tap(find.text('Iniciar sesión'));
      await tester.pumpAndSettle();
      final notice = find.byKey(const ValueKey('persistent_feedback_card'));
      expect(notice, findsOneWidget);
      expect(tester.getRect(notice).right, lessThanOrEqualTo(320));
      expect(
        tester.getRect(notice).bottom,
        lessThan(tester.getTopLeft(find.byType(Form)).dy),
      );
      await tester.tap(
        find.descendant(of: notice, matching: find.byType(IconButton)),
      );
      await tester.pumpAndSettle();
      expect(notice, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop create account opens the official web form externally',
    (tester) async {
      MethodCall? launch;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            launch = call;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await pumpLogin(tester, ApiErrorType.unauthorized, const Size(1280, 900));
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      expect(launch?.method, 'launch');
      final args = launch!.arguments as Map;
      expect(args['url'], ProductConfig.productionRegistrationUrl);
      expect(args['useWebView'], false);
      expect(args['useSafariVC'], false);
      expect(find.text('Crear mi empresa'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
