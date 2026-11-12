import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/onboarding/presentation/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Carga la tipografía real de la app para que las capturas no salgan con la
/// fuente de prueba (bloques negros).
Future<void> _loadManrope() async {
  final loader = FontLoader('Manrope');
  for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
  }
  await loader.load();
}

Future<void> _pumpWelcome(
  WidgetTester tester,
  Size size, {
  DateTime? trialEndsAt,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: OnboardingWelcomePreview(trialEndsAt: trialEndsAt),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadManrope);

  testWidgets('bienvenida escritorio 1280x800', (tester) async {
    await _pumpWelcome(
      tester,
      const Size(1280, 800),
      trialEndsAt: DateTime(2026, 11, 25),
    );

    expect(find.text('Tu cuenta está lista'), findsOneWidget);
    expect(find.text('Comenzar configuración'), findsOneWidget);
    expect(find.text('Omitir configuración'), findsOneWidget);
    expect(find.text('Prepara tu negocio sin perder ritmo'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(OnboardingWelcomePreview),
      matchesGoldenFile('goldens/welcome_desktop_1280x800.png'),
    );
  });

  testWidgets('bienvenida tableta 834x1112', (tester) async {
    await _pumpWelcome(tester, const Size(834, 1112));

    expect(find.text('Tu cuenta está lista'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(OnboardingWelcomePreview),
      matchesGoldenFile('goldens/welcome_tablet_834x1112.png'),
    );
  });

  testWidgets('bienvenida teléfono 390x844', (tester) async {
    await _pumpWelcome(tester, const Size(390, 844));

    expect(find.text('Tu cuenta está lista'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(OnboardingWelcomePreview),
      matchesGoldenFile('goldens/welcome_phone_390x844.png'),
    );
  });
}
