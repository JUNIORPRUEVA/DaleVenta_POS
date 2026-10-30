import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_prepare_action.dart';

/// Acción de preparación desde la venta. Estas pruebas fijan la SELECCIÓN de
/// tipo documental: E31 y E32 se ofrecen por separado y la aplicación nunca
/// deduce cuál corresponde. No emiten nada.
class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

void main() {
  UserModel user() => UserModel(
    id: 'user-a',
    email: 'user-a@test.local',
    nombreCompleto: 'Test User',
    telefono: '',
    role: 'ADMIN',
    companyId: 'company-a',
    companyName: 'FULLTECH, SRL',
  );

  Map<String, dynamic> capabilitiesJson({
    bool enabled = true,
    List<String> allowed = const ['E31', 'E32'],
  }) => {
    'enabled': enabled,
    'environment': 'SANDBOX',
    'certificationStatus': 'NOT_STARTED',
    'productionEnabled': false,
    'allowedTypes': allowed,
    'emissionPathAvailable': false,
    'documentTypes': [
      for (final type in const ['E31', 'E32', 'E34'])
        {
          'documentType': type,
          'contractStatus': type == 'E32' ? 'PARTIAL_OFFICIAL' : 'CONFIRMED_OFFICIAL',
          // E32 nunca se asigna desde el rango de la empresa.
          'contractAllowsEmission': type != 'E32',
          'allowedForCompany': allowed.contains(type),
          'allocatable': type != 'E32',
        },
    ],
  };

  late List<Map<String, dynamic>> posts;
  late List<String> paths;

  setUp(() {
    posts = <Map<String, dynamic>>[];
    paths = <String>[];
  });

  Widget harness({
    bool enabled = true,
    List<String> allowed = const ['E31', 'E32'],
  }) {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter((options) async {
        paths.add(options.path);
        if (options.path.endsWith('/capabilities')) {
          return _json(capabilitiesJson(enabled: enabled, allowed: allowed));
        }
        if (options.method == 'POST') {
          final body = Map<String, dynamic>.from(options.data as Map);
          posts.add(body);
          return _json({
            'ok': true,
            'value': {
              'documentId': 'doc-1',
              'documentType': body['documentType'],
              'status': 'LOCAL_VALIDATED',
              'encf': body['documentType'] == 'E32' ? null : 'E310000000001',
            },
          });
        }
        return _json({'total': 0, 'items': <Object>[]});
      });
    return ProviderScope(
      overrides: [
        ecfRepositoryProvider.overrideWithValue(EcfRepository(dio)),
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: true,
              user: user(),
              hasSessionHint: true,
            ),
          ),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: EcfPrepareAction(
            saleId: 'sale-1',
            total: 'DA 59.00',
            customerName: 'Cliente SA',
          ),
        ),
      ),
    );
  }

  FilledButton prepareButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Preparar'));

  Future<void> openDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preparar e-CF'));
    await tester.pumpAndSettle();
  }

  /// Elige la forma de pago fiscal en el primer desplegable del diálogo.
  Future<void> pickPaymentType(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Código 1').last);
    await tester.pumpAndSettle();
  }

  /// El diálogo de resultado se muestra MIENTRAS la acción sigue en curso (el
  /// botón gira un indicador), así que `pumpAndSettle` no terminaría nunca.
  Future<void> pumpRequest(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('offers both types and will not prepare until one is chosen',
      (tester) async {
    await openDialog(tester);

    expect(find.text('E31 · Crédito fiscal'), findsOneWidget);
    expect(find.text('E32 · Consumo'), findsOneWidget);
    // Sin tipo elegido no se puede preparar, aunque la forma de pago esté puesta.
    expect(prepareButton(tester).onPressed, isNull);

    await pickPaymentType(tester);
    expect(prepareButton(tester).onPressed, isNull);

    await tester.tap(find.text('E31 · Crédito fiscal'));
    await tester.pumpAndSettle();
    expect(prepareButton(tester).onPressed, isNotNull);
    expect(posts, isEmpty);
  });

  testWidgets('preparing E32 goes through its own consumo flow',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('E32 · Consumo'));
    await tester.pumpAndSettle();
    // E32 es consumo final: no se pide receptor.
    expect(find.text('Cliente'), findsNothing);
    expect(
      find.textContaining('SIN numeración'),
      findsOneWidget,
    );

    await pickPaymentType(tester);
    await tester.tap(find.text('Preparar'));
    await pumpRequest(tester);

    expect(paths.last, '/ecf/documents/prepare-consumo');
    expect(posts.single['documentType'], 'E32');
    expect(posts.single['saleId'], 'sale-1');
    expect(posts.single['paymentType'], 1);
    expect(find.text('Borrador preparado'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await pumpRequest(tester);
  });

  testWidgets('preparing E31 keeps using the credit-fiscal flow',
      (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('E31 · Crédito fiscal'));
    await tester.pumpAndSettle();
    // E31 sí exige identificar al receptor.
    expect(find.text('Cliente'), findsOneWidget);

    await pickPaymentType(tester);
    await tester.tap(find.text('Preparar'));
    await pumpRequest(tester);

    expect(paths.last, '/ecf/documents/prepare');
    expect(posts.single['documentType'], 'E31');
    expect(find.text('Borrador preparado'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await pumpRequest(tester);
  });

  testWidgets('with only one type enabled there is nothing to choose',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(allowed: const ['E31']));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preparar e-CF'));
    await tester.pumpAndSettle();

    expect(find.text('E32 · Consumo'), findsNothing);
    expect(find.text('E31 · Crédito fiscal'), findsOneWidget);

    await pickPaymentType(tester);
    await tester.tap(find.text('Preparar'));
    await pumpRequest(tester);

    expect(posts.single['documentType'], 'E31');

    await tester.tap(find.text('Entendido'));
    await pumpRequest(tester);
  });

  testWidgets('a company with e-CF off sees no e-CF action at all',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(enabled: false));
    await tester.pumpAndSettle();

    expect(find.text('Preparar e-CF'), findsNothing);
  });

  testWidgets('a company with no allowed types sees no e-CF action either',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness(allowed: const []));
    await tester.pumpAndSettle();

    expect(find.text('Preparar e-CF'), findsNothing);
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
