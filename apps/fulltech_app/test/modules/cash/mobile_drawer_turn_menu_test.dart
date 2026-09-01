import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/core/realtime/operations_data_refresh_service.dart';
import 'package:daleventa_pos/core/realtime/operations_realtime_service.dart';
import 'package:daleventa_pos/core/widgets/app_drawer.dart';
import 'package:daleventa_pos/modules/cash/cash_close_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
import 'package:daleventa_pos/modules/cash/cash_providers.dart';
import 'package:daleventa_pos/modules/cash/cash_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// AuthController con estado fijo para el test (sin bootstrap real).
class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

UserModel _cashierUser() => UserModel(
  id: 'user-a',
  email: 'cajero@test.local',
  nombreCompleto: 'Cajero Test',
  telefono: '',
  role: 'CAJERO',
  companyId: 'company-a',
  companyName: 'FULLTECH, SRL',
);

final _openSession = ActiveCashSession(
  userId: 'user-a',
  shiftId: 'shift-1',
  openedAt: DateTime.utc(2026, 8, 22, 10),
  status: 'OPEN',
  userName: 'Cajero',
  businessDate: '2026-08-22',
);

/// Repositorio fake con estado controlable: permite simular abierto/cerrado,
/// desde caché (no sincronizado), etc. y disparar el refresh del controller.
class _DrawerCashRepository implements CashRepository {
  CashGateState Function()? stateFactory;

  @override
  bool lastStateFromCache = false;

  @override
  void registerSyncHandlers() {}

  @override
  Future<CashGateState> state() async {
    final factory = stateFactory;
    if (factory != null) return factory();
    return const CashGateState(businessDate: '2026-08-22', canOperate: false);
  }

  @override
  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) async => _openSession;

  @override
  Future<void> closeSession({
    required double closingAmount,
    String? note,
  }) async {}

  @override
  Future<CashSummaryModel> summary() async => const CashSummaryModel(
    openingAmount: 0,
    totalSales: 0,
    totalExpenses: 0,
    totalWithdrawals: 0,
    cashInManual: 0,
    cashOutManual: 0,
    creditAbonos: 0,
    creditSalesTotal: 0,
    creditInitialCash: 0,
    creditInitialTransfer: 0,
    creditBalanceTotal: 0,
    creditPaymentCash: 0,
    creditPaymentTransfer: 0,
    salesCashTotal: 0,
    salesTransferTotal: 0,
    refundsCash: 0,
    expectedCash: 100,
    totalTickets: 0,
    totalRefunds: 0,
    categorySummary: [],
  );

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
  Future<CashSessionDetailModel> sessionDetail(String id) {
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

class _FakeCashCloseTicketPrinter implements CashCloseTicketPrinter {
  @override
  Future<PrintTicketResult> printCloseTicket(
    CashCloseTicketSnapshot snapshot, {
    bool automatic = true,
  }) async {
    return const PrintTicketResult(success: true, message: 'Impreso');
  }

  @override
  Future<PrintTicketResult> printHistoryTicket(CashSessionHistoryModel row) {
    throw UnimplementedError('printHistoryTicket');
  }

  @override
  List<String> buildLines(CashCloseTicketSnapshot snapshot) => const [];

  @override
  List<String> buildHistoryLines(CashSessionHistoryModel row) => const [];
}

/// Simula el servicio realtime (Socket.IO) sin red. Emula el evento
/// `cash.event` que el backend emite a TODOS los sockets del company room.
class _FakeOperationsRealtimeService implements OperationsRealtimeService {
  final StreamController<CashRealtimeMessage> cash =
      StreamController<CashRealtimeMessage>.broadcast();
  final StreamController<SalesRealtimeMessage> sales =
      StreamController<SalesRealtimeMessage>.broadcast();
  final StreamController<PermissionsRealtimeMessage> permissions =
      StreamController<PermissionsRealtimeMessage>.broadcast();

  @override
  Stream<CashRealtimeMessage> get cashStream => cash.stream;

  @override
  Stream<SalesRealtimeMessage> get salesStream => sales.stream;

  @override
  Stream<PermissionsRealtimeMessage> get permissionsStream =>
      permissions.stream;

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
    cash.close();
    sales.close();
    permissions.close();
  }
}

ProviderContainer _buildContainer(
  _DrawerCashRepository repo, {
  _FakeOperationsRealtimeService? realtime,
}) {
  return ProviderContainer(
    overrides: [
      if (realtime != null)
        operationsRealtimeServiceProvider.overrideWithValue(realtime),
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: _cashierUser(),
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          ),
        ),
      ),
      cashRepositoryProvider.overrideWithValue(repo),
      companySettingsProvider.overrideWith(
        (ref) async => CompanySettings.empty(),
      ),
      cashCloseTicketPrinterProvider.overrideWithValue(
        _FakeCashCloseTicketPrinter(),
      ),
    ],
  );
}

Widget _buildHost(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leading: Builder(
              builder: (buttonContext) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(buttonContext).openDrawer(),
              ),
            ),
          ),
          drawer: AppDrawer(currentUser: _cashierUser()),
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.menu));
  await tester.pumpAndSettle();
}

/// Expande el grupo "Turno" del drawer (el usuario lo despliega para ver los
/// ítems de turno). El header del grupo se titula exactamente "Turno".
Future<void> _expandTurnGroup(WidgetTester tester) async {
  await tester.tap(find.text('Turno'));
  await tester.pumpAndSettle();
}

void main() {
  group('Drawer móvil — grupo Turno reactivo', () {
    testWidgets('Test 1 — turno CERRADO: solo "Abrir turno" + historial', (
      tester,
    ) async {
      final repo = _DrawerCashRepository()
        ..stateFactory = () =>
            const CashGateState(businessDate: '2026-08-22', canOperate: false);
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildHost(container));
      await _openDrawer(tester);
      await _expandTurnGroup(tester);

      expect(find.text('Abrir turno'), findsOneWidget);
      expect(find.text('Historial de turnos'), findsWidgets);
      expect(find.text('Cerrar turno'), findsNothing);
      expect(find.text('Turno actual'), findsNothing);
    });

    testWidgets('Test 2 — turno ABIERTO: "Turno actual" + "Cerrar turno"', (
      tester,
    ) async {
      final repo = _DrawerCashRepository()
        ..stateFactory = () => CashGateState(
          businessDate: '2026-08-22',
          canOperate: true,
          activeSession: _openSession,
        );
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildHost(container));
      await _openDrawer(tester);
      await _expandTurnGroup(tester);

      expect(find.text('Turno actual'), findsOneWidget);
      expect(find.text('Cerrar turno'), findsOneWidget);
      expect(find.text('Historial de turnos'), findsWidgets);
      expect(find.text('Abrir turno'), findsNothing);
    });

    testWidgets('Test 3 — abierto → cerrado sin recrear la app', (
      tester,
    ) async {
      final repo = _DrawerCashRepository()
        ..stateFactory = () => CashGateState(
          businessDate: '2026-08-22',
          canOperate: true,
          activeSession: _openSession,
        );
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildHost(container));
      await _openDrawer(tester);
      await _expandTurnGroup(tester);
      expect(find.text('Cerrar turno'), findsOneWidget);

      // Otro dispositivo (Windows) cierra el turno → backend responde CERRADO.
      repo.stateFactory = () =>
          const CashGateState(businessDate: '2026-08-22', canOperate: false);
      await container
          .read(activeCashSessionControllerProvider.notifier)
          .refresh();
      await tester.pumpAndSettle();

      expect(find.text('Cerrar turno'), findsNothing);
      expect(find.text('Turno actual'), findsNothing);
      expect(find.text('Abrir turno'), findsOneWidget);
      expect(find.text('Historial de turnos'), findsWidgets);
    });

    testWidgets('Test 4 — cerrado → abierto sin recrear la app', (
      tester,
    ) async {
      final repo = _DrawerCashRepository()
        ..stateFactory = () =>
            const CashGateState(businessDate: '2026-08-22', canOperate: false);
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildHost(container));
      await _openDrawer(tester);
      await _expandTurnGroup(tester);
      expect(find.text('Abrir turno'), findsOneWidget);

      // Este dispositivo (u otro) abre el turno → backend responde ABIERTO.
      repo.stateFactory = () => CashGateState(
        businessDate: '2026-08-22',
        canOperate: true,
        activeSession: _openSession,
      );
      await container
          .read(activeCashSessionControllerProvider.notifier)
          .refresh();
      await tester.pumpAndSettle();

      expect(find.text('Abrir turno'), findsNothing);
      expect(find.text('Turno actual'), findsOneWidget);
      expect(find.text('Cerrar turno'), findsOneWidget);
    });

    testWidgets('Test 5 — NO SINCRONIZADO: no se presenta acción crítica', (
      tester,
    ) async {
      final repo = _DrawerCashRepository()
        ..stateFactory = () => CashGateState(
          businessDate: '2026-08-22',
          canOperate: true,
          activeSession: _openSession,
          fromCache: true,
        );
      final container = _buildContainer(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_buildHost(container));
      await _openDrawer(tester);
      await _expandTurnGroup(tester);

      // Estado desde caché/no verificado: NO mostrar "Cerrar turno" ni
      // "Abrir turno" como confirmados; solo un ítem neutro deshabilitado
      // + historial (estado no sincronizado).
      expect(find.text('Estado del turno no disponible'), findsOneWidget);
      expect(find.text('Cerrar turno'), findsNothing);
      expect(find.text('Abrir turno'), findsNothing);
      expect(find.text('Turno actual'), findsNothing);
      expect(find.text('Historial de turnos'), findsWidgets);
    });

    testWidgets(
      'Test 6 — cambio de empresa: Empresa A abierta → Empresa B cerrada '
      'muestra "Abrir turno"',
      (tester) async {
        final repo = _DrawerCashRepository()
          ..stateFactory = () => CashGateState(
            businessDate: '2026-08-22',
            canOperate: true,
            activeSession: _openSession,
          );
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildHost(container));
        await _openDrawer(tester);
        await _expandTurnGroup(tester);
        expect(find.text('Cerrar turno'), findsOneWidget);

        // Cambio de empresa (equivale a logout+login): se invalida el estado y
        // la nueva empresa no tiene turno abierto.
        repo.stateFactory = () =>
            const CashGateState(businessDate: '2026-08-22', canOperate: false);
        container.invalidate(activeCashSessionControllerProvider);
        await tester.pumpAndSettle();

        expect(find.text('Abrir turno'), findsOneWidget);
        expect(find.text('Cerrar turno'), findsNothing);
      },
    );

    testWidgets(
      'Test 7 — logout/login: usuario B no hereda el turno de usuario A',
      (tester) async {
        final repo = _DrawerCashRepository()
          ..stateFactory = () => CashGateState(
            businessDate: '2026-08-22',
            canOperate: true,
            activeSession: _openSession,
          );
        final container = _buildContainer(repo);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildHost(container));
        await _openDrawer(tester);
        await _expandTurnGroup(tester);
        expect(find.text('Cerrar turno'), findsOneWidget);

        // Logout → se invalida todo el estado de caja. Usuario B no tiene turno.
        repo.stateFactory = () =>
            const CashGateState(businessDate: '2026-08-22', canOperate: false);
        container.invalidate(activeCashSessionControllerProvider);
        await tester.pumpAndSettle();

        expect(find.text('Cerrar turno'), findsNothing);
        expect(find.text('Turno actual'), findsNothing);
        expect(find.text('Abrir turno'), findsOneWidget);
      },
    );

    testWidgets(
      'Test D — drawer montado abierto → evento realtime (otro dispositivo '
      'cerró) → cambia a "Abrir turno" sin recrear la app',
      (tester) async {
        final realtime = _FakeOperationsRealtimeService();
        final repo = _DrawerCashRepository()
          ..stateFactory = () => CashGateState(
            businessDate: '2026-08-22',
            canOperate: true,
            activeSession: _openSession,
          );
        final container = _buildContainer(repo, realtime: realtime);
        addTearDown(() {
          realtime.disposeStreams();
          container.dispose();
        });

        await tester.pumpWidget(_buildHost(container));
        // Mantener vivo el servicio que reacciona a los eventos realtime.
        container.read(operationsDataRefreshProvider);
        await _openDrawer(tester);
        await _expandTurnGroup(tester);
        expect(find.text('Cerrar turno'), findsOneWidget);

        // Windows cierra el turno → backend responde CERRADO.
        repo.stateFactory = () =>
            const CashGateState(businessDate: '2026-08-22', canOperate: false);
        // El backend emite cash.event al room; el servicio lo recibe y hace
        // refresh silencioso → el drawer (montado) se reconstruye.
        realtime.cash.add(
          CashRealtimeMessage(
            eventId: 'cash-ev-1',
            type: 'cash.session.closed',
            sessionId: 'shift-1',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Cerrar turno'), findsNothing);
        expect(find.text('Turno actual'), findsNothing);
        expect(find.text('Abrir turno'), findsOneWidget);
        expect(find.text('Historial de turnos'), findsWidgets);
      },
    );

    testWidgets(
      'Test E — drawer montado cerrado → evento realtime (otro dispositivo '
      'abrió) → cambia a "Cerrar turno" sin recrear la app',
      (tester) async {
        final realtime = _FakeOperationsRealtimeService();
        final repo = _DrawerCashRepository()
          ..stateFactory = () => const CashGateState(
            businessDate: '2026-08-22',
            canOperate: false,
          );
        final container = _buildContainer(repo, realtime: realtime);
        addTearDown(() {
          realtime.disposeStreams();
          container.dispose();
        });

        await tester.pumpWidget(_buildHost(container));
        container.read(operationsDataRefreshProvider);
        await _openDrawer(tester);
        await _expandTurnGroup(tester);
        expect(find.text('Abrir turno'), findsOneWidget);

        // Android/iPhone abre el turno → backend responde ABIERTO.
        repo.stateFactory = () => CashGateState(
          businessDate: '2026-08-22',
          canOperate: true,
          activeSession: _openSession,
        );
        realtime.cash.add(
          CashRealtimeMessage(
            eventId: 'cash-ev-2',
            type: 'cash.session.opened',
            sessionId: 'shift-1',
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Abrir turno'), findsNothing);
        expect(find.text('Turno actual'), findsOneWidget);
        expect(find.text('Cerrar turno'), findsOneWidget);
      },
    );
  });
}
