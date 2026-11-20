import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/license/license_repository.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../data/plans_repository.dart';
import '../presentation/screens/license_overview_screen.dart';
import '../presentation/screens/orders_history_screen.dart';
import '../presentation/screens/payment_screen.dart';
import '../presentation/screens/plans_catalog_screen.dart';

/// Vista previa de la seccion Planes con datos ficticios.
///
/// Uso (no forma parte del arranque de la app):
///   flutter run -d chrome -t lib/features/plans/preview/plans_preview.dart
///
/// Las cuatro pantallas son independientes y se pasan con el indice de la
/// izquierda (o las pestanas en telefono). Los importes y los limites son los
/// del catalogo real; la empresa y las ordenes son inventadas.
///
/// Cada pantalla tiene su ruta y se puede abrir directamente para comparar el
/// mismo estado en escritorio y en telefono:
///   #/planes
///   #/planes/catalogo
///   #/planes/pago            (centro de pagos)
///   #/planes/pago?paso=pagar (detalle de la cuota pendiente)
///   #/planes/pago?plan=pro&meses=3
///   #/planes/historial
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // La ruta de entrada se toma del hash para poder abrir cualquier pantalla
  // directamente y comparar el mismo estado en escritorio y en telefono.
  final fragment = Uri.base.fragment;
  final initialRoute =
      fragment.startsWith('/') ? fragment : Routes.planes;
  runApp(
    ProviderScope(
      overrides: [
        plansCatalogProvider.overrideWith((ref) async => _plans),
        paymentInstructionsProvider.overrideWith(
          (ref) async => const PaymentInstructions(
            configured: true,
            instructions:
                'Transfiere el monto exacto e incluye la referencia de tu orden en el concepto.',
            bankName: 'Banco Popular Dominicano',
            accountNumber: '712-345678-9',
            accountType: 'Corriente',
            holder: 'FULLTECH SRL',
            holderTaxId: '1-31-12345-6',
          ),
        ),
        licenseOrdersProvider.overrideWith((ref) async => _orders),
        // Cotizacion inventada: en la vista previa no hay servidor.
        orderQuoteProvider.overrideWith((ref, params) async {
          final plan = _plans.firstWhere(
            (p) => p.code == params.planCode,
            orElse: () => _plans.last,
          );
          final subtotal = plan.monthlyPrice * params.months;
          const credit = 1400.0; // 12 dias del plan actual
          return OrderQuote(
            planCode: plan.code,
            planName: plan.name,
            months: params.months,
            currency: plan.currency,
            monthlyPrice: plan.monthlyPrice,
            subtotal: subtotal,
            credit: credit,
            creditDays: 12,
            creditPlanCode: 'pro',
            amountDue: subtotal - credit,
            planChange: true,
          );
        }),
        licenseStatusProvider.overrideWith((ref) async {
          // `--dart-define=PREVIEW_TRIAL=true` sirve la pantalla de un cliente
          // que todavia esta en la prueba (sin plan contratado).
          if (const bool.fromEnvironment('PREVIEW_TRIAL')) return _licenseTrial;
          return ref.watch(_demoLicenseProvider);
        }),
      ],
      child: MaterialApp.router(
        title: 'Vista previa · Planes',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightForRole(AppRole.admin),
        // Barra de la vista previa (no se superpone: ocupa su propio espacio,
        // asi no intercepta los clics de la pantalla).
        builder: (context, child) => Column(
          children: [
            if (child != null) Expanded(child: child),
            Container(
              width: double.infinity,
              color: const Color(0xFF102235),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'VISTA PREVIA · datos ficticios',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Consumer(
                    builder: (context, ref, _) {
                      final expired =
                          ref.watch(_demoLicenseProvider).isUsable == false;
                      return TextButton(
                        onPressed: () =>
                            ref.read(_demoLicenseProvider.notifier).state =
                                expired ? _licenseActive : _licenseSuspended,
                        style: TextButton.styleFrom(
                          backgroundColor:
                              expired ? Colors.green.shade600 : Colors.red.shade600,
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        child: Text(
                          expired
                              ? 'Ver estado ACTIVO'
                              : 'Ver estado SUSPENDIDO',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        routerConfig: GoRouter(
          initialLocation: initialRoute,
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
              builder: (context, state) {
                final query = state.uri.queryParameters;
                return PaymentScreen(
                  planCode: query['plan'],
                  months: int.tryParse(query['meses'] ?? ''),
                  startPayment: query['paso'] == 'pagar',
                );
              },
            ),
            GoRoute(
              path: Routes.planesHistorial,
              builder: (context, state) => const OrdersHistoryScreen(),
            ),
          ],
        ),
      ),
    ),
  );
}

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

final _demoLicenseProvider = StateProvider<LicenseStatusModel>(
  (ref) => _licenseActive,
);

final _licenseActive = LicenseStatusModel(
  companyId: 'empresa-demo',
  companyName: 'Colmado La Fe',
  plan: 'STANDARD',
  planCode: 'pro',
  status: 'ACTIVE',
  isUsable: true,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 3,
  products: 812,
  daysRemaining: 12,
  periodEndsAtOverride: DateTime(2026, 12, 1),
  licenseTypeLabel: 'FullPOS Pro',
);

/// Mismo plan, pero vencido: es la pantalla de regularizacion.
final _licenseSuspended = LicenseStatusModel(
  companyId: 'empresa-demo',
  companyName: 'Colmado La Fe',
  plan: 'STANDARD',
  planCode: 'pro',
  status: 'EXPIRED',
  isUsable: false,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 3,
  products: 812,
  daysRemaining: -3,
  periodEndsAtOverride: DateTime(2026, 11, 13),
  licenseTypeLabel: 'FullPOS Pro',
);

/// Cliente en la **prueba**: usable pero sin plan contratado.
final _licenseTrial = LicenseStatusModel(
  companyId: 'empresa-demo',
  companyName: 'Colmado La Fe',
  plan: 'TRIAL',
  planCode: 'pro',
  status: 'TRIAL',
  isUsable: true,
  maxUsers: 4,
  maxProducts: 1000,
  maxWarehouses: 5,
  users: 3,
  products: 812,
  daysRemaining: 5,
  periodEndsAtOverride: DateTime(2026, 11, 24),
  licenseTypeLabel: 'Plan demo',
);

final _orders = <LicenseOrder>[
  LicenseOrder(
    id: 'order-open',
    planCode: 'pro',
    planName: 'FullPOS Pro',
    amount: 3500,
    currency: 'DOP',
    months: 1,
    status: 'AWAITING_TRANSFER',
    reference: 'FP-2026-000482',
    expiresAt: DateTime(2026, 11, 18, 18),
    createdAt: DateTime(2026, 11, 16, 9, 12),
  ),
  LicenseOrder(
    id: 'order-settled',
    planCode: 'pro',
    planName: 'FullPOS Pro',
    amount: 3500,
    currency: 'DOP',
    months: 1,
    status: 'SETTLED',
    reference: 'FP-2026-000301',
    periodStart: DateTime(2026, 11, 1),
    periodEnd: DateTime(2026, 12, 1),
    createdAt: DateTime(2026, 10, 30, 16, 40),
    evidences: const [
      LicenseOrderEvidence(
        id: 'ev-1',
        mime: 'application/pdf',
        sizeBytes: 184320,
      ),
    ],
  ),
  LicenseOrder(
    id: 'order-old',
    planCode: 'basico',
    planName: 'FullPOS Básico',
    amount: 1000,
    currency: 'DOP',
    months: 1,
    status: 'EXPIRED',
    reference: 'FP-2026-000128',
    createdAt: DateTime(2026, 9, 28, 11, 5),
  ),
];
