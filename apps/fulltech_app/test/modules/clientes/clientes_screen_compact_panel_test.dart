import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  testWidgets('desktop client screen renders compact right panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1366, 768);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = ClienteModel(
      id: 'client-1',
      ownerId: 'owner-1',
      nombre: 'Junior Lopez',
      telefono: '8295319442',
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
            (ref) => _FakeClientesController(ref, client),
          ),
        ],
        child: const MaterialApp(home: ClientesScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('Cliente seleccionado'), findsOneWidget);
    expect(find.text('Junior Lopez'), findsWidgets);
    expect(find.text('Resumen de actividad'), findsOneWidget);
    expect(find.text('Últimos movimientos'), findsOneWidget);
  });
}

class _FakeClientesController extends ClientesController {
  _FakeClientesController(super.ref, ClienteModel client) : super() {
    state = ClientesState(items: [client]);
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
