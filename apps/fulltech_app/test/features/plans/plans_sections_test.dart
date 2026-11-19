import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:daleventa_pos/core/license/license_repository.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/plans/data/plans_repository.dart';
import 'package:daleventa_pos/features/plans/presentation/screens/license_overview_screen.dart';
import 'package:daleventa_pos/features/plans/presentation/screens/orders_history_screen.dart';
import 'package:daleventa_pos/features/plans/presentation/screens/payment_screen.dart';
import 'package:daleventa_pos/features/plans/presentation/screens/plans_catalog_screen.dart';

PlanOffer _plan({
  required String code,
  required String name,
  required double price,
  required int users,
  required int products,
  required int warehouses,
  bool ecf = false,
  bool taxes = false,
  bool wholesale = false,
  bool multiWarehouse = false,
}) {
  return PlanOffer(
    code: code,
    name: name,
    version: 1,
    monthlyPrice: price,
    currency: 'DOP',
    maxUsers: users,
    maxProducts: products,
    maxWarehouses: warehouses,
    features: PlanFeatureFlags(
      multiWarehouse: multiWarehouse,
      wholesale: wholesale,
      uom: true,
      ecf: ecf,
      taxes: taxes,
    ),
    highlight: code == 'negocio',
  );
}

final _plans = <PlanOffer>[
  _plan(
    code: 'basico',
    name: 'FullPOS Básico',
    price: 1000,
    users: 1,
    products: 100,
    warehouses: 1,
  ),
  _plan(
    code: 'negocio',
    name: 'FullPOS Negocio',
    price: 2500,
    users: 3,
    products: 400,
    warehouses: 1,
    ecf: true,
    taxes: true,
    wholesale: true,
  ),
  _plan(
    code: 'pro',
    name: 'FullPOS Pro',
    price: 3500,
    users: 4,
    products: 1000,
    warehouses: 5,
    ecf: true,
    taxes: true,
    wholesale: true,
    multiWarehouse: true,
  ),
  _plan(
    code: 'empresa',
    name: 'FullPOS Empresa',
    price: 5000,
    users: 7,
    products: 5000,
    warehouses: 10,
    ecf: true,
    taxes: true,
    wholesale: true,
    multiWarehouse: true,
  ),
];

final _licenseActive = LicenseStatusModel(
  companyId: 'company-1',
  companyName: 'Colmado La Fe',
  plan: 'STANDARD',
  planCode: 'pro',
  status: 'ACTIVE',
  isUsable: true,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 2,
  products: 320,
  daysRemaining: 12,
  periodEndsAtOverride: DateTime(2026, 12, 1),
);

final _licenseSuspended = LicenseStatusModel(
  companyId: 'company-1',
  companyName: 'Colmado La Fe',
  plan: 'STANDARD',
  planCode: 'pro',
  status: 'EXPIRED',
  isUsable: false,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 2,
  products: 320,
  daysRemaining: -3,
  periodEndsAtOverride: DateTime(2026, 11, 13),
);

/// Cliente en la **prueba**: usable, pero sin plan contratado.
final _licenseTrial = LicenseStatusModel(
  companyId: 'company-1',
  companyName: 'Colmado La Fe',
  plan: 'TRIAL',
  planCode: 'pro',
  status: 'TRIAL',
  isUsable: true,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 2,
  products: 320,
  daysRemaining: 5,
  periodEndsAtOverride: DateTime(2026, 11, 24),
);

final _order = LicenseOrder(  id: 'order-1',
  planCode: 'pro',
  planName: 'FullPOS Pro',
  amount: 3500,
  currency: 'DOP',
  months: 1,
  status: 'AWAITING_TRANSFER',
  reference: 'FP-2026-000123',
  expiresAt: DateTime(2026, 11, 18),
);

/// Cuota proxima: faltan 9 dias, todavia **no** esta vencida.
final _licenseUpcoming = LicenseStatusModel(
  companyId: 'company-1',
  companyName: 'Colmado La Fe',
  plan: 'STANDARD',
  planCode: 'pro',
  status: 'ACTIVE',
  isUsable: true,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 2,
  products: 320,
  daysRemaining: 9,
  periodEndsAtOverride: DateTime(2026, 11, 26),
  renewal: RenewalInfo(
    state: 'UPCOMING',
    dueDate: DateTime(2026, 11, 26),
    daysLeft: 9,
    amount: 5000,
    currency: 'DOP',
    planCode: 'pro',
    planName: 'FullPOS Pro',
  ),
);

/// El cliente ya pago y espera verificacion.
final _licenseInReview = LicenseStatusModel(
  companyId: 'company-1',
  companyName: 'Colmado La Fe',
  plan: 'STANDARD',
  planCode: 'pro',
  status: 'ACTIVE',
  isUsable: true,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 2,
  products: 320,
  daysRemaining: 28,
  periodEndsAtOverride: DateTime(2026, 12, 15),
  renewal: RenewalInfo(
    state: 'IN_REVIEW',
    dueDate: DateTime(2026, 12, 15),
    daysLeft: 28,
    amount: 5000,
    currency: 'DOP',
    planCode: 'pro',
    planName: 'FullPOS Pro',
    order: const RenewalOrderInfo(
      id: 'order-2',
      reference: 'FP-2026-000777',
      amount: 5000,
      currency: 'DOP',
      status: 'UNCONFIRMED',
      months: 1,
    ),
  ),
);

/// La cuota paso su fecha sin pago.
final _licenseOverdue = LicenseStatusModel(
  companyId: 'company-1',
  companyName: 'Colmado La Fe',
  plan: 'STANDARD',
  planCode: 'pro',
  status: 'ACTIVE',
  isUsable: true,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 2,
  products: 320,
  daysRemaining: -1,
  periodEndsAtOverride: DateTime(2026, 11, 16),
  renewal: RenewalInfo(
    state: 'OVERDUE',
    dueDate: DateTime(2026, 11, 16),
    daysLeft: -1,
    amount: 5000,
    currency: 'DOP',
    planCode: 'pro',
    planName: 'FullPOS Pro',
  ),
);

/// Empresa ya en el tope del catalogo.
final _licenseTop = LicenseStatusModel(
  companyId: 'company-1',
  companyName: 'Colmado La Fe',
  plan: 'ENTERPRISE',
  planCode: 'empresa',
  status: 'ACTIVE',
  isUsable: true,
  maxUsers: 7,
  maxProducts: 5000,
  maxWarehouses: 10,
  users: 2,
  products: 320,
  daysRemaining: 20,
  periodEndsAtOverride: DateTime(2026, 12, 7),
);

Widget _app({
  LicenseStatusModel? license,
  List<LicenseOrder>? orders,
  PlanUpgradeRequest? openRequest,
  String initialLocation = Routes.planes,
}) {
  return ProviderScope(
    overrides: [
      plansCatalogProvider.overrideWith((ref) async => _plans),
      paymentInstructionsProvider.overrideWith(
        (ref) async => const PaymentInstructions(
          configured: true,
          instructions: 'Transfiere e incluye la referencia.',
          bankName: 'Banco Popular',
          accountNumber: '712345678',
          accountType: 'Corriente',
          holder: 'FULLTECH SRL',
          holderTaxId: '133080206',
        ),
      ),
      licenseOrdersProvider.overrideWith((ref) async => orders ?? [_order]),
      orderQuoteProvider.overrideWith(
        (ref, params) async => OrderQuote(
          planCode: params.planCode,
          planName: 'FullPOS Pro',
          months: params.months,
          currency: 'DOP',
          monthlyPrice: 3500,
          subtotal: 3500.0 * params.months,
          credit: 0,
          creditDays: 0,
          creditPlanCode: null,
          amountDue: 3500.0 * params.months,
          planChange: false,
        ),
      ),
      licenseStatusProvider.overrideWith(
        (ref) async => license ?? _licenseActive,
      ),
      planUpgradeRequesterProvider.overrideWithValue(({planCode, message}) async {
        return const PlanUpgradeRequest(
          id: 'req-1',
          reference: 'SOL-2026-000123',
          status: 'OPEN',
        );
      }),
      planUpgradeOpenProvider.overrideWith((ref) async => openRequest),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: initialLocation,
        routes: [
          GoRoute(
            path: Routes.planes,
            builder: (context, state) => const LicenseOverviewScreen(),
          ),
          GoRoute(
            path: Routes.planesCatalogo,
            builder: (context, state) => const PlansCatalogScreen(),
          ),
          GoRoute(
            path: Routes.planesPago,
            builder: (context, state) => PaymentScreen(
              planCode: state.uri.queryParameters['plan'],
              months: int.tryParse(state.uri.queryParameters['meses'] ?? ''),
              startPayment: state.uri.queryParameters['paso'] == 'pagar',
            ),
          ),
          GoRoute(
            path: Routes.planesHistorial,
            builder: (context, state) => const OrdersHistoryScreen(),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('con la licencia activa muestra el plan actual y dos acciones', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PLAN ACTUAL'), findsOneWidget);
    expect(find.text('FullPOS Pro'), findsOneWidget);
    expect(find.text('Activa'), findsOneWidget);
    expect(find.text('Cambiar a plan superior'), findsOneWidget);
    expect(find.text('Transferencia'), findsOneWidget);
    // El historial ya no se pinta suelto: vive dentro de Transferencia.
    expect(find.text('Historial'), findsNothing);
    // Sin indice lateral de secciones.
    expect(find.text('Secciones'), findsNothing);
    // Ya no se llama «Licencias».
    expect(find.text('Licencias'), findsNothing);
  });

  testWidgets('en la prueba avisa de que no hay plan activo y ofrece elegir', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(license: _licenseTrial));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Aún no tienes un plan activo'), findsOneWidget);
    expect(find.text('Te quedan 5 días de prueba.'), findsOneWidget);
    // La demo no se presenta como si fuera un plan contratado.
    expect(find.text('PLAN ACTUAL'), findsNothing);
    expect(find.text('FullPOS Pro'), findsNothing);
    expect(find.text('Prueba gratis'), findsNothing);

    await tester.tap(find.text('Elegir plan'));
    await tester.pumpAndSettle();
    expect(find.text('Elige tu plan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambiar a plan superior muestra solo los planes mas caros', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cambiar a plan superior'));
    await tester.pumpAndSettle();

    expect(find.text('Sube de plan'), findsOneWidget);
    expect(find.text('RD\$5,000'), findsOneWidget);
    expect(find.text('RD\$1,000'), findsNothing);
    expect(find.text('RD\$2,500'), findsNothing);
    expect(find.text('RD\$3,500'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('con la licencia vencida muestra la pantalla de suspension', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(license: _licenseSuspended));
    await tester.pumpAndSettle();

    expect(
      find.text('Tu plan esta suspendido por falta de pago'),
      findsOneWidget,
    );
    expect(find.text('Transferir y subir comprobante'), findsOneWidget);
    expect(find.text('Cambiar a un plan superior'), findsOneWidget);
    // El titular de estado activo no aparece.
    expect(find.text('PLAN ACTUAL'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cada pagina abre por separado y se vuelve con atras', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Transferencia'));
    await tester.pumpAndSettle();
    // Primero el centro de pagos: estado y dos caminos. El fixture tiene una
    // orden abierta, asi que el estado correcto es «pago pendiente».
    expect(find.text('Tienes un pago pendiente'), findsOneWidget);
    expect(find.text('Pagar ahora'), findsOneWidget);
    expect(find.text('Pagar cuota pendiente'), findsOneWidget);
    expect(find.text('Mejorar mi plan'), findsOneWidget);
    expect(find.text('Secciones'), findsNothing);

    await tester.tap(find.text('Pagar ahora'));
    await tester.pumpAndSettle();
    expect(find.text('Banco Popular'), findsOneWidget);

    // El historial de pagos se abre desde el appbar.
    await tester.tap(find.text('Historial de transferencia'));
    await tester.pumpAndSettle();
    expect(find.text('Tus ordenes'), findsOneWidget);

    await tester.tap(find.byTooltip('Regresar').last);
    await tester.pumpAndSettle();
    expect(find.text('Banco Popular'), findsOneWidget);
    // El RNC tiene que verse y poder copiarse junto al valor.
    expect(find.text('133080206'), findsOneWidget);
    expect(find.byTooltip('Copiar RNC'), findsOneWidget);
    // La cuota pendiente del plan actual no se cancela.
    expect(find.text('Cancelar orden'), findsNothing);
    // La referencia bancaria es opcional y el cliente lo ve claro.
    expect(
      find.textContaining('No hace falta escribir la referencia'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Regresar').last);
    await tester.pumpAndSettle();
    expect(find.text('Tienes un pago pendiente'), findsOneWidget);

    await tester.tap(find.byTooltip('Regresar').last);
    await tester.pumpAndSettle();
    expect(find.text('PLAN ACTUAL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda en telefono', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('PLAN ACTUAL'), findsOneWidget);
    await tester.tap(find.text('Cambiar a plan superior'));
    await tester.pumpAndSettle();
    // Solo los planes superiores: el actual (Pro) y los inferiores no salen.
    expect(find.text('RD\$5,000'), findsOneWidget);
    expect(find.text('RD\$3,500'), findsNothing);
    expect(find.text('RD\$1,000'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la proxima cuota muestra importe, vencimiento y Pagar ahora', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        license: _licenseUpcoming,
        orders: const [],
        initialLocation: Routes.planesPago,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // No esta vencida: se dice «proxima», no «vencida».
    expect(find.text('Tu proxima cuota esta por vencer'), findsOneWidget);
    expect(find.text('PROXIMA CUOTA'), findsOneWidget);
    expect(find.text('Tu cuota esta vencida'), findsNothing);
    expect(find.text('RD\$5,000'), findsOneWidget);
    expect(find.text('Vence el 26/11/2026 · 1 mes'), findsOneWidget);
    expect(find.text('Pagar ahora'), findsOneWidget);
    // Las dos opciones de siempre siguen disponibles.
    expect(find.text('Pagar meses por adelantado'), findsOneWidget);
    expect(find.text('Mejorar mi plan'), findsOneWidget);
  });

  testWidgets('un pago en verificacion no se presenta como deuda', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        license: _licenseInReview,
        orders: const [],
        initialLocation: Routes.planesPago,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Tu pago esta en verificacion'), findsOneWidget);
    expect(find.textContaining('FP-2026-000777'), findsOneWidget);
    // Sin reclamar otro pago ni marcar cuota pendiente.
    expect(find.text('Pagar ahora'), findsNothing);
    expect(find.text('PROXIMA CUOTA'), findsNothing);
    expect(find.text('CUOTA VENCIDA'), findsNothing);
    expect(find.text('Pagar meses por adelantado'), findsOneWidget);
    expect(find.text('Mejorar mi plan'), findsOneWidget);
  });

  testWidgets('la cuota vencida ofrece pagar sin perder el flujo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        license: _licenseOverdue,
        orders: const [],
        initialLocation: Routes.planesPago,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Tu cuota esta vencida'), findsOneWidget);
    expect(find.text('CUOTA VENCIDA'), findsOneWidget);
    expect(find.text('Pagar ahora'), findsOneWidget);
    // Con cuota vencida no se habla de «adelantado».
    expect(find.text('Pagar cuota pendiente'), findsOneWidget);
    expect(find.text('Pagar meses por adelantado'), findsNothing);
    expect(find.text('Mejorar mi plan'), findsOneWidget);
  });

  testWidgets('en el ultimo plan se pide la mejora a soporte, sin mas planes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        license: _licenseTop,
        initialLocation: '${Routes.planesCatalogo}?superiores=1',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ya estás en el último plan'), findsOneWidget);
    expect(find.text('YA ESTAS EN EL ULTIMO PLAN'), findsOneWidget);
    // Nada de ofrecer planes que no existen ni ruido de «cambiar de plan».
    expect(find.text('Ver todos los planes'), findsNothing);
    expect(find.text('Cambiar de plan'), findsNothing);

    await tester.tap(find.text('Solicitar mejora de plan a soporte'));
    await tester.pumpAndSettle();

    // Confirmacion para el cliente con la referencia del ticket.
    expect(find.textContaining('SOL-2026-000123'), findsWidgets);
    expect(
      find.textContaining('Un administrador te va a estar contactando'),
      findsWidgets,
    );
    expect(find.text('Solicitar mejora de plan a soporte'), findsNothing);
    // El aviso se retira solo; se deja correr su temporizador.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('con planes superiores no aparece la solicitud a soporte', (    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        license: _licenseActive,
        initialLocation: '${Routes.planesCatalogo}?superiores=1',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Solicitar mejora de plan a soporte'), findsNothing);
    expect(find.text('Ya estás en el último plan'), findsNothing);
    expect(find.text('Empresa'), findsOneWidget);
    // El camino de mejora no permite ver el catalogo completo.
    expect(find.text('Ver todos los planes'), findsNothing);
  });

  testWidgets('si el ticket ya existe se muestra sin pedirlo otra vez', (    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        license: _licenseTop,
        initialLocation: '${Routes.planesCatalogo}?superiores=1',
        openRequest: const PlanUpgradeRequest(
          id: 'req-9',
          reference: 'SOL-2026-000777',
          status: 'OPEN',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Solicitar mejora de plan a soporte'),
      findsNothing,
    );
    expect(find.textContaining('SOL-2026-000777'), findsOneWidget);
    expect(find.text('Ver todos los planes'), findsNothing);
  });

  testWidgets('una orden de cambio de plan si se puede cancelar', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1320, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        license: _licenseActive,
        orders: [
          LicenseOrder(
            id: 'order-change',
            planCode: 'empresa',
            planName: 'FullPOS Empresa',
            amount: 3500,
            currency: 'DOP',
            months: 1,
            status: 'AWAITING_TRANSFER',
            reference: 'FP-2026-000555',
            expiresAt: DateTime(2026, 12, 2),
          ),
        ],
        initialLocation: '${Routes.planesPago}?plan=empresa&paso=pagar',
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cancelar orden'), findsOneWidget);
    expect(
      find.text('Subir comprobante de la transferencia'),
      findsOneWidget,
    );
  });
}
