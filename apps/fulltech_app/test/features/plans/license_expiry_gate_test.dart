import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daleventa_pos/core/license/license_repository.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/plans/presentation/plans_open_provider.dart';
import 'package:daleventa_pos/features/plans/presentation/widgets/license_expiry_gate.dart';

/// La pantalla de trabajo que queda **detras** del cuadro.
class _FakePos extends StatelessWidget {
  const _FakePos();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Punto de venta')),
    );
  }
}

LicenseStatusModel _expired({String? evidenceReference}) {
  return LicenseStatusModel(
    companyId: 'company-1',
    companyName: 'Comercial Demo SRL',
    plan: 'ENTERPRISE',
    planCode: 'empresa',
    status: 'EXPIRED',
    isUsable: false,
    maxUsers: 7,
    maxProducts: 5000,
    maxWarehouses: 10,
    users: 3,
    products: 320,
    daysRemaining: -7,
    periodEndsAtOverride: DateTime(2026, 11, 10),
    access: LicenseAccessInfo(
      level: 'RESTRICTED',
      reason: 'EXPIRED',
      daysRemaining: -7,
      periodEndsAt: DateTime(2026, 11, 10),
      effectiveStatus: 'EXPIRED',
    ),
    renewal: RenewalInfo(
      state: evidenceReference == null ? 'OVERDUE' : 'IN_REVIEW',
      dueDate: DateTime(2026, 11, 10),
      daysLeft: -7,
      amount: 5000,
      currency: 'DOP',
      planCode: 'empresa',
      planName: 'FullPOS Empresa',
      order: evidenceReference == null
          ? null
          : RenewalOrderInfo(
              id: 'order-1',
              reference: evidenceReference,
              amount: 5000,
              currency: 'DOP',
              status: 'UNCONFIRMED',
              months: 1,
            ),
    ),
  );
}

LicenseStatusModel _active() {
  return LicenseStatusModel(
    companyId: 'company-1',
    companyName: 'Comercial Demo SRL',
    plan: 'ENTERPRISE',
    planCode: 'empresa',
    status: 'ACTIVE',
    isUsable: true,
    maxUsers: 7,
    maxProducts: 5000,
    maxWarehouses: 10,
    users: 3,
    products: 320,
    daysRemaining: 20,
    periodEndsAtOverride: DateTime(2026, 12, 7),
    access: const LicenseAccessInfo(level: 'FULL', reason: 'ACTIVE'),
  );
}

LicenseStatusModel _blocked() {
  return LicenseStatusModel(
    companyId: 'company-1',
    companyName: 'Comercial Demo SRL',
    plan: 'ENTERPRISE',
    planCode: 'empresa',
    status: 'SUSPENDED',
    isUsable: false,
    maxUsers: 7,
    maxProducts: 5000,
    maxWarehouses: 10,
    users: 3,
    products: 320,
    licenseBlockedAt: DateTime(2026, 11, 16),
    access: const LicenseAccessInfo(
      level: 'BLOCKED',
      reason: 'COMPANY_INACTIVE',
    ),
    renewal: RenewalInfo(
      state: 'OVERDUE',
      dueDate: DateTime(2026, 11, 10),
      daysLeft: -7,
      amount: 5000,
      currency: 'DOP',
      planCode: 'empresa',
      planName: 'FullPOS Empresa',
    ),
  );
}

LicenseStatusModel _trialEnded() {
  return LicenseStatusModel(
    companyId: 'company-1',
    companyName: 'Comercial Demo SRL',
    plan: 'STANDARD',
    status: 'EXPIRED',
    isUsable: false,
    maxUsers: 2,
    maxProducts: 100,
    users: 1,
    products: 37,
    trialStartedAt: DateTime(2026, 11, 5),
    trialEndsAt: DateTime(2026, 11, 12),
    daysRemaining: -6,
    access: LicenseAccessInfo(
      level: 'RESTRICTED',
      reason: 'TRIAL_EXPIRED',
      daysRemaining: -6,
      periodEndsAt: DateTime(2026, 11, 12),
      effectiveStatus: 'EXPIRED',
    ),
    // La prueba no tiene plan contratado: la cuota esta al dia y sin importe.
    renewal: const RenewalInfo(state: 'CURRENT'),
  );
}

Widget _app({required LicenseStatusModel license}) {
  final router = GoRouter(
    initialLocation: '/trabajo',
    routes: [
      GoRoute(
        path: '/trabajo',
        builder: (context, state) =>
            LicenseExpiryGate(child: const _FakePos()),
      ),
      // Los mismos destinos que usa el cuadro, sin construir la pantalla real:
      // lo que se comprueba aqui es **a donde** lleva cada boton.
      GoRoute(
        path: Routes.planesPago,
        builder: (context, state) =>
            Text('PAGO ${state.uri}'),
      ),
      GoRoute(
        path: Routes.planesCatalogo,
        builder: (context, state) =>
            Text('CATALOGO ${state.uri}'),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      licenseStatusProvider.overrideWith((ref) async => license),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  testWidgets('con la licencia vencida el cuadro se pinta encima del POS',
      (tester) async {
    await tester.pumpWidget(_app(license: _expired()));
    await tester.pumpAndSettle();

    expect(find.text('PLAN VENCIDO'), findsOneWidget);
    expect(find.text('Tu plan FullPOS Empresa venció'), findsOneWidget);
    expect(find.textContaining('hace 7 días'), findsOneWidget);
    expect(find.text('RD\$5,000.00'), findsOneWidget);
    expect(find.text('REALIZAR PAGO'), findsOneWidget);
    expect(find.text('MEJORAR MI PLAN'), findsOneWidget);
    // El POS sigue debajo: el cliente ve su pantalla de trabajo.
    expect(find.text('Punto de venta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con la licencia al dia no se tapa el punto de venta',
      (tester) async {
    await tester.pumpWidget(_app(license: _active()));
    await tester.pumpAndSettle();

    expect(find.text('PLAN VENCIDO'), findsNothing);
    expect(find.text('Punto de venta'), findsOneWidget);
  });

  testWidgets('REALIZAR PAGO abre la pantalla de transferencia en modo pago',
      (tester) async {
    await tester.pumpWidget(_app(license: _expired()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('REALIZAR PAGO'));
    await tester.pumpAndSettle();

    expect(find.text('PAGO /planes/pago?paso=pagar'), findsOneWidget);
  });

  testWidgets('MEJORAR MI PLAN abre el catalogo de planes superiores',
      (tester) async {
    await tester.pumpWidget(_app(license: _expired()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('MEJORAR MI PLAN'));
    await tester.pumpAndSettle();

    expect(find.text('CATALOGO /planes/catalogo?superiores=1'), findsOneWidget);
  });

  testWidgets('con una pantalla de Planes abierta la capa se aparta y vuelve'
      ' al cerrarse', (tester) async {
    await tester.pumpWidget(_app(license: _expired()));
    await tester.pumpAndSettle();
    expect(find.text('PLAN VENCIDO'), findsOneWidget);

    // Es lo que hace `PlansShell` al montarse y al cerrarse.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(LicenseExpiryGate)),
    );
    container.read(plansOpenCountProvider.notifier).state = 1;
    await tester.pumpAndSettle();
    expect(find.text('PLAN VENCIDO'), findsNothing);
    expect(find.text('Punto de venta'), findsOneWidget);

    container.read(plansOpenCountProvider.notifier).state = 0;
    await tester.pumpAndSettle();
    expect(find.text('PLAN VENCIDO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con la cuenta suspendida se pinta el aviso de suspension',
      (tester) async {
    await tester.pumpWidget(_app(license: _blocked()));
    await tester.pumpAndSettle();

    expect(find.text('CUENTA SUSPENDIDA'), findsOneWidget);
    expect(find.text('Tu cuenta está suspendida'), findsOneWidget);
    expect(find.text('Falta de pago de tu plan.'), findsOneWidget);
    expect(find.text('REALIZAR PAGO'), findsOneWidget);
    expect(find.text('HABLAR CON SOPORTE'), findsOneWidget);
    // No se confunde con el aviso de plan vencido.
    expect(find.text('PLAN VENCIDO'), findsNothing);

    await tester.tap(find.text('REALIZAR PAGO'));
    await tester.pumpAndSettle();
    expect(find.text('PAGO /planes/pago?paso=pagar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un comprobante en revision se ve y no se pide otra vez',
      (tester) async {
    await tester.pumpWidget(
      _app(license: _expired(evidenceReference: 'FP-2026-000777')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comprobante en revisión'), findsOneWidget);
    expect(
      find.textContaining('Ref. FP-2026-000777'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No hace falta subirlo otra vez'),
      findsOneWidget,
    );
  });

  testWidgets('con la demo terminada se ofrece elegir plan, no pagar un plan',
      (tester) async {
    await tester.pumpWidget(_app(license: _trialEnded()));
    await tester.pumpAndSettle();

    expect(find.text('DEMO FINALIZADA'), findsOneWidget);
    expect(find.text('Tu demo de 7 días terminó'), findsOneWidget);
    expect(find.textContaining('El 12/11/2026'), findsOneWidget);
    expect(find.text('VER PLANES'), findsOneWidget);
    // La prueba no tiene plan pagado: ni «plan vencido» ni importes.
    expect(find.text('PLAN VENCIDO'), findsNothing);
    expect(find.text('MEJORAR MI PLAN'), findsNothing);
    expect(find.text('REALIZAR PAGO'), findsNothing);
    expect(find.textContaining('RD\$'), findsNothing);

    await tester.tap(find.text('VER PLANES'));
    await tester.pumpAndSettle();
    // Catalogo completo, sin `superiores=1`: puede elegir cualquier plan.
    expect(find.text('CATALOGO /planes/catalogo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda en un telefono de 390x844', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(license: _expired()));
    await tester.pumpAndSettle();

    expect(find.text('PLAN VENCIDO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin fecha ni importe del servidor no se inventa una cifra',
      (tester) async {
    final sinDatos = LicenseStatusModel(
      companyId: 'company-1',
      companyName: 'Comercial Demo SRL',
      plan: 'STANDARD',
      status: 'EXPIRED',
      isUsable: false,
      maxUsers: 2,
      maxProducts: 100,
      users: 1,
      products: 10,
      access: const LicenseAccessInfo(level: 'RESTRICTED', reason: 'EXPIRED'),
    );

    await tester.pumpWidget(_app(license: sinDatos));
    await tester.pumpAndSettle();

    expect(find.text('PLAN VENCIDO'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Importe pendiente del plan actual'), findsOneWidget);
  });

  testWidgets('el cuadro no deja operar el punto de venta de detras',
      (tester) async {
    var cobros = 0;
    final router = GoRouter(
      initialLocation: '/trabajo',
      routes: [
        GoRoute(
          path: '/trabajo',
          builder: (context, state) => LicenseExpiryGate(
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => cobros++,
                  child: const Text('COBRAR'),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          licenseStatusProvider.overrideWith((ref) async => _expired()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Fuera de la tarjeta: la capa tiene que comerse la pulsacion.
    await tester.tapAt(const Offset(30, 30));
    await tester.pumpAndSettle();
    expect(cobros, 0);
    expect(find.text('PLAN VENCIDO'), findsOneWidget);
  });
}
