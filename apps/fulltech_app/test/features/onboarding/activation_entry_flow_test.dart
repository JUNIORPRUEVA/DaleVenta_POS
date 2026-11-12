import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/onboarding/application/activation_controller.dart';
import 'package:daleventa_pos/features/onboarding/data/activation_models.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_entry_point.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_panel.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_welcome_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'activation-qa',
        email: 'qa@example.invalid',
        nombreCompleto: 'QA',
        telefono: '',
        role: 'ADMIN',
        companyId: 'activation-company',
        companyName: 'Mi negocio',
        requiresOnboarding: true,
      ),
    );
  }
}

ActivationState _fixture({bool seen = false, bool dismissed = false}) =>
    ActivationState.fromJson({
      'companyId': 'activation-company',
      'required': true,
      'welcomeSeen': seen,
      'dismissed': dismissed,
      'allResolved': false,
      'progress': {
        'total': 7,
        'done': 2,
        'skipped': 0,
        'pending': 5,
        'percent': 29,
      },
      'tasks': [
        for (final key in [
          'account',
          'products',
          'firstSale',
          'business',
          'taxes',
          'tickets',
          'ecf',
        ])
          {
            'key': key,
            'title': key == 'products' ? 'Tu primer producto' : key,
            'state': ['account', 'business'].contains(key) ? 'DONE' : 'PENDING',
            'optional': key != 'account',
            'destination': key == 'products' ? 'catalog' : 'company',
          },
      ],
    });

class _Activation extends ActivationController {
  bool seen = false;
  bool dismissed = false;
  @override
  Future<ActivationState?> build() async => _fixture();
  @override
  Future<void> markWelcomeSeen() async {
    seen = true;
    state = AsyncValue.data(_fixture(seen: seen, dismissed: dismissed));
  }

  @override
  Future<void> dismiss() async {
    dismissed = true;
    state = AsyncValue.data(_fixture(seen: seen, dismissed: dismissed));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['FULLPOS_VISUAL_EVIDENCE_DIR'];
  if (folder == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final target = File('$folder/$name.png');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final fonts = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(
        rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'),
      );
    }
    await fonts.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('bienvenida nueva y panel secuenciales en ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => _Auth(ref)),
            activationControllerProvider.overrideWith(_Activation.new),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: const Scaffold(
                body: ActivationEntryPoint(child: Center(child: Text('POS'))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ActivationWelcomeCard), findsOneWidget);
      expect(find.byType(ActivationPanel), findsNothing);
      expect(find.textContaining('3 pasos cortos'), findsOneWidget);
      await _capture(tester, 'welcome-${size.width.toInt()}');
      await tester.tap(find.text('¡Comencemos!'));
      await tester.pumpAndSettle();
      expect(find.byType(ActivationWelcomeCard), findsNothing);
      expect(find.byType(ActivationPanel), findsOneWidget);
      expect(find.text('Datos de tu negocio'), findsNothing);
      expect(find.text('Completa los datos de tu empresa'), findsOneWidget);
      await _capture(tester, 'activation-${size.width.toInt()}');
    });
  }
}
