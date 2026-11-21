import 'dart:async';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/recovery_review_repository.dart';
import 'package:daleventa_pos/features/offline/recovery_reviews_panel.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Admin extends AuthController {
  _Admin(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'owner',
        companyId: 'company',
        email: 'fixture@example.test',
        nombreCompleto: 'Fixture',
        telefono: '',
        role: 'ADMIN',
      ),
    );
  }
}

class _Repository extends RecoveryReviewRepository {
  _Repository() : super(Dio(), OfflineStore.instance);
  int checks = 0;
  String? decision;
  String? note;
  Completer<void>? pending;
  @override
  Future<void> verify(String id) async {
    expect(id, 'review-1');
    checks++;
    await pending?.future;
  }

  @override
  Future<void> decide(
    Map<String, dynamic> row,
    String value,
    String reason,
  ) async {
    expect(row['id'], 'review-1');
    decision = value;
    note = reason;
  }
}

void main() {
  final row = <String, dynamic>{
    'id': 'review-1',
    'actionType': 'cash.close',
    'operationId': 'operation-1',
    'status': 'OPEN',
    'expectedAmount': 7,
    'needsIntervention': true,
  };
  Future<void> mount(
    WidgetTester tester,
    _Repository repository, {
    List<Map<String, dynamic>>? rows,
    Set<String> localSaleAttemptIds = const {},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_Admin.new),
          recoveryReviewRepositoryProvider.overrideWithValue(repository),
          recoveryReviewsProvider.overrideWith((ref) async => rows ?? [row]),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: RecoveryReviewsPanel(localSaleAttemptIds: localSaleAttemptIds)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty reviews add no card or actions', (tester) async {
    await mount(tester, _Repository(), rows: []);
    expect(find.text('Por comprobar'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
  testWidgets('published own sale is not duplicated while another user case remains visible', (tester) async {
    final own = {...row, 'sourceUserId': 'owner', 'sourceActionId': 'local-sale'};
    await mount(tester, _Repository(), rows: [own], localSaleAttemptIds: {'local-sale'});
    expect(find.byType(ExpansionTile), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, _Repository(), rows: [{...own, 'sourceUserId': 'cashier'}], localSaleAttemptIds: {'local-sale'});
    expect(find.byType(ExpansionTile), findsOneWidget);
  });

  testWidgets(
    'verification is a single guarded action and preserves concise status',
    (tester) async {
      final repository = _Repository()..pending = Completer<void>();
      await mount(tester, repository);
      expect(find.text('cash.close'), findsNothing);
      expect(find.text('Cierre de caja'), findsOneWidget);
      expect(find.text('Comprobar registro'), findsNothing);
      await tester.tap(find.text('Cierre de caja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprobar registro'));
      await tester.tap(find.text('Comprobar registro'));
      await tester.pump();
      expect(repository.checks, 1);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      repository.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Revisión actualizada.'), findsOneWidget);
      expect(repository.decision, isNull);
    },
  );

  testWidgets(
    'administrative decision requires an explicit note and cancel writes nothing',
    (tester) async {
      final repository = _Repository();
      await mount(tester, repository);
      await tester.tap(find.text('Cierre de caja'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar pendiente'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar decisión'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'corto');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Guardar decisión'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(repository.decision, isNull);
      await tester.tap(find.text('Eliminar pendiente'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Comprobé el cierre original.',
      );
      await tester.pump();
      await tester.tap(find.text('Guardar decisión'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(repository.decision, 'NOT_PERFORMED');
      expect(repository.note, 'Comprobé el cierre original.');
      expect(tester.takeException(), isNull);
    },
  );
}
