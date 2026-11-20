import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/license/license_repository.dart';
import 'package:daleventa_pos/features/plans/presentation/plans_open_provider.dart';
import 'package:daleventa_pos/features/plans/presentation/widgets/license_expiry_gate.dart';

/// Activación al instante: al volver de Planes se vuelve a pedir la licencia y,
/// si el cliente acaba de pagar, el cuadro desaparece **sin reiniciar la app**.
///
/// La prueba simula el servidor: la primera consulta devuelve la cuenta
/// suspendida y las siguientes, la cuenta reactivada. No se inventa nada en la
/// interfaz; lo que se comprueba es que la capa **vuelve a preguntar**.
LicenseStatusModel _status({required bool blocked}) {
  return LicenseStatusModel(
    companyId: 'company-1',
    companyName: 'Comercial Demo SRL',
    plan: 'ENTERPRISE',
    planCode: 'empresa',
    status: blocked ? 'SUSPENDED' : 'ACTIVE',
    isUsable: !blocked,
    maxUsers: 7,
    maxProducts: 5000,
    maxWarehouses: 10,
    users: 3,
    products: 320,
    licenseBlockedAt: blocked ? DateTime(2026, 11, 16) : null,
    access: blocked
        ? const LicenseAccessInfo(
            level: 'BLOCKED',
            reason: 'COMPANY_INACTIVE',
          )
        : const LicenseAccessInfo(level: 'FULL', reason: 'ACTIVE'),
    renewal: blocked
        ? RenewalInfo(
            state: 'OVERDUE',
            dueDate: DateTime(2026, 11, 10),
            daysLeft: -7,
            amount: 5000,
            currency: 'DOP',
            planCode: 'empresa',
            planName: 'FullPOS Empresa',
          )
        : null,
  );
}

void main() {
  testWidgets('al volver de Planes se consulta otra vez y el aviso se retira',
      (tester) async {
    var consultas = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          licenseStatusProvider.overrideWith((ref) async {
            consultas += 1;
            return _status(blocked: consultas == 1);
          }),
        ],
        child: const MaterialApp(
          home: LicenseExpiryGate(
            child: Scaffold(body: Center(child: Text('Punto de venta'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Cuenta suspendida: el aviso tapa el punto de venta.
    expect(consultas, 1);
    expect(find.text('CUENTA SUSPENDIDA'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LicenseExpiryGate)),
    );

    // 2. El cliente entra a Planes (como avisa `PlansShell`).
    container.read(plansOpenCountProvider.notifier).state = 1;
    await tester.pumpAndSettle();
    expect(find.text('CUENTA SUSPENDIDA'), findsNothing);

    // 3. Vuelve a la app: se pregunta de nuevo al servidor.
    container.read(plansOpenCountProvider.notifier).state = 0;
    await tester.pumpAndSettle();

    expect(consultas, 2);
    expect(find.text('CUENTA SUSPENDIDA'), findsNothing);
    expect(find.text('Punto de venta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('si sigue suspendida el aviso vuelve a pintarse', (tester) async {
    var consultas = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          licenseStatusProvider.overrideWith((ref) async {
            consultas += 1;
            return _status(blocked: true);
          }),
        ],
        child: const MaterialApp(
          home: LicenseExpiryGate(
            child: Scaffold(body: Center(child: Text('Punto de venta'))),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('CUENTA SUSPENDIDA'), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LicenseExpiryGate)),
    );
    container.read(plansOpenCountProvider.notifier).state = 1;
    await tester.pumpAndSettle();
    expect(find.text('CUENTA SUSPENDIDA'), findsNothing);

    container.read(plansOpenCountProvider.notifier).state = 0;
    await tester.pumpAndSettle();

    expect(consultas, 2);
    expect(find.text('CUENTA SUSPENDIDA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
