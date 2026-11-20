import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/license/license_demo_state.dart';
import 'package:daleventa_pos/core/license/license_repository.dart';
import 'package:daleventa_pos/features/plans/presentation/widgets/license_expiry_gate.dart';

/// Empresa ficticia tal como la interpreta el modelo real de la API.
LicenseStatusModel _license(LicenseDemoScenario scenario) =>
    LicenseStatusModel.fromJson(demoLicenseJson(scenario));

Widget _app({
  required LicenseDemoScenario scenario,
  LicenseStatusModel? serverLicense,
}) {
  return ProviderScope(
    overrides: [
      licenseDemoScenarioProvider.overrideWith((ref) => scenario),
      // Con la simulacion apagada el cuadro consultaria la API de verdad: se
      // sustituye por una licencia ya resuelta para no dejar llamadas abiertas.
      if (serverLicense != null)
        licenseStatusProvider.overrideWith((ref) async => serverLicense),
    ],
    child: const MaterialApp(
      home: LicenseExpiryGate(child: Scaffold(body: Text('Punto de venta'))),
    ),
  );
}

void main() {
  group('escenarios simulados', () {
    test('sin valor o con un valor desconocido no se simula nada', () {
      expect(LicenseDemoScenario.fromRaw(''), LicenseDemoScenario.off);
      expect(LicenseDemoScenario.fromRaw('LO_QUE_SEA'), LicenseDemoScenario.off);
      expect(LicenseDemoScenario.fromRaw(''), LicenseDemoScenario.off);
    });

    test('se aceptan los nombres documentados', () {
      expect(LicenseDemoScenario.fromRaw('OVERDUE'), LicenseDemoScenario.overdue);
      expect(LicenseDemoScenario.fromRaw('vencida'), LicenseDemoScenario.overdue);
      expect(
        LicenseDemoScenario.fromRaw('IN_REVIEW'),
        LicenseDemoScenario.inReview,
      );
      expect(LicenseDemoScenario.fromRaw('ACTIVE'), LicenseDemoScenario.active);
      expect(LicenseDemoScenario.fromRaw('BLOCKED'), LicenseDemoScenario.blocked);
      expect(
        LicenseDemoScenario.fromRaw('suspendida'),
        LicenseDemoScenario.blocked,
      );
      expect(
        LicenseDemoScenario.fromRaw('BLOCKED_OTHER'),
        LicenseDemoScenario.blockedOther,
      );
      expect(
        LicenseDemoScenario.fromRaw('suspendida_otra'),
        LicenseDemoScenario.blockedOther,
      );
    });

    test('la demo terminada se reconoce por varios nombres', () {
      expect(
        LicenseDemoScenario.fromRaw('TRIAL_EXPIRED'),
        LicenseDemoScenario.trialEnded,
      );
      expect(
        LicenseDemoScenario.fromRaw('demo_finalizada'),
        LicenseDemoScenario.trialEnded,
      );
    });

    test('demo terminada: restringida por fin de prueba y sin deuda', () {
      final license = _license(LicenseDemoScenario.trialEnded);

      expect(license.access?.level, 'RESTRICTED');
      expect(license.access?.reason, 'TRIAL_EXPIRED');
      // Es una licencia restringida, pero no de un plan: tiene su pantalla.
      expect(license.isLicenseExpired, isTrue);
      expect(license.isTrialExpired, isTrue);
      expect(license.trialEndsAt, isNotNull);
      expect(license.licenseActivatedAt, isNull);
      expect(license.renewal?.amount, isNull);
      expect(license.renewal?.isOverdue, isFalse);
    });

    test('un plan pagado y vencido no se confunde con la demo', () {
      final license = _license(LicenseDemoScenario.overdue);

      expect(license.isLicenseExpired, isTrue);
      expect(license.isTrialExpired, isFalse);
    });

    test('suspendida por falta de pago: bloqueada, con cuota vencida', () {
      final license = _license(LicenseDemoScenario.blocked);

      expect(license.access?.level, 'BLOCKED');
      // Una cuenta bloqueada no es «vencida»: tiene su propia pantalla.
      expect(license.isLicenseExpired, isFalse);
      expect(license.blockReason, contains('Falta de pago'));
      expect(license.renewal?.isOverdue, isTrue);
      expect(license.renewal?.amount, 5000);
    });

    test('suspendida por otra causa: bloqueada pero sin deuda', () {
      final license = _license(LicenseDemoScenario.blockedOther);

      expect(license.access?.level, 'BLOCKED');
      expect(license.blockReason, contains('uso indebido'));
      expect(license.renewal?.isOverdue, isFalse);
      expect(license.renewal?.isUpcoming, isFalse);
    });

    test('vencida: acceso restringido, importe real y 7 dias de mora', () {
      final license = _license(LicenseDemoScenario.overdue);

      expect(license.companyName, 'Comercial Demo SRL');
      expect(license.isLicenseExpired, isTrue);
      expect(license.access?.level, 'RESTRICTED');
      expect(license.access?.reason, 'EXPIRED');
      expect(license.renewal?.state, 'OVERDUE');
      expect(license.renewal?.amount, 5000);
      expect(license.renewal?.currency, 'DOP');
      expect(license.renewal?.planName, 'FullPOS Empresa');
      expect(license.access?.daysRemaining, -7);
    });

    test('al dia: no se considera vencida', () {
      final license = _license(LicenseDemoScenario.active);

      expect(license.isLicenseExpired, isFalse);
      expect(license.isUsable, isTrue);
      expect(license.access?.level, 'FULL');
      expect(license.renewal?.state, 'CURRENT');
    });

    test('comprobante en revision: vencida pero con referencia enviada', () {
      final license = _license(LicenseDemoScenario.inReview);

      expect(license.isLicenseExpired, isTrue);
      expect(license.renewal?.isInReview, isTrue);
      expect(license.renewal?.order?.reference, 'FP-2026-000777');
    });
  });

  group('cuadro con licencia simulada', () {
    testWidgets('la empresa simulada pinta el cuadro y la barra de demo',
        (tester) async {
      await tester.pumpWidget(_app(scenario: LicenseDemoScenario.overdue));
      await tester.pumpAndSettle();

      expect(find.text('PLAN VENCIDO'), findsOneWidget);
      expect(find.text('Tu plan FullPOS Empresa venció'), findsOneWidget);
      expect(find.text('RD\$5,000.00'), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      expect(find.text('Ver la app'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Ver la app» aparta el cuadro y deja recorrer el punto de venta',
        (tester) async {
      await tester.pumpWidget(_app(scenario: LicenseDemoScenario.overdue));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ver la app'));
      await tester.pumpAndSettle();

      expect(find.text('PLAN VENCIDO'), findsNothing);
      expect(find.text('Punto de venta'), findsOneWidget);
      expect(find.text('Volver al cuadro'), findsOneWidget);

      await tester.tap(find.text('Volver al cuadro'));
      await tester.pumpAndSettle();

      expect(find.text('PLAN VENCIDO'), findsOneWidget);
    });

    testWidgets('cambiar el escenario en caliente cambia la licencia que ve la app',
        (tester) async {
      await tester.pumpWidget(_app(scenario: LicenseDemoScenario.overdue));
      await tester.pumpAndSettle();
      expect(find.text('PLAN VENCIDO'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LicenseExpiryGate)),
      );
      container.read(licenseDemoScenarioProvider.notifier).state =
          LicenseDemoScenario.active;
      await tester.pumpAndSettle();

      expect(find.text('PLAN VENCIDO'), findsNothing);
      expect(find.text('Punto de venta'), findsOneWidget);
    });

    testWidgets('el menu de la barra permite pasar a comprobante en revision',
        (tester) async {
      await tester.pumpWidget(_app(scenario: LicenseDemoScenario.overdue));
      await tester.pumpAndSettle();
      expect(find.text('Comprobante en revisión'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprobante en revision').last);
      await tester.pumpAndSettle();

      expect(find.text('Comprobante en revisión'), findsOneWidget);
      expect(find.textContaining('Ref. FP-2026-000777'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el escenario de demo terminada pinta su propio cuadro',
        (tester) async {
      await tester.pumpWidget(_app(scenario: LicenseDemoScenario.trialEnded));
      await tester.pumpAndSettle();

      expect(find.text('DEMO FINALIZADA'), findsOneWidget);
      expect(find.text('Tu demo de 7 días terminó'), findsOneWidget);
      expect(find.text('VER PLANES'), findsOneWidget);
      // Se parece a la vencida, pero no lo es: no se habla de plan ni de importe.
      expect(find.text('PLAN VENCIDO'), findsNothing);
      expect(find.textContaining('RD\$'), findsNothing);
      expect(find.text('DEMO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin escenario no aparece nada de demostracion', (tester) async {
      await tester.pumpWidget(
        _app(
          scenario: LicenseDemoScenario.off,
          serverLicense: _license(LicenseDemoScenario.active),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLAN VENCIDO'), findsNothing);
      expect(find.text('DEMO'), findsNothing);
      expect(find.text('Punto de venta'), findsOneWidget);
    });
  });
}
