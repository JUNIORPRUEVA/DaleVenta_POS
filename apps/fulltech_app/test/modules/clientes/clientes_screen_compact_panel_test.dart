import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import '../../support/platform_goldens.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/routing/routes.dart';
import 'package:go_router/go_router.dart';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/realtime/operations_realtime_service.dart';
import 'package:daleventa_pos/modules/clientes/application/clientes_controller.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/clientes/cliente_profile_model.dart';
import 'package:daleventa_pos/modules/clientes/cliente_timeline_model.dart';
import 'package:daleventa_pos/modules/clientes/clientes_screen.dart';
import 'package:daleventa_pos/modules/clientes/data/clientes_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final size in [
    const Size(1024, 600),
    const Size(1366, 768),
    const Size(1920, 1080),
    const Size(2560, 1440),
  ]) {
    for (final empty in [false, true]) {
      testWidgets('clientes compactos $size vacío $empty', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final client = ClienteModel(
          id: 'client-1',
          ownerId: 'owner-1',
          nombre: 'Junior Lopez',
          telefono: '8295319442',
          correo: 'junior@test.local',
          createdAt: DateTime(2026, 9, 14),
          updatedAt: DateTime(2026, 9, 15),
        );

        final repository = _FakeClientesRepository(
          profile: ClienteProfileResponse(
            client: const ClienteProfileClient(
              id: 'client-1',
              nombre: 'Junior Lopez',
              telefono: '8295319442',
              phoneNormalized: '8295319442',
            ),
            metrics: ClienteProfileMetrics(
              salesCount: 2,
              salesTotal: 6000,
              lastSaleAt: DateTime(2026, 9, 15),
              creditSalesCount: 2,
              creditAmountTotal: 3500,
              creditPaidTotal: 0,
              creditBalanceTotal: 3500,
              lastCreditAt: DateTime(2026, 9, 15),
              servicesCount: 0,
              serviceOrdersCount: 0,
              legacyServicesCount: 0,
              serviceReferencesCount: 0,
              legacyServicesTotal: 0,
              lastServiceAt: null,
              lastReferenceAt: null,
              cotizacionesCount: 0,
              cotizacionesTotal: 0,
              lastCotizacionAt: null,
              lastActivityAt: DateTime(2026, 9, 15),
            ),
            createdBy: null,
          ),
          timeline: ClienteTimelineResponse(
            items: [
              ClienteTimelineEvent(
                eventType: 'sale',
                eventId: 'sale-1',
                at: DateTime(2026, 9, 15),
                title: 'Venta',
                amount: 3000,
              ),
              ClienteTimelineEvent(
                eventType: 'sale',
                eventId: 'sale-2',
                at: DateTime(2026, 9, 14),
                title: 'Venta',
                amount: 3000,
              ),
            ],
            before: '',
            take: 8,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              operationsRealtimeServiceProvider.overrideWith(
                (ref) => OperationsRealtimeService(TokenStorage()),
              ),
              clientesRepositoryProvider.overrideWith((ref) => repository),
              clientesControllerProvider.overrideWith(
                (ref) => _FakeClientesController(ref, empty ? null : client),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(size.width == 1024 ? 1.15 : 1),
                ),
                child: child!,
              ),
              home: const ClientesScreen(),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() async {
          final context = tester.element(find.byType(ClientesScreen));
          for (final name in ['search', 'edit', 'download', 'refresh']) {
            await precacheImage(
              AssetImage('assets/image/action_$name.png'),
              context,
            );
          }
        });
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Nuevo cliente'), findsNothing);
        expect(
          tester.getSize(find.byType(TextField).first).width,
          lessThanOrEqualTo(760),
        );
        expect(find.byTooltip('Nuevo cliente'), findsNothing);
        expect(find.text('Exportar'), findsNothing);
        expect(find.byTooltip('Exportar'), findsOneWidget);
        expect(find.byTooltip('Importar'), findsOneWidget);
        expect(find.byTooltip('Actualizar'), findsWidgets);
        if (!empty) {
          expect(
            find.byKey(const ValueKey('client-email-client-1')),
            size.width >= 1920 ? findsOneWidget : findsNothing,
          );
          expect(find.text('Junior Lopez'), findsWidgets);
          expect(find.text('Resumen de actividad'), findsOneWidget);
          expect(find.text('Últimos movimientos'), findsOneWidget);
        } else {
          expect(find.text('Crear cliente').hitTestable(), findsOneWidget);
        }
        await expectLater(
          find.byType(Scaffold).first,
          matchesGoldenFile(
            platformGolden(
              'goldens/clients_${empty ? 'empty_' : ''}${size.width.toInt()}.png',
            ),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets('Crear cliente abre Facturar sin abrir el formulario aquí', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/client-review',
      routes: [
        GoRoute(
          path: '/client-review',
          builder: (_, __) => const ClientesScreen(),
        ),
        GoRoute(
          path: Routes.cotizaciones,
          builder: (_, __) => const Scaffold(body: Text('Facturar existente')),
        ),
      ],
    );
    addTearDown(router.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => _ClientAuth(ref)),
          operationsRealtimeServiceProvider.overrideWith(
            (ref) => OperationsRealtimeService(TokenStorage()),
          ),
          clientesControllerProvider.overrideWith(
            (ref) => _FakeClientesController(ref, null),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Facturar existente'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _ClientAuth extends AuthController {
  _ClientAuth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'test',
        email: 'test@test.local',
        nombreCompleto: 'Usuario',
        telefono: '',
        role: 'ADMIN',
        companyId: 'test-company',
      ),
    );
  }
}

class _FakeClientesController extends ClientesController {
  _FakeClientesController(super.ref, ClienteModel? client) : super() {
    state = ClientesState(items: [if (client != null) client]);
  }

  @override
  Future<void> load({String? search}) async {}

  @override
  Future<void> refresh() async {}
}

class _FakeClientesRepository extends ClientesRepository {
  _FakeClientesRepository({required this.profile, required this.timeline})
    : super(Dio(), SyncQueueService(OfflineStore.instance));

  final ClienteProfileResponse profile;
  final ClienteTimelineResponse timeline;

  @override
  Future<ClienteProfileResponse> getClientProfile({required String id}) async {
    return profile;
  }

  @override
  Future<ClienteTimelineResponse> getClientTimeline({
    required String id,
    int take = 100,
    DateTime? before,
    List<String> types = const [],
  }) async {
    return timeline;
  }
}
