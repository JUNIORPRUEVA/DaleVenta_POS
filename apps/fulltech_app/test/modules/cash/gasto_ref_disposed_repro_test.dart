import 'dart:async';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/core/widgets/app_drawer.dart';
import 'package:daleventa_pos/modules/cash/cash_box_screen.dart';
import 'package:daleventa_pos/modules/cash/cash_close_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_models.dart';
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

UserModel _adminUser() => UserModel(
      id: 'user-a',
      email: 'admin@test.local',
      nombreCompleto: 'Admin Test',
      telefono: '',
      role: 'ADMIN',
      companyId: 'company-a',
      companyName: 'FULLTECH, SRL',
    );

/// Repositorio fake que NO toca la red.
class _FakeCashRepository implements CashRepository {
  int addMovementCalls = 0;

  @override
  bool lastStateFromCache = false;

  @override
  void registerSyncHandlers() {}

  @override
  Future<CashGateState> state() async {
    return CashGateState(
      businessDate: '2026-08-22',
      canOperate: true,
      activeSession: ActiveCashSession(
        userId: 'user-a',
        shiftId: 'shift-1',
        openedAt: DateTime.utc(2026, 8, 22, 10),
        status: 'OPEN',
        userName: 'Admin',
        businessDate: '2026-08-22',
      ),
    );
  }

  @override
  Future<ActiveCashSession> openSession({
    required double openingAmount,
    String? note,
  }) async {
    return ActiveCashSession(
      userId: 'user-a',
      shiftId: 'shift-1',
      openedAt: DateTime.utc(2026, 8, 22, 10),
      status: 'OPEN',
      userName: 'Admin',
      businessDate: '2026-08-22',
    );
  }

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
  Future<void> addMovement({
    required String type,
    required double amount,
    required String reason,
    String movementType = 'expense',
    bool? affectsProfit,
  }) async {
    addMovementCalls += 1;
    // Simula una llamada real que puede tardar un poco.
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  @override
  Future<List<CashSessionHistoryModel>> closedSessions() async => const [];

  @override
  Future<CashSessionDetailModel> sessionDetail(String id) {
    throw UnimplementedError('sessionDetail');
  }

  @override
  Future<List<CashMovementModel>> movementHistory({
    String? type,
    String? movementType,
    DateTime? from,
    DateTime? to,
    int take = 160,
  }) async =>
      const [];
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

ProviderContainer _buildContainer({_FakeCashRepository? repo}) {
  final repository = repo ?? _FakeCashRepository();
  final container = ProviderContainer(
    overrides: [
      authStateProvider.overrideWith(
        (ref) => _FixedAuthController(
          ref,
          AuthState(
            initialized: true,
            isAuthenticated: true,
            user: _adminUser(),
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          ),
        ),
      ),
      cashRepositoryProvider.overrideWithValue(repository),
      companySettingsProvider.overrideWith(
        (ref) async => CompanySettings.empty(),
      ),
      cashCloseTicketPrinterProvider.overrideWithValue(
        _FakeCashCloseTicketPrinter(),
      ),
    ],
  );
  return container;
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
          drawer: AppDrawer(currentUser: _adminUser()),
          body: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Regresión: gastos sin "Bad state: Cannot use ref after disposed"', () {
    testWidgets(
      'flujo "Registrar salida" (gasto) desde el drawer: el drawer se cierra, '
      'se abre el diálogo y al confirmar el gasto se guarda UNA vez y NO '
      'aparece el error de ref dispuesto',
      (tester) async {
        final repo = _FakeCashRepository();
        final container = _buildContainer(repo: repo);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildHost(container));
        await tester.pumpAndSettle();

        // 1. Abrir el drawer (accesible desde Facturación / cualquier pantalla).
        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        expect(find.text('Movimiento efectivo'), findsOneWidget);

        // 2. Expandir el grupo "Movimiento efectivo" y tocar "Registrar salida"
        //    (la acción que registra un gasto/salida).
        await tester.tap(find.text('Movimiento efectivo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Registrar salida'));
        await tester.pumpAndSettle();

        // 3. El drawer ya se cerró (su State se destruyó) y el diálogo está abierto.
        expect(find.text('Registrar salida'), findsWidgets);

        // 4. Completar la acción: monto + motivo y confirmar.
        await tester.enterText(
          find.byType(TextFormField).at(0),
          '500',
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'Compra de material',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Registrar salida'));
        await tester.pumpAndSettle();

        // 5. NO debe aparecer el error de ref dispuesto en la parte inferior.
        expect(
          find.text(
            'Bad state: Cannot use "ref" after the widget was disposed.',
          ),
          findsNothing,
        );

        // 6. El gasto se guarda UNA vez y se confirma con el toast.
        expect(repo.addMovementCalls, 1);
        expect(find.text('Salida registrada'), findsOneWidget);
      },
    );

    testWidgets(
      'control: cancelar el diálogo NO lanza el error y no registra nada',
      (tester) async {
        final repo = _FakeCashRepository();
        final container = _buildContainer(repo: repo);
        addTearDown(container.dispose);

        await tester.pumpWidget(_buildHost(container));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.menu));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Movimiento efectivo'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Registrar salida'));
        await tester.pumpAndSettle();

        // Cancelar el diálogo.
        await tester.tap(find.widgetWithText(OutlinedButton, 'Cancelar'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Bad state: Cannot use "ref" after the widget was disposed.',
          ),
          findsNothing,
        );
        expect(repo.addMovementCalls, 0);
        expect(find.text('Movimiento efectivo'), findsNothing);
      },
    );

    testWidgets(
      'edge case: CashBoxScreen destruida mientras el diálogo está abierto NO '
      'lanza la excepción y el gasto se guarda (controller capturado antes)',
      (tester) async {
        tester.view.physicalSize = const Size(500, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _FakeCashRepository();
        final container = _buildContainer(repo: repo);
        addTearDown(container.dispose);
        final showScreen = ValueNotifier<bool>(true);
        addTearDown(showScreen.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: ValueListenableBuilder<bool>(
                valueListenable: showScreen,
                builder: (context, show, _) =>
                    show ? const CashBoxScreen() : const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Object? capturedError;
        await runZonedGuarded(() async {
          // Abrir el diálogo "Gasto / salida".
          await tester.tap(
            find.widgetWithText(OutlinedButton, 'Gasto / salida'),
          );
          await tester.pumpAndSettle();
          expect(find.text('Registrar salida'), findsWidgets);

          // Destruir CashBoxScreen mientras el diálogo está abierto.
          showScreen.value = false;
          await tester.pumpAndSettle();

          // Completar la acción: confirmar el diálogo.
          await tester.enterText(find.byType(TextFormField).at(0), '500');
          await tester.enterText(
            find.byType(TextFormField).at(1),
            'Compra de material',
          );
          await tester.tap(
            find.widgetWithText(FilledButton, 'Registrar salida'),
          );
          await tester.pumpAndSettle();
        }, (error, stack) {
          capturedError = error;
        });

        // NO debe lanzarse la excepción de ref dispuesto.
        expect(capturedError, isNull);
        expect(repo.addMovementCalls, 1);
      },
    );
  });
}
