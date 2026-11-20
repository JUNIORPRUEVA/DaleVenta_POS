import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/license/license_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/features/plans/data/plans_repository.dart';
import 'package:daleventa_pos/features/onboarding/application/activation_controller.dart';
import 'package:daleventa_pos/features/onboarding/data/activation_models.dart';
import 'package:daleventa_pos/core/app_access/session_notices.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _MenuAuthController extends AuthController {
  _MenuAuthController(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'u-menu',
        email: 'menu@example.com',
        nombreCompleto: 'Usuario Menu',
        telefono: '',
        role: 'ADMIN',
        companyId: 'company-menu',
      ),
    );
  }
}

class _MenuActivation extends ActivationController {
  int reopened = 0;
  @override
  Future<ActivationState?> build() async => ActivationState.fromJson({
    'companyId': 'company-menu',
    'welcomeSeen': true,
    'tasks': [
      {
        'key': 'products',
        'title': 'Productos',
        'state': 'PENDING',
        'destination': 'catalog',
      },
    ],
  });
  @override
  Future<void> reopen() async {
    reopened++;
  }
}

final _captureKey = GlobalKey();

Future<void> _capturePanel(WidgetTester tester, String name) async {
  final directory = Platform.environment['RECOVERY_VISUAL_DIR'];
  if (directory == null) return;
  final boundary = _captureKey.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

Future<GoRouter> _pumpCompanyMenu(
  WidgetTester tester, {
  LicenseStatusModel? license,
  List<PlanOffer> catalog = const [],
}) async {
  final router = GoRouter(
    initialLocation: '/menu-test',
    routes: [
      GoRoute(
        path: '/menu-test',
        builder: (_, __) => Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: buildCompanyAccountMenuForTesting(),
          ),
        ),
      ),
      GoRoute(
        path: Routes.configuracionEmpresa,
        builder: (_, __) => const Scaffold(body: Text('Datos de empresa')),
      ),
      GoRoute(
        path: Routes.planesPago,
        builder: (_, state) => Scaffold(body: Text('Pago ${state.uri.query}')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: ProviderScope(
      overrides: [
        authStateProvider.overrideWith(_MenuAuthController.new),
        activationControllerProvider.overrideWith(_MenuActivation.new),
        // La licencia se consulta para el menu; en pruebas se resuelve al
        // instante para no dejar el temporizador de la peticion pendiente.
        licenseStatusProvider.overrideWith(
          (_) async => license ?? LicenseStatusModel.fromJson({}),
        ),
        plansCatalogProvider.overrideWith((_) async => catalog),
        licenseOrdersProvider.overrideWith((_) async => const []),
        companySettingsProvider.overrideWith(
          (_) async =>
              CompanySettings.empty().copyWith(companyName: 'FullPOS Test'),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
      ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _companyMenuItem(String label) {
  return find
      .descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text(label),
      )
      .last;
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Bold.ttf'));
    await font.load();
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [1280.0, 390.0]) {
    testWidgets('Plan actual abre el panel recuperado sin desbordes en $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final license = LicenseStatusModel.fromJson({
        'companyId': 'company-menu', 'companyName': 'Empresa ficticia',
        'planCode': 'pro', 'status': 'ACTIVE', 'isUsable': true,
        'limits': {'maxUsers': 4, 'maxProducts': 1000, 'maxWarehouses': 5},
        'usage': {'users': 2, 'products': 57},
      });
      await _pumpCompanyMenu(tester, license: license, catalog: [
        PlanOffer.fromJson({
          'code': 'pro', 'name': 'FullPOS Pro', 'monthlyPrice': '3500',
          'limits': {'maxUsers': 4, 'maxProducts': 1000, 'maxWarehouses': 5},
          'features': {'ecf': true, 'taxes': true, 'multiWarehouse': true},
        }),
      ]);
      await tester.tap(find.byTooltip('Cuenta y empresa'));
      await tester.pumpAndSettle();
      await tester.tap(_companyMenuItem('Plan actual'));
      await tester.pumpAndSettle();
      expect(find.text('FullPOS Pro'), findsOneWidget);
      expect(find.text('Usuarios'), findsOneWidget);
      expect(find.text('Productos'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);
      final transfer = tester.widget<TextButton>(find.ancestor(
        of: find.text('Transferencia'), matching: find.byType(TextButton),
      ));
      expect(transfer.style!.textStyle!.resolve({})!.fontFamily, 'Manrope');
      expect(find.text('Estado de uso, empresa activa y alcance contratado.'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capturePanel(tester, 'plan-actual-${width.toInt()}');
    });
  }

  testWidgets('una cuota pendiente conserva el plan y abre el pago correspondiente', (
    tester,
  ) async {
    final router = await _pumpCompanyMenu(tester, license: LicenseStatusModel.fromJson({
      'companyId': 'company-menu', 'status': 'ACTIVE', 'isUsable': true,
      'planCode': 'pro',
      'renewal': {'state': 'UPCOMING', 'order': {'status': 'AWAITING_TRANSFER'}},
    }));
    await tester.tap(find.byTooltip('Cuenta y empresa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(_companyMenuItem('Plan actual'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Realizar pago'), findsOneWidget);
    await tester.tap(find.text('Realizar pago'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(router.routeInformationProvider.value.uri.path, Routes.planesPago);
    expect(router.routeInformationProvider.value.uri.queryParameters,
        {'plan': 'pro', 'paso': 'pagar'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('una licencia anterior no recibe un codigo de catalogo al abrir el panel', (
    tester,
  ) async {
    final legacy = LicenseStatusModel.fromJson({
      'companyId': 'company-menu', 'plan': 'ENTERPRISE',
      'status': 'ACTIVE', 'isUsable': true,
      'limits': {'maxUsers': 999, 'maxProducts': 999},
      'usage': {'users': 4, 'products': 80},
    });
    await _pumpCompanyMenu(tester, license: legacy);
    await tester.tap(find.byTooltip('Cuenta y empresa'));
    await tester.pumpAndSettle();
    await tester.tap(_companyMenuItem('Plan actual'));
    await tester.pumpAndSettle();
    expect(find.text('Plan enterprise'), findsOneWidget);
    expect(find.text('Pago pendiente'), findsNothing);
    expect(find.text('Almacenes'), findsNothing);
    expect(legacy.planCode, isNull);
    expect(legacy.maxProducts, 999);
    expect(tester.takeException(), isNull);
  });

  testWidgets('un bloqueo no se atribuye sin evidencia a falta de pago', (
    tester,
  ) async {
    await _pumpCompanyMenu(tester, license: LicenseStatusModel.fromJson({
      'companyId': 'company-menu', 'status': 'BLOCKED', 'isUsable': false,
      'access': {'level': 'BLOCKED'},
    }));
    await tester.tap(find.byTooltip('Cuenta y empresa'));
    await tester.pumpAndSettle();
    await tester.tap(_companyMenuItem('Plan actual'));
    await tester.pumpAndSettle();
    expect(find.text('Tu licencia requiere atención'), findsOneWidget);
    expect(find.textContaining('por falta de pago'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Configuracion retoma onboarding después de ocultar el aviso temporal',
    (tester) async {
      await _pumpCompanyMenu(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byTooltip('Cuenta y empresa')),
      );
      container.read(sessionNoticesProvider.notifier).dismiss('activation');
      await tester.tap(find.byTooltip('Cuenta y empresa'));
      await tester.pumpAndSettle();
      await tester.tap(_companyMenuItem('Configuracion'));
      await tester.pumpAndSettle();
      expect(find.text('Apps de la empresa'), findsOneWidget);
      await tester.tap(find.text('Termina de preparar FullPOS'));
      await tester.pumpAndSettle();
      expect(container.read(activationPanelOpenProvider), isTrue);
      expect(
        (container.read(activationControllerProvider.notifier)
                as _MenuActivation)
            .reopened,
        1,
      );
      expect(container.read(sessionNoticesProvider), contains('activation'));
    },
  );
  testWidgets(
    'Cuenta y empresa > Empresa navega sin usar ref tras cerrar menu',
    (tester) async {
      final router = await _pumpCompanyMenu(tester);

      await tester.tap(find.byTooltip('Cuenta y empresa'));
      await tester.pumpAndSettle();
      await tester.tap(_companyMenuItem('Empresa'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pumpAndSettle();

      expect(
        router.routeInformationProvider.value.uri.path,
        Routes.configuracionEmpresa,
      );
      expect(find.text('Datos de empresa'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cuenta y empresa no muestra acceso directo a Almacenes', (
    tester,
  ) async {
    await _pumpCompanyMenu(tester);

    await tester.tap(find.byTooltip('Cuenta y empresa'));
    await tester.pumpAndSettle();

    expect(find.text('Almacenes'), findsNothing);
  });

  testWidgets('Cuenta y empresa > Configuracion despliega opciones compactas', (
    tester,
  ) async {
    await _pumpCompanyMenu(tester);

    await tester.tap(find.byTooltip('Cuenta y empresa'));
    await tester.pumpAndSettle();

    expect(_companyMenuItem('Empresa'), findsOneWidget);
    expect(_companyMenuItem('Plan actual'), findsOneWidget);
    expect(_companyMenuItem('Configuracion'), findsOneWidget);
    expect(find.text('Actualización'), findsNothing);
    expect(find.text('Impresora'), findsNothing);
    expect(find.text('Eliminar mi cuenta'), findsNothing);

    await tester.tap(_companyMenuItem('Configuracion'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    await tester.pumpAndSettle();

    expect(find.text('Actualización'), findsOneWidget);
    expect(find.text('Impresora'), findsOneWidget);
    expect(find.text('Eliminar mi cuenta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Cuenta y empresa > Empresa soporta desmontaje rapido sin StateError',
    (tester) async {
      await _pumpCompanyMenu(tester);

      await tester.tap(find.byTooltip('Cuenta y empresa'));
      await tester.pumpAndSettle();
      await tester.tap(_companyMenuItem('Empresa'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 160));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
