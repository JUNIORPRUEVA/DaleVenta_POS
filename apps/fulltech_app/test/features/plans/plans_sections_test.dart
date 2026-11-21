import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
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
import 'package:daleventa_pos/features/plans/presentation/widgets/plan_ui.dart';
import 'package:daleventa_pos/features/plans/presentation/widgets/plan_card.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import '../../support/plans_file_picker.dart';

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

final _order = LicenseOrder(
  id: 'order-1',
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
  Object? quoteError,
  double? quotedAmount,
  PlansRepository? repository,
  Future<List<LicenseOrder>> Function()? loadOrders,
}) {
  return ProviderScope(
    overrides: [
      if (repository != null)
        plansRepositoryProvider.overrideWithValue(repository),
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
      licenseOrdersProvider.overrideWith(
        (ref) async =>
            loadOrders != null ? await loadOrders() : orders ?? [_order],
      ),
      orderQuoteProvider.overrideWith((ref, params) async {
        if (quoteError != null) throw quoteError;
        return OrderQuote(
          planCode: params.planCode,
          planName: 'FullPOS Pro',
          months: params.months,
          currency: 'DOP',
          monthlyPrice: 3500,
          subtotal: 3500.0 * params.months,
          credit: 0,
          creditDays: 0,
          creditPlanCode: null,
          amountDue: quotedAmount ?? 3500.0 * params.months,
          planChange: false,
        );
      }),
      licenseStatusProvider.overrideWith(
        (ref) async => license ?? _licenseActive,
      ),
      planUpgradeRequesterProvider.overrideWithValue(({
        planCode,
        message,
      }) async {
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

class _UploadRepository extends PlansRepository {
  _UploadRepository() : super(Dio());
  int uploads = 0;
  @override
  Future<EvidenceUploadResult> uploadEvidence({
    required String orderId,
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
  }) async {
    uploads++;
    return EvidenceUploadResult(
      activated: false,
      message: 'Recibido',
      order: LicenseOrder(
        id: orderId,
        planCode: 'pro',
        amount: 3500,
        currency: 'DOP',
        months: 1,
        status: 'EVIDENCE_RECEIVED',
        reference: 'FP-TEST',
      ),
    );
  }
}

void main() {
  testWidgets(
    'el historial no confunde un fallo de red con ausencia de pagos',
    (tester) async {
      await tester.pumpWidget(
        _app(
          initialLocation: Routes.planesHistorial,
          loadOrders: () async => throw StateError('offline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudo comprobar el historial. Intenta nuevamente.'),
        findsOneWidget,
      );
      expect(
        find.text('Todavia no has comprado ni renovado un plan.'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'el centro de pagos no afirma estar al dia sin comprobar el servidor',
    (tester) async {
      await tester.pumpWidget(
        _app(
          initialLocation: Routes.planesPago,
          loadOrders: () async => throw StateError('offline'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se pudo comprobar el estado del pago. Intenta nuevamente.',
        ),
        findsOneWidget,
      );
      expect(find.text('Tu suscripcion esta al dia'), findsNothing);
    },
  );
  tearDown(AppFeedback.clearToasts);
  for (final width in [390.0, 1280.0, 1920.0]) {
    testWidgets('catalog is spacious and responsive at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(initialLocation: Routes.planesCatalogo));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final card = tester.getSize(find.byType(PlanCard).first);
      if (width >= 1280) {
        expect(card.width, greaterThan(width >= 1900 ? 320 : 280));
      }
      final renew = find.widgetWithText(TextButton, 'Renovar plan');
      expect(renew, findsOneWidget);
      expect(tester.widget<TextButton>(renew).onPressed, isNotNull);
    });
  }
  testWidgets(
    'cancelled file selection leaves payment ready without uploading',
    (tester) async {
      final repository = _UploadRepository();
      final picker = PlansTestFilePicker(() async => null);
      FilePicker.platform = picker;
      await tester.pumpWidget(
        _app(
          repository: repository,
          initialLocation: '${Routes.planesPago}?plan=pro&paso=pagar',
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('Subir comprobante de la transferencia');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(repository.uploads, 0);
      expect(picker.calls, 1);
      expect(
        tester
            .widget<SquareButton>(
              find.byWidgetPredicate(
                (w) =>
                    w is SquareButton &&
                    w.label == 'Subir comprobante de la transferencia',
              ),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'one upload receives the proof without a fake confirmation step',
    (tester) async {
      final repository = _UploadRepository();
      final pending = Completer<FilePickerResult?>();
      final picker = PlansTestFilePicker(() => pending.future);
      FilePicker.platform = picker;
      await tester.pumpWidget(
        _app(
          repository: repository,
          initialLocation: '${Routes.planesPago}?plan=pro&paso=pagar',
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('Subir comprobante de la transferencia');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Procesando…'), findsOneWidget);
      await tester.tap(find.text('Procesando…'));
      expect(picker.calls, 1);
      pending.complete(
        FilePickerResult([
          PlatformFile(
            name: 'prueba.pdf',
            size: 4,
            bytes: Uint8List.fromList([37, 80, 68, 70]),
          ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(repository.uploads, 1);
      expect(find.text('Comprobante recibido'), findsOneWidget);
      expect(find.text('Confirmar pago'), findsNothing);
      expect(find.text('Ver estado del pago'), findsOneWidget);
    },
  );
  testWidgets(
    'order loading failure has a working retry and never silently enables a new order',
    (tester) async {
      var attempts = 0;
      await tester.pumpWidget(
        _app(
          initialLocation: '${Routes.planesPago}?plan=pro&paso=pagar',
          loadOrders: () async {
            if (attempts++ == 0) throw Exception('Synthetic order unavailable');
            return [_order];
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No se pudo comprobar tu orden de pago.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Reintentar'));
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(
        find.text('Subir comprobante de la transferencia'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'reviewed receipt remains visible on reopening without another upload',
    (tester) async {
      await tester.pumpWidget(
        _app(
          initialLocation: '${Routes.planesPago}?plan=pro&paso=pagar',
          orders: [
            const LicenseOrder(
              id: 'received',
              planCode: 'pro',
              amount: 3500,
              currency: 'DOP',
              months: 1,
              status: 'EVIDENCE_RECEIVED',
              reference: 'FP-TEST-RECEIVED',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comprobante recibido'), findsOneWidget);
      expect(find.text('Subir comprobante de la transferencia'), findsNothing);
      expect(find.text('Confirmar pago'), findsNothing);
    },
  );
  testWidgets(
    'an existing order can accept its voucher when quote refresh fails',
    (tester) async {
      await tester.pumpWidget(
        _app(
          initialLocation: '${Routes.planesPago}?plan=pro&paso=pagar',
          quoteError: Exception('Synthetic quote unavailable'),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byWidgetPredicate(
        (w) =>
            w is SquareButton &&
            w.label == 'Subir comprobante de la transferencia',
      );
      expect(button, findsOneWidget);
      expect(tester.widget<SquareButton>(button).onPressed, isNotNull);
    },
  );
  testWidgets('a changed quote never replaces an existing transfer amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        initialLocation: '${Routes.planesPago}?plan=pro&paso=pagar',
        quotedAmount: 3400,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Subir comprobante de la transferencia'), findsOneWidget);
    expect(find.textContaining('3,500'), findsWidgets);
    expect(find.textContaining('3,400'), findsNothing);
  });
  testWidgets(
    'resuming a multi-month order keeps its period instead of generating another order',
    (tester) async {
      await tester.pumpWidget(
        _app(
          initialLocation: '${Routes.planesPago}?plan=pro&paso=pagar',
          orders: [
            LicenseOrder(
              id: 'three-months',
              planCode: 'pro',
              amount: 10500,
              currency: 'DOP',
              months: 3,
              status: 'AWAITING_TRANSFER',
              reference: 'FP-TEST-003',
              expiresAt: DateTime.now().add(const Duration(days: 2)),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Subir comprobante de la transferencia'),
        findsOneWidget,
      );
      expect(find.textContaining('10,500'), findsWidgets);
    },
  );
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

  testWidgets('con planes superiores no aparece la solicitud a soporte', (
    tester,
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

  testWidgets('si el ticket ya existe se muestra sin pedirlo otra vez', (
    tester,
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
    expect(find.text('Solicitar mejora de plan a soporte'), findsNothing);
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
    expect(find.text('Subir comprobante de la transferencia'), findsOneWidget);
  });
}
