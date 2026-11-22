import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/mobile_page_app_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/realtime/operations_realtime_service.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/modules/clientes/application/clientes_controller.dart';
import 'package:daleventa_pos/modules/clientes/cliente_detail_screen.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/clientes/cliente_profile_model.dart';
import 'package:daleventa_pos/modules/clientes/cliente_timeline_model.dart';
import 'package:daleventa_pos/modules/clientes/data/cliente_detail_local_repository.dart';
import 'package:daleventa_pos/modules/clientes/data/clientes_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(
        rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('cliente detail renders without layout exceptions: $platform', (
      tester,
    ) async {
      tester.view.physicalSize = platform == TargetPlatform.windows
          ? const Size(1280, 900)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const client = ClienteModel(
        id: 'client-1',
        ownerId: 'owner-1',
        nombre: 'ANAILDA CHEVALIER JIMENEZ',
        telefono: '8092500943',
        direccion: 'SALIDA PARA SANTANA',
        locationUrl: 'https://maps.app.goo.gl/hzELURx7mKPRJSnW8',
      );

      final profile = ClienteProfileResponse(
        client: const ClienteProfileClient(
          id: 'client-1',
          nombre: 'ANAILDA CHEVALIER JIMENEZ',
          telefono: '8092500943',
          phoneNormalized: '8092500943',
          direccion: 'SALIDA PARA SANTANA',
          locationUrl: 'https://maps.app.goo.gl/hzELURx7mKPRJSnW8',
        ),
        metrics: const ClienteProfileMetrics(
          salesCount: 0,
          salesTotal: 0,
          lastSaleAt: null,
          creditSalesCount: 0,
          creditAmountTotal: 0,
          creditPaidTotal: 0,
          creditBalanceTotal: 0,
          lastCreditAt: null,
          servicesCount: 1,
          serviceOrdersCount: 1,
          legacyServicesCount: 0,
          serviceReferencesCount: 2,
          legacyServicesTotal: 0,
          lastServiceAt: null,
          lastReferenceAt: null,
          cotizacionesCount: 1,
          cotizacionesTotal: 17900,
          lastCotizacionAt: null,
          lastActivityAt: null,
        ),
        createdBy: const ClienteProfileCreatedBy(
          id: 'user-1',
          nombreCompleto: 'RUBEN LOOBENS J. F.',
        ),
      );

      final fakeRepository = _FakeClientesRepository(
        client: client,
        profile: profile,
        timeline: const ClienteTimelineResponse(
          items: [],
          before: '',
          take: 120,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            operationsRealtimeServiceProvider.overrideWith(
              (ref) => OperationsRealtimeService(TokenStorage()),
            ),
            clienteDetailLocalRepositoryProvider.overrideWith(
              (ref) => _FakeClienteDetailLocalRepository(),
            ),
            clientesRepositoryProvider.overrideWith((ref) => fakeRepository),
            clientesControllerProvider.overrideWith(
              (ref) => _FakeClientesController(ref, client),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const RepaintBoundary(
              key: ValueKey('client-detail-evidence'),
              child: ClienteDetailScreen(clienteId: 'client-1'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      final phone = platform != TargetPlatform.windows;
      expect(
        find.text(
          phone ? 'Datos del cliente' : 'Datos importantes del cliente',
        ),
        findsOneWidget,
      );
      expect(
        find.byType(MobilePageAppBar),
        phone ? findsOneWidget : findsNothing,
      );
      expect(find.text('Ubicacion GPS'), findsOneWidget);
      expect(find.text('ANAILDA CHEVALIER JIMENEZ'), findsWidgets);
      const evidence = String.fromEnvironment('MOBILE_DETAIL_EVIDENCE');
      if (evidence.isNotEmpty) {
        await tester.runAsync(() async {
          final imageContext = tester.element(find.byType(ClienteDetailScreen));
          await precacheImage(const AssetImage('assets/image/mobile_navigation/back.png'), imageContext);
          await precacheImage(const AssetImage('assets/image/mobile_navigation/more.png'), imageContext);
        });
        await tester.pump(const Duration(milliseconds: 500));
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('client-detail-evidence')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(evidence).create(recursive: true);
          await File('$evidence/client-detail-${platform.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }, variant: TargetPlatformVariant({platform}));
  }
}

class _FakeClientesController extends ClientesController {
  _FakeClientesController(super.ref, this.client) : super() {
    state = const ClientesState().copyWith(items: [client]);
  }

  final ClienteModel client;

  @override
  Future<void> load({String? search}) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<ClienteModel> getById(String id) async => client;

  @override
  Future<void> remove(String id) async {}
}

class _FakeClientesRepository extends ClientesRepository {
  _FakeClientesRepository({
    required this.client,
    required this.profile,
    required this.timeline,
  }) : super(Dio(), SyncQueueService(OfflineStore.instance));

  final ClienteModel client;
  final ClienteProfileResponse profile;
  final ClienteTimelineResponse timeline;

  @override
  Future<ClienteModel> getClientById({
    required String ownerId,
    required String id,
    bool skipLoader = false,
  }) async {
    return client;
  }

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

class _FakeClienteDetailLocalRepository extends ClienteDetailLocalRepository {
  @override
  Future<ClienteDetailLocalSnapshot> read(String clientId) async {
    return const ClienteDetailLocalSnapshot();
  }

  @override
  Future<void> write({
    required String clientId,
    ClienteProfileResponse? profile,
    List<ClienteTimelineEvent>? timeline,
  }) async {}
}
