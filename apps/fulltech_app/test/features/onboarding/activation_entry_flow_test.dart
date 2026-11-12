import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/app_bootstrap_status.dart';
import 'package:daleventa_pos/core/app_access/session_notices.dart';
import 'package:daleventa_pos/core/widgets/web_session_actions.dart';
import 'package:daleventa_pos/core/widgets/branded_menu_button.dart';
import 'package:daleventa_pos/features/account/apps_downloads_panel.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:daleventa_pos/core/app_access/app_access_links.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/app_router.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/onboarding/application/activation_controller.dart';
import 'package:daleventa_pos/features/onboarding/data/activation_models.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_entry_point.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_panel.dart';
import 'package:daleventa_pos/features/onboarding/presentation/widgets/activation_welcome_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'activation-qa',
        email: 'qa@example.invalid',
        nombreCompleto: 'QA',
        telefono: '',
        role: 'ADMIN',
        companyId: 'activation-company',
        companyName: 'Mi negocio',
        requiresOnboarding: true,
      ),
    );
  }

  void switchUser() {
    state = state.copyWith(
      user: UserModel(
        id: 'new-owner',
        email: 'new@example.invalid',
        nombreCompleto: 'Nuevo',
        telefono: '',
        role: 'ADMIN',
        companyId: 'activation-company',
        companyName: 'Mi negocio',
        requiresOnboarding: true,
      ),
    );
  }
}

ActivationState _fixture({
  bool seen = false,
  bool dismissed = false,
  bool complete = false,
}) => ActivationState.fromJson({
  'companyId': 'activation-company',
  'required': true,
  'welcomeSeen': seen,
  'dismissed': dismissed,
  'allResolved': false,
  'progress': {
    'total': 7,
    'done': 2,
    'skipped': 0,
    'pending': 5,
    'percent': 29,
  },
  'tasks': [
    for (final key in [
      'account',
      'products',
      'firstSale',
      'business',
      'taxes',
      'tickets',
      'ecf',
    ])
      {
        'key': key,
        'title': key == 'products' ? 'Tu primer producto' : key,
        'state': complete || ['account', 'business'].contains(key)
            ? 'DONE'
            : 'PENDING',
        'optional': key != 'account',
        'destination': key == 'products' ? 'catalog' : 'company',
      },
  ],
});

class _Activation extends ActivationController {
  bool seen = false;
  bool dismissed = false;
  int reopened = 0;
  @override
  Future<void> reopen() async {
    reopened++;
  }

  @override
  Future<ActivationState?> build() async => _fixture();
  @override
  Future<void> markWelcomeSeen() async {
    seen = true;
    state = AsyncValue.data(_fixture(seen: seen, dismissed: dismissed));
  }

  @override
  Future<void> dismiss() async {
    dismissed = true;
    state = AsyncValue.data(_fixture(seen: seen, dismissed: dismissed));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final folder = Platform.environment['FULLPOS_VISUAL_EVIDENCE_DIR'];
  if (folder == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final target = File('$folder/$name.png');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final fonts = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(
        rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'),
      );
    }
    await fonts.load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets(
      'avisos web independientes, navegación y progreso en ${size.width}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final controller = _Activation();
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => Scaffold(
                appBar: AppBar(
                  title: const Text('POS'),
                  actions: const [WebSessionActions()],
                ),
                body: const Text('Ventas disponibles'),
              ),
            ),
            GoRoute(
              path: Routes.apps,
              builder: (_, _) => const Scaffold(body: AppsDownloadsContent()),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith((ref) => _Auth(ref)),
              activationControllerProvider.overrideWith(() => controller),
              webSessionActionsEnabledProvider.overrideWithValue(true),
            ],
            child: RepaintBoundary(
              key: const ValueKey('menu-capture'),
              child: MaterialApp.router(
                theme: AppTheme.light,
                routerConfig: router,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(WebSessionActions)),
        );
        final progress = container.read(activationControllerProvider).value;
        await tester.tap(
          find.byTooltip('Ocultar Activa tu FullPOS durante esta sesión'),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.rocket_launch_outlined), findsNothing);
        expect(find.byIcon(Icons.devices_other_rounded), findsOneWidget);
        expect(
          container.read(activationControllerProvider).value,
          same(progress),
        );
        await tester.tap(find.byIcon(Icons.devices_other_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Windows'), findsOneWidget);
        expect(find.text('Android'), findsOneWidget);
        expect(find.text('iPhone'), findsOneWidget);
        expect(find.byTooltip('Copiar enlace'), findsNWidgets(4));
        expect(find.byTooltip('Compartir enlace'), findsNWidgets(4));
        final dialog = tester.widget<Dialog>(find.byType(Dialog));
        expect(dialog.alignment, Alignment.center);
        await _captureMenu(tester, 'apps-${size.width.toInt()}');
        await tester.ensureVisible(
          find.text(
            'También puedes encontrar estas aplicaciones en Configuración → Apps de la empresa.',
          ),
        );
        await tester.tap(
          find.text(
            'También puedes encontrar estas aplicaciones en Configuración → Apps de la empresa.',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.path,
          Routes.apps,
        );
        expect(find.byType(AppsDownloadsContent), findsOneWidget);
        router.go('/');
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.rocket_launch_outlined), findsNothing);
        await tester.tap(find.byTooltip('Ocultar Apps durante esta sesión'));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.devices_other_rounded), findsNothing);
        expect(
          container.read(activationControllerProvider).value,
          same(progress),
        );
      },
    );
  }

  testWidgets('aplicaciones nativas no muestran avisos del AppBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [WebSessionActions()])),
        ),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.devices_other_rounded), findsNothing);
  });

  testWidgets(
    'los avisos dejan espacio al menú y a las acciones POS en 320 px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => _Auth(ref)),
            activationControllerProvider.overrideWith(_Activation.new),
            webSessionActionsEnabledProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: SizedBox(
                height: 50,
                child: Stack(
                  children: [
                    Positioned(
                      left: 8,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: BrandedMenuButton(
                          onPressed: () {},
                          onDark: true,
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 6,
                      top: 0,
                      bottom: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WebSessionActions(),
                          SizedBox(width: 80, child: Text('QR · Acciones')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final menu = tester.getRect(find.byType(BrandedMenuButton));
      final notices = tester.getRect(find.byType(WebSessionActions));
      expect(menu.right, lessThanOrEqualTo(notices.left));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'la X del anuncio oculta solo aplicaciones y conserva onboarding',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => _Auth(ref)),
            activationControllerProvider.overrideWith(_Activation.new),
            webSessionActionsEnabledProvider.overrideWithValue(true),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(actions: const [WebSessionActions()]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.devices_other_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cerrar anuncio de aplicaciones'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.devices_other_rounded), findsNothing);
      expect(find.byIcon(Icons.rocket_launch_outlined), findsOneWidget);
    },
  );

  testWidgets(
    'PWA sin prompt ofrece instrucciones en lugar de una acción vacía',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openAppAccessChannel(
                  context,
                  AppAccessLinks.allChannels().last,
                ),
                child: const Text('Instalar PWA'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Instalar PWA'));
      await tester.pumpAndSettle();
      expect(find.text('Instalar la aplicación web'), findsOneWidget);
      expect(find.textContaining('en Safari'), findsOneWidget);
      expect(find.textContaining('Chrome o Edge'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(find.text('Instalar la aplicación web'), findsNothing);
    },
  );

  testWidgets('Apps copia el enlace oficial y ofrece compartir', (
    tester,
  ) async {
    String? clipboard;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final channel = AppAccessLinks.allChannels().first;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: AppsDownloadCard(channel: channel, concise: true),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Copiar enlace'));
    await tester.pumpAndSettle();
    expect(clipboard, channel.uri.toString());
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Compartir enlace',
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('completar onboarding retira solo su acceso temporal', (
    tester,
  ) async {
    final controller = _Activation();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => _Auth(ref)),
          activationControllerProvider.overrideWith(() => controller),
          webSessionActionsEnabledProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [WebSessionActions()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.rocket_launch_outlined));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(WebSessionActions)),
    );
    expect(container.read(activationPanelOpenProvider), isTrue);
    expect(controller.reopened, 1);
    controller.state = AsyncValue.data(_fixture(complete: true));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.rocket_launch_outlined), findsNothing);
    expect(find.byIcon(Icons.devices_other_rounded), findsOneWidget);
  });

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('bienvenida nueva y panel secuenciales en ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => _Auth(ref)),
            activationControllerProvider.overrideWith(_Activation.new),
            appBootstrapStatusProvider.overrideWithValue(
              AppBootstrapStatus.ready,
            ),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(
              key: const ValueKey('capture'),
              child: const Scaffold(
                body: ActivationEntryPoint(child: Center(child: Text('POS'))),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ActivationWelcomeCard), findsOneWidget);
      expect(find.byType(ActivationPanel), findsNothing);
      expect(find.textContaining('3 pasos cortos'), findsOneWidget);
      await _capture(tester, 'welcome-${size.width.toInt()}');
      await tester.tap(find.text('¡Comencemos!'));
      await tester.pumpAndSettle();
      expect(find.byType(ActivationWelcomeCard), findsNothing);
      expect(find.byType(ActivationPanel), findsOneWidget);
      expect(find.text('Datos de tu negocio'), findsNothing);
      expect(find.text('Completa los datos de tu empresa'), findsOneWidget);
      await _capture(tester, 'activation-${size.width.toInt()}');
    });
  }

  testWidgets(
    'bienvenida espera la empresa y no hereda el panel de otra sesión',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bootstrap = StateProvider<AppBootstrapStatus>(
        (ref) => AppBootstrapStatus.authenticatedLoadingCompany,
      );
      final controller = _Activation();
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox())],
      );
      addTearDown(router.dispose);
      late _Auth auth;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => auth = _Auth(ref)),
            activationControllerProvider.overrideWith(() => controller),
            appBootstrapStatusProvider.overrideWith(
              (ref) => ref.watch(bootstrap),
            ),
            routerProvider.overrideWithValue(router),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: ActivationEntryPoint(child: Center(child: Text('POS'))),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ActivationWelcomeCard), findsNothing);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ActivationEntryPoint)),
      );
      container.read(bootstrap.notifier).state = AppBootstrapStatus.ready;
      await tester.pumpAndSettle();
      expect(find.byType(ActivationWelcomeCard), findsOneWidget);
      await tester.tap(find.text('¡Comencemos!'));
      await tester.pumpAndSettle();
      expect(find.byType(ActivationPanel), findsOneWidget);
      auth.switchUser();
      controller.state = AsyncValue.data(_fixture());
      await tester.pumpAndSettle();
      expect(container.read(activationPanelOpenProvider), isFalse);
      expect(find.byType(ActivationPanel), findsNothing);
      expect(find.byType(ActivationWelcomeCard), findsOneWidget);
    },
  );
}

Future<void> _captureMenu(WidgetTester tester, String name) async {
  // Full widget-tree capture for the anchored dialog, including its route.
  final folder = Platform.environment['FULLPOS_VISUAL_EVIDENCE_DIR'];
  if (folder == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('menu-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(folder).create(recursive: true);
    await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
