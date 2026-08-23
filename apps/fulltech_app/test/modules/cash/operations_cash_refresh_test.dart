import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/realtime/operations_data_refresh_service.dart';
import 'package:daleventa_pos/core/realtime/operations_realtime_service.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_providers.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simula el servicio realtime (Socket.IO) sin red. Expone streams broadcast
/// que el test dispara manualmente para emular:
///  - `cash.event` (otro dispositivo abrió/cerró turno),
///  - `permissions.reconnect` (el socket se reconectó tras background/caída).
class _FakeOperationsRealtimeService implements OperationsRealtimeService {
  final StreamController<SalesRealtimeMessage> sales = StreamController<
    SalesRealtimeMessage
  >.broadcast();
  final StreamController<CashRealtimeMessage> cash = StreamController<
    CashRealtimeMessage
  >.broadcast();
  final StreamController<PermissionsRealtimeMessage> permissions =
      StreamController<PermissionsRealtimeMessage>.broadcast();

  @override
  Stream<SalesRealtimeMessage> get salesStream => sales.stream;

  @override
  Stream<CashRealtimeMessage> get cashStream => cash.stream;

  @override
  Stream<PermissionsRealtimeMessage> get permissionsStream => permissions.stream;

  @override
  Stream<OperationsRealtimeMessage> get stream =>
      const Stream<OperationsRealtimeMessage>.empty();

  @override
  Stream<ClientsRealtimeMessage> get clientStream =>
      const Stream<ClientsRealtimeMessage>.empty();

  @override
  Stream<Map<String, dynamic>> get whatsappStream =>
      const Stream<Map<String, dynamic>>.empty();

  @override
  Stream<LicenseRealtimeMessage> get licenseStream =>
      const Stream<LicenseRealtimeMessage>.empty();

  @override
  void onWhatsappMessage(void Function(Map<String, dynamic> data) callback) {}

  @override
  Future<void> connect(AuthState authState) async {}

  @override
  void disconnect() {}

  void disposeStreams() {
    sales.close();
    cash.close();
    permissions.close();
  }
}

/// Repositorio fake que registra cuántas veces se consultó el estado al
/// "backend" (fuente de verdad) y permite simular abierto/cerrado/fallo.
class _TrackingCashRepository implements CashRepository {
  int stateCalls = 0;
  CashGateState Function()? stateFactory;

  @override
  bool lastStateFromCache = false;

  @override
  void registerSyncHandlers() {}

  @override
  Future<CashGateState> state() async {
    stateCalls += 1;
    final factory = stateFactory;
    if (factory != null) return factory();
    return const CashGateState(businessDate: '2026-08-22', canOperate: false);
  }

  @override
  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) async {
    throw UnimplementedError('openSession');
  }

  @override
  Future<void> closeSession({
    required double closingAmount,
    String? note,
  }) async {}

  @override
  Future<CashSummaryModel> summary() async {
    throw UnimplementedError('summary');
  }

  @override
  Future<List<CashMovementModel>> movements() async => const [];

  @override
  Future<List<CashMovementModel>> movementHistory({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    int take = 160,
  }) async => const [];

  @override
  Future<List<CashSessionHistoryModel>> closedSessions() async => const [];

  @override
  Future<CashSessionDetailModel> sessionDetail(String id) async {
    throw UnimplementedError('sessionDetail');
  }

  @override
  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {}
}

final _session = ActiveCashSession(
  userId: 'user-1',
  shiftId: 'shift-1',
  openedAt: DateTime.utc(2026, 8, 22, 10),
  status: 'OPEN',
  userName: 'Cajero',
  businessDate: '2026-08-22',
);

ProviderContainer _buildContainer(
  _FakeOperationsRealtimeService realtime,
  _TrackingCashRepository repo,
) {
  return ProviderContainer(
    overrides: [
      operationsRealtimeServiceProvider.overrideWithValue(realtime),
      cashRepositoryProvider.overrideWithValue(repo),
    ],
  );
}

void main() {
  group('OperationsDataRefreshService — revalidación multi-dispositivo', () {
    test(
      'evento realtime cash.event (otro dispositivo abrió/cerró) dispara '
      'refetch silencioso contra el backend', () async {
        final realtime = _FakeOperationsRealtimeService();
        final repo = _TrackingCashRepository();
        final container = _buildContainer(realtime, repo);
        addTearDown(() {
          realtime.disposeStreams();
          container.dispose();
        });

        // Instancia el servicio (se suscribe a los streams).
        container.read(operationsDataRefreshProvider);
        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        final before = repo.stateCalls;
        expect(before, greaterThanOrEqualTo(2)); // constructor + refresh.

        // Otro dispositivo emite evento de caja (p. ej. cerró el turno).
        realtime.cash.add(
          CashRealtimeMessage(
            eventId: 'cash-1',
            type: 'cash.session.closed',
            sessionId: 'shift-1',
          ),
        );
        await pumpEventQueue();

        // El controller reconsultó al backend (fuente de verdad).
        expect(repo.stateCalls, greaterThan(before));
      },
    );

    test(
      'reconexión del socket (permissions.reconnect) dispara refetch: '
      'recupera eventos de caja perdidos en background', () async {
        final realtime = _FakeOperationsRealtimeService();
        final repo = _TrackingCashRepository();
        final container = _buildContainer(realtime, repo);
        addTearDown(() {
          realtime.disposeStreams();
          container.dispose();
        });

        container.read(operationsDataRefreshProvider);
        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        final before = repo.stateCalls;

        // El socket se reconecta tras background/caída de red.
        realtime.permissions.add(
          PermissionsRealtimeMessage(
            eventId: 'perm-1',
            type: 'permissions.reconnect',
            companyId: 'company-1',
            userId: 'user-1',
          ),
        );
        await pumpEventQueue();

        expect(repo.stateCalls, greaterThan(before));
      },
    );

    test(
      'resumed (hook de lifecycle) llama refreshCash(silent) y refetcha: '
      'el turno converge al estado real del backend sin perder snapshot',
      () async {
        final realtime = _FakeOperationsRealtimeService();
        final repo = _TrackingCashRepository();
        // Windows/móvil tenía el turno abierto confirmado.
        repo.stateFactory = () => CashGateState(
          businessDate: '2026-08-22',
          canOperate: true,
          activeSession: _session,
        );
        final container = _buildContainer(realtime, repo);
        addTearDown(() {
          realtime.disposeStreams();
          container.dispose();
        });

        final service = container.read(operationsDataRefreshProvider);
        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        expect(
          container.read(activeCashSessionControllerProvider)
              .valueOrNull?.isOpen,
          isTrue,
        );

        // Mientras estuvo en background otro dispositivo cerró el turno.
        repo.stateFactory = () => const CashGateState(
          businessDate: '2026-08-22',
          canOperate: false,
        );

        // `main.dart _refreshCashOnResume()` ejecuta exactamente esta llamada
        // (AppLifecycleState.resumed → refreshCash(silent: true)).
        final before = repo.stateCalls;
        service.refreshCash(silent: true);
        await pumpEventQueue();

        expect(repo.stateCalls, greaterThan(before));
        expect(
          container.read(activeCashSessionControllerProvider).valueOrNull,
          isNull, // convergió a CERRADO
        );
      },
    );

    test(
      'refetch tras reconexión corrige un turno que pasó a CERRADO '
      '(Windows cerró mientras Android estaba sin conexión)', () async {
        final realtime = _FakeOperationsRealtimeService();
        final repo = _TrackingCashRepository();
        // Android conserva el snapshot viejo "abierto" (caché no sincronizada).
        repo.stateFactory = () => CashGateState(
          businessDate: '2026-08-22',
          canOperate: true,
          activeSession: _session,
          fromCache: true,
        );
        final container = _buildContainer(realtime, repo);
        addTearDown(() {
          realtime.disposeStreams();
          container.dispose();
        });

        // Instancia el servicio (se suscribe a los streams de realtime).
        container.read(operationsDataRefreshProvider);
        final controller = container.read(
          activeCashSessionControllerProvider.notifier,
        );
        await controller.refresh();
        expect(
          container.read(activeCashSessionControllerProvider)
              .valueOrNull?.isOpen,
          isTrue,
        );
        // Snapshot de caché → marcado como "no sincronizado".
        expect(container.read(cashStateUnverifiedProvider), isTrue);

        // Android recupera internet y el socket se reconecta: el backend
        // responde CERRADO (Windows lo cerró).
        repo.stateFactory = () => const CashGateState(
          businessDate: '2026-08-22',
          canOperate: false,
        );
        realtime.permissions.add(
          PermissionsRealtimeMessage(
            eventId: 'perm-2',
            type: 'permissions.reconnect',
            companyId: 'company-1',
            userId: 'user-1',
          ),
        );
        await pumpEventQueue();

        expect(
          container.read(activeCashSessionControllerProvider).valueOrNull,
          isNull, // convergió a CERRADO
        );
        expect(container.read(cashStateUnverifiedProvider), isFalse);
      },
    );
  });
}
