import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_credit_note_action.dart';

/// Acción E34: estas pruebas fijan la INTERFAZ (qué se muestra, qué se bloquea
/// y qué se envía), no solo el transporte HTTP. No emiten nada: el backend
/// únicamente reserva crédito fiscal y crea un borrador.
void main() {
  late List<String> paths;
  late List<Map<String, dynamic>> prepared;

  EcfRepository repository() {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter((options) async {
        paths.add(options.path);
        if (options.path.endsWith('/prepare-credit-note')) {
          prepared.add(Map<String, dynamic>.from(options.data as Map));
          return _json({
            'ok': true,
            'value': {
              'documentId': 'credit-1',
              'documentType': 'E34',
              'status': 'LOCAL_VALIDATED',
              'encf': 'E340000000001',
            },
          });
        }
        return _json({'total': 0, 'items': <Object>[]});
      });
    return EcfRepository(dio);
  }

  setUp(() {
    paths = <String>[];
    prepared = <Map<String, dynamic>>[];
  });

  Widget harness() => ProviderScope(
    overrides: [ecfRepositoryProvider.overrideWithValue(repository())],
    child: const MaterialApp(
      home: Scaffold(
        body: EcfCreditNoteAction(
          originalId: 'original-1',
          originalLabel: 'E31 E310000000001',
          availableAmount: 'DA 237.00',
        ),
      ),
    ),
  );

  FilledButton confirmButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Preparar nota'));

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.tap(find.text('Nota de crédito'));
    await tester.pumpAndSettle();
  }

  /// El diálogo de resultado se muestra MIENTRAS la acción sigue en curso
  /// (spinner girando), así que no se puede usar `pumpAndSettle` aquí.
  Future<void> settleRequest(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  const uuidV4 =
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';

  testWidgets('shows the original and its available balance before acting',
      (tester) async {
    await open(tester);

    expect(find.text('Nota de crédito (E34)'), findsOneWidget);
    expect(find.text('E31 E310000000001'), findsOneWidget);
    expect(find.text('DA 237.00'), findsOneWidget);
    // Abrir el diálogo no debe enviar nada.
    expect(paths, isEmpty);
  });

  testWidgets('will not prepare without a modification reason', (tester) async {
    await open(tester);

    expect(confirmButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'Anulación total');
    await tester.pump();

    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('a TOTAL credit note copies the original and sends a fresh id',
      (tester) async {
    await open(tester);

    await tester.enterText(find.byType(TextField).last, 'Anulación total');
    await tester.pump();
    await tester.tap(find.text('Preparar nota'));
    await settleRequest(tester);

    expect(find.text('Nota preparada'), findsOneWidget);
    expect(find.text('E340000000001'), findsOneWidget);

    final body = prepared.single;
    expect(body['originalDocumentId'], 'original-1');
    expect(body['refundKind'], 'TOTAL');
    // TOTAL no manda líneas: el servidor copia el original.
    expect(body.containsKey('lines'), isFalse);
    expect(
      RegExp(uuidV4).hasMatch(body['clientRequestId'] as String),
      isTrue,
      reason: 'cada operación necesita su propio clientRequestId',
    );

    await tester.tap(find.text('Entendido'));
    await settleRequest(tester);
  });

  testWidgets('a PARTIAL credit note sends only the lines the user typed',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Parcial'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '2:1');
    await tester.enterText(find.byType(TextField).last, 'Devolución parcial');
    await tester.pump();

    await tester.tap(find.text('Preparar nota'));
    await settleRequest(tester);

    final body = prepared.single;
    expect(body['refundKind'], 'PARTIAL');
    expect(body['lines'], [
      {'lineNumber': 2, 'quantity': '1'},
    ]);
    // El usuario elige QUÉ acredita, nunca la clasificación ni el precio.
    expect(body['modificationReason'], 'Devolución parcial');

    await tester.tap(find.text('Entendido'));
    await settleRequest(tester);
  });

  testWidgets('an unreadable line blocks a PARTIAL credit note',
      (tester) async {
    await open(tester);

    await tester.tap(find.text('Parcial'));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'sin formato');
    await tester.enterText(find.byType(TextField).last, 'Devolución parcial');
    await tester.pump();

    expect(confirmButton(tester).onPressed, isNull);
    expect(paths, isEmpty);
  });

  testWidgets('a rejected credit note surfaces the safe message, not a crash',
      (tester) async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (_) async => _json({
          'ok': false,
          'code': 'E34_INSUFFICIENT_FISCAL_BALANCE',
          'safeMessage': 'La cantidad supera el saldo acreditable del original.',
        }),
      );

    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfRepositoryProvider.overrideWithValue(EcfRepository(dio)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: EcfCreditNoteAction(
              originalId: 'original-1',
              originalLabel: 'E31 E310000000001',
              availableAmount: 'DA 237.00',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Nota de crédito'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Devolución parcial');
    await tester.pump();
    await tester.tap(find.text('Preparar nota'));
    await settleRequest(tester);

    expect(find.text('No se pudo preparar'), findsOneWidget);
    expect(find.text('E34_INSUFFICIENT_FISCAL_BALANCE'), findsOneWidget);
    expect(
      find.text('La cantidad supera el saldo acreditable del original.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Entendido'));
    await settleRequest(tester);
  });
}

ResponseBody _json(Object body, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
