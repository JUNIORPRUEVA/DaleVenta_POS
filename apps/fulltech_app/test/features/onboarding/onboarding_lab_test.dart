import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/onboarding/lab/lab_onboarding_repository.dart';
import 'package:daleventa_pos/features/onboarding/lab/onboarding_lab_access.dart';
import 'package:daleventa_pos/features/onboarding/presentation/onboarding_lab_screen.dart';

void main() {
  UserModel user(String email, {String? companyName, String? companySlug}) {
    return UserModel(
      id: 'user-1',
      email: email,
      nombreCompleto: 'Usuario Lab',
      telefono: '',
      companyName: companyName,
      companySlug: companySlug,
    );
  }

  group('onboarding lab access', () {
    test('allows only the configured email when the flag is enabled', () {
      expect(
        canAccessOnboardingLab(user('  PRUEVA7@gmail.com  '), enabled: true),
        isTrue,
      );
      expect(
        canAccessOnboardingLab(user('cliente@example.com'), enabled: true),
        isFalse,
      );
      expect(
        canAccessOnboardingLab(
          user(onboardingLabAuthorizedEmail),
          enabled: false,
        ),
        isFalse,
      );
      expect(canAccessOnboardingLab(null, enabled: true), isFalse);
    });

    test('also allows the prueva7 company in local lab builds', () {
      expect(
        canAccessOnboardingLab(
          user('admin@example.com', companyName: 'prueva7'),
          enabled: true,
        ),
        isTrue,
      );
      expect(
        canAccessOnboardingLab(
          user('admin@example.com', companySlug: 'prueva7'),
          enabled: true,
        ),
        isTrue,
      );
    });
  });

  group('lab onboarding repository', () {
    test('keeps the simulated flow in memory', () async {
      final controller = LabOnboardingController();
      final repository = LabOnboardingRepository(controller);

      final initial = await repository.getState();
      expect(initial.status, 'WELCOME_PENDING');
      expect(initial.shouldShowWelcome, isTrue);
      expect(initial.steps['company'], 'PENDING');

      final started = await repository.start();
      expect(started.status, 'IN_PROGRESS');
      expect(started.shouldShowWelcome, isFalse);

      final companyDone = await repository.setStep('company', 'COMPLETED');
      expect(companyDone.steps['company'], 'COMPLETED');
      expect(companyDone.productCount, 0);

      final productDone = await repository.setStep('product', 'COMPLETED');
      expect(productDone.steps['product'], 'COMPLETED');
      expect(productDone.productCount, 1);

      final tutorialDone = await repository.setTutorial('COMPLETED');
      expect(tutorialDone.tutorialStatus, 'COMPLETED');

      controller.reset(entry: LabOnboardingEntryPoint.billing);
      final billing = await repository.getState();
      expect(billing.steps['company'], 'COMPLETED');
      expect(billing.steps['billing'], 'PENDING');
      expect(billing.shouldShowWelcome, isFalse);
    });
  });

  group('onboarding lab screen', () {
    testWidgets('double tap starts the company guide only once', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingLabScreen()));

      final start = find.text('Comenzar configuración');
      expect(start, findsOneWidget);

      await tester.tap(start);
      await tester.tap(start);
      await tester.pumpAndSettle();

      expect(find.text('Configura tu empresa'), findsOneWidget);
      expect(find.text('Guía de empresa · 1 de 3'), findsOneWidget);
      expect(find.text('Guía de empresa · 2 de 3'), findsNothing);
    });

    testWidgets('repeated next click advances one step per frame', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingLabScreen()));
      await tester.tap(find.text('Comenzar configuración'));
      await tester.pumpAndSettle();

      final next = find.text('Siguiente');
      await tester.tap(next);
      await tester.tap(next);
      await tester.tap(next);
      await tester.pumpAndSettle();

      expect(find.text('Guía de empresa · 2 de 3'), findsOneWidget);
      expect(find.text('Guía de empresa · 3 de 3'), findsNothing);

      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Guía de empresa · 3 de 3'), findsOneWidget);
    });

    testWidgets('visible lab UI is in Spanish and has one guide overlay', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: OnboardingLabScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Onboarding'), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.text('Laboratorio de configuración'), findsOneWidget);

      await tester.tap(find.text('Comenzar configuración'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Onboarding'), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.textContaining('Guía de empresa'), findsOneWidget);
    });
  });
}
