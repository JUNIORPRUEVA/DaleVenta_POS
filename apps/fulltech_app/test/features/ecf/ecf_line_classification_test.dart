import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_line_classification_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Clasificación fiscal supervisada (F1) — contrato Flutter.
///
/// Lo que se fija aquí:
///
///  * el cliente habla con las rutas REALES del backend y **nunca** envía un
///    `companyId` (el ámbito lo impone la sesión);
///  * la pantalla no decide nada por su cuenta: muestra lo que el backend dice;
///  * sin permiso no se ofrece una acción que el servidor rechazaría;
///  * confirmar una clasificación no se presenta nunca como emisión ni como
///    aprobación de la DGII.
void main() {
  group('repositorio', () {
    late RequestOptions? captured;

    EcfRepository repositoryWith(Object body, {int status = 200}) {
      final dio = Dio()
        ..httpClientAdapter = _RecordingAdapter((options) async {
          captured = options;
          return ResponseBody.fromString(
            jsonEncode(body),
            status,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        });
      return EcfRepository(dio);
    }

    test('lee las partidas pendientes de la ruta real', () async {
      final repository = repositoryWith({
        'saleId': 'sale-1',
        'fiscallyFrozen': false,
        'lines': [
          {
            'saleItemId': 'item-1',
            'name': 'Servicio suelto',
            'quantity': '2',
            'unitPrice': '50',
            'needsClassification': true,
            'canConfirm': true,
          },
          {
            'saleItemId': 'item-2',
            'name': 'Producto con bien',
            'quantity': '1',
            'unitPrice': '118',
            'needsClassification': false,
            'canConfirm': false,
            'effectiveClassification': 'PRODUCT',
          },
        ],
      });

      final state = await repository.pendingClassifications('sale-1');

      expect(captured?.method, 'GET');
      expect(captured?.path, '/ecf/documents/sale-1/pending-classifications');
      expect(state.fiscallyFrozen, isFalse);
      expect(state.lines, hasLength(2));
      // Solo una sigue necesitando clasificación.
      expect(state.pending, hasLength(1));
      expect(state.pending.single.name, 'Servicio suelto');
      expect(state.pending.single.statusLabel, 'Sin clasificar');
      expect(state.lines[1].statusLabel, 'Bien');
    });

    test('confirmar envía el cuerpo del contrato y sin companyId', () async {
      final repository = repositoryWith({
        'classification': {'id': 'c1', 'saleItemId': 'item-1'},
        'sale': {
          'saleId': 'sale-1',
          'fiscallyFrozen': false,
          'lines': [
            {
              'saleItemId': 'item-1',
              'name': 'Servicio suelto',
              'quantity': '2',
              'unitPrice': '50',
              'needsClassification': false,
              'canConfirm': false,
              'effectiveClassification': 'SERVICE',
            },
          ],
        },
      });

      final state = await repository.confirmLineClassification(
        saleId: 'sale-1',
        saleItemId: 'item-1',
        classification: 'SERVICE',
        reason: 'Es mano de obra',
      );

      expect(captured?.method, 'POST');
      expect(captured?.path, '/ecf/documents/line-classifications');
      expect(captured?.data, {
        'saleId': 'sale-1',
        'saleItemId': 'item-1',
        'classification': 'SERVICE',
        'reason': 'Es mano de obra',
      });
      // El ámbito de empresa sale de la sesión, nunca del cliente.
      expect((captured?.data as Map).containsKey('companyId'), isFalse);
      // El estado que se muestra es el que devuelve el servidor.
      expect(state.pending, isEmpty);
      expect(state.lines.single.statusLabel, 'Servicio');
    });

    test('una partida ya clasificada deja de estar pendiente', () {
      final state = EcfPendingClassifications.fromJson({
        'saleId': 'sale-1',
        'fiscallyFrozen': true,
        'lines': [
          {
            'saleItemId': 'item-1',
            'name': 'Servicio suelto',
            'needsClassification': false,
            'canConfirm': false,
            'effectiveClassification': 'PRODUCT',
          },
        ],
      });

      expect(state.fiscallyFrozen, isTrue);
      expect(state.pending, isEmpty);
      // Congelado por envío: la interfaz lo sabe porque el backend lo dijo.
      expect(state.lines.single.fiscallyFrozen, isTrue);
      expect(state.lines.single.canConfirm, isFalse);
    });
  });

  group('diálogo', () {
    UserModel user(Set<String> permissions) => UserModel(
      id: 'u1',
      email: 'op@test.local',
      nombreCompleto: 'Operador',
      telefono: '',
      role: 'VENDEDOR',
      companyId: 'company-a',
      companyName: 'FULLTECH, SRL',
      userPermissions: {for (final p in permissions) p: true},
    );

    Widget harness({
      required UserModel currentUser,
      required EcfPendingClassifications state,
      Object? error,
    }) {
      return ProviderScope(
        key: UniqueKey(),
        overrides: [
          ecfPendingClassificationsProvider('sale-1').overrideWith((ref) async {
            if (error != null) throw error;
            return state;
          }),
          authStateProvider.overrideWith(
            (ref) => _FixedAuth(ref, currentUser),
          ),
        ],
        child: const MaterialApp(
          home: EcfLineClassificationDialog(saleId: 'sale-1'),
        ),
      );
    }

    const pendingState = EcfPendingClassifications(
      saleId: 'sale-1',
      fiscallyFrozen: false,
      lines: [
        EcfPendingClassificationLine(
          saleItemId: 'item-1',
          name: 'Servicio suelto',
          quantity: '2',
          unitPrice: '50',
          needsClassification: true,
          canConfirm: true,
        ),
      ],
    );

    testWidgets('explica el bloqueo y ofrece revisar al autorizado', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          currentUser: user(const {'confirmEcfLineClassification'}),
          state: pendingState,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'necesita clasificación fiscal antes de preparar el comprobante',
        ),
        findsOneWidget,
      );
      expect(find.text('Servicio suelto'), findsOneWidget);
      expect(find.text('Clasificación: Sin clasificar'), findsOneWidget);
      expect(find.text('Clasificar Servicio suelto'), findsOneWidget);
      // Nunca se insinúa emisión ni aprobación de la DGII.
      expect(find.textContaining('emitido'), findsNothing);
      expect(find.textContaining('DGII aprobado'), findsNothing);
    });

    testWidgets('sin permiso no ofrece la acción y dice por qué', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(currentUser: user(const {}), state: pendingState),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clasificar Servicio suelto'), findsNothing);
      expect(
        find.textContaining('Necesitas el permiso de clasificación fiscal'),
        findsOneWidget,
      );
    });

    testWidgets('el motivo es obligatorio y la clasificación también', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          currentUser: user(const {'confirmEcfLineClassification'}),
          state: pendingState,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Clasificar Servicio suelto'));
      await tester.pumpAndSettle();
      expect(find.text('Clasificación fiscal de la partida'), findsOneWidget);
      expect(find.textContaining('no emite nada'), findsOneWidget);

      // Sin elegir nada, no deja confirmar.
      await tester.tap(find.text('Confirmar clasificación'));
      await tester.pumpAndSettle();
      expect(find.text('Elige BIEN o SERVICIO'), findsOneWidget);

      // Eligiendo el tipo pero sin motivo, tampoco.
      await tester.tap(find.text('Clasificación'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servicio').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar clasificación'));
      await tester.pumpAndSettle();
      expect(
        find.text('El motivo es obligatorio (mínimo 3 caracteres)'),
        findsOneWidget,
      );
    });

    testWidgets('si el comprobante ya salió, lo dice y no deja confirmar', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          currentUser: user(const {'confirmEcfLineClassification'}),
          state: const EcfPendingClassifications(
            saleId: 'sale-1',
            fiscallyFrozen: true,
            lines: [
              EcfPendingClassificationLine(
                saleItemId: 'item-1',
                name: 'Servicio suelto',
                quantity: '2',
                unitPrice: '50',
                needsClassification: true,
                canConfirm: false,
                fiscallyFrozen: true,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('ya salió del equipo'),
        findsOneWidget,
      );
      // El backend dijo que no se puede: no se ofrece el botón.
      expect(find.text('Clasificar Servicio suelto'), findsNothing);
    });

    testWidgets('un fallo de consulta ofrece reintentar', (tester) async {
      await tester.pumpWidget(
        harness(
          currentUser: user(const {'confirmEcfLineClassification'}),
          state: pendingState,
          error: Exception('boom'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se pudo consultar el estado'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('ventana estrecha: se ve sin desbordes', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        harness(
          currentUser: user(const {'confirmEcfLineClassification'}),
          state: pendingState,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Servicio suelto'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FixedAuth extends AuthController {
  _FixedAuth(super.ref, UserModel currentUser) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: currentUser,
      hasSessionHint: true,
    );
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}
