import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_dock_button.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'preview-user',
        email: 'preview@example.test',
        nombreCompleto: 'Preview',
        telefono: '',
        role: 'ADMIN',
        companyId: 'preview-company',
      ),
    );
  }
}

void main() {
  testWidgets(
    'native phones keep global AI hidden across routes while Windows retains it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('Inicio')),
          ),
          GoRoute(
            path: '/cotizaciones',
            builder: (_, __) => const Scaffold(body: Text('Facturación')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith(_SignedIn.new),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (_, child) => GlobalAiAssistantEntryPoint(child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dock = defaultTargetPlatform == TargetPlatform.windows ? findsOneWidget : findsNothing;
      expect(find.byType(AiAssistantDockButton), dock);
      router.go('/cotizaciones');
      await tester.pumpAndSettle();
      expect(find.text('Facturación'), findsOneWidget);
      expect(find.byType(AiAssistantDockButton), dock);
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.byType(AiAssistantDockButton), dock);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );
}
