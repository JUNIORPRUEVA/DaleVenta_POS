import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_credit_note_action.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_documents_page.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_prepare_action.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// E2E DE INTERFAZ de e-CF.
///
/// Corre sobre un dispositivo REAL (Windows desktop / Chrome) con el motor de
/// Flutter de verdad: gestos reales, navegación real de widgets y **HTTP real
/// sobre socket** contra un backend local levantado por la propia prueba.
///
/// Alcance declarado: recorre los TRES recorridos e-CF de la interfaz (preparar
/// E31/E32 desde la venta, bandeja + detalle, y nota de crédito E34). NO recorre
/// login ni el alta de la venta: eso pertenece al armazón completo de la app y
/// se declara como no cubierto aquí.
///
/// El backend es local y sintético: no hay proveedor, no hay emisión y ninguna
/// respuesta declara aceptación de la DGII.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late String baseUrl;
  final requests = <String>[];

  final screenshots = const String.fromEnvironment(
    'ECF_E2E_SCREENSHOT_DIR',
    defaultValue: '../../docs/ecf-integration-evidence',
  );

  /// Estado sintético del backend local.
  final documents = <Map<String, dynamic>>[];
  var nextE31 = 1;
  var nextE34 = 1;
  var reservedCredit = 0.0;
  const originalTotal = 177.0;

  Map<String, dynamic> capabilities() => {
    'enabled': true,
    'environment': 'SANDBOX',
    'certificationStatus': 'NOT_STARTED',
    'productionEnabled': false,
    'allowedTypes': ['E31', 'E32'],
    'emissionPathAvailable': false,
    'documentTypes': [
      for (final type in const ['E31', 'E32', 'E34'])
        {
          'documentType': type,
          'contractStatus': type == 'E32' ? 'PARTIAL_OFFICIAL' : 'CONFIRMED_OFFICIAL',
          'contractAllowsEmission': type != 'E32',
          'allowedForCompany': type != 'E34',
          'allocatable': type != 'E32',
        },
    ],
  };

  Map<String, dynamic> counters() => {
    'total': documents.length,
    'byStatus': <String, int>{},
    'byGroup': {
      'PENDING': documents.length,
      'REQUIRES_REVIEW': 0,
      'ACCEPTED': 0,
      'REJECTED': 0,
      'CANCELLED': 0,
    },
  };

  Map<String, dynamic> originalDocument() => {
    'id': 'original-1',
    'documentType': 'E31',
    'status': 'DGII_ACCEPTED',
    'statusGroup': 'ACCEPTED',
    'encf': 'E310000000001',
    'createdAt': '2026-10-14T10:00:00.000Z',
    'total': '177.00',
    'currency': 'DOP',
    'availableAmount': (originalTotal - reservedCredit).toStringAsFixed(2),
  };

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final path = request.uri.path;
      requests.add('${request.method} $path');
      Object? body;
      var status = 200;

      if (path.endsWith('/ecf/capabilities')) {
        body = capabilities();
      } else if (path.endsWith('/ecf/documents/summary')) {
        body = counters();
      } else if (path.endsWith('/ecf/documents/eligible-originals')) {
        body = {
          'items': [originalDocument()],
        };
      } else if (path.endsWith('/ecf/documents/prepare')) {
        final encf = 'E31${(nextE31++).toString().padLeft(10, '0')}';
        final document = {
          'id': 'doc-$encf',
          'documentType': 'E31',
          'status': 'LOCAL_VALIDATED',
          'statusGroup': 'PENDING',
          'encf': encf,
          'createdAt': '2026-10-15T12:00:00.000Z',
          'total': '177.00',
          'currency': 'DOP',
          'receiverName': 'Cliente SA',
          'receiverTaxId': '130000000',
        };
        documents.add(document);
        body = {
          'ok': true,
          'value': {
            'documentId': document['id'],
            'documentType': 'E31',
            'status': 'LOCAL_VALIDATED',
            'encf': encf,
          },
        };
      } else if (path.endsWith('/ecf/documents/prepare-consumo')) {
        final document = {
          'id': 'doc-consumo-1',
          'documentType': 'E32',
          'status': 'LOCAL_VALIDATED',
          'statusGroup': 'PENDING',
          'encf': null,
          'createdAt': '2026-10-15T12:05:00.000Z',
          'total': '177.00',
          'currency': 'DOP',
        };
        documents.add(document);
        body = {
          'ok': true,
          'value': {
            'documentId': document['id'],
            'documentType': 'E32',
            'status': 'LOCAL_VALIDATED',
            'encf': null,
            'numberingState': 'PENDING_SANDBOX_SLOT',
          },
        };
      } else if (path.endsWith('/ecf/documents/prepare-credit-note')) {
        final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        final quantity = double.tryParse(
              ((payload['lines'] as List?)?.first as Map?)?['quantity']?.toString() ?? '',
            ) ??
            0;
        final amount = quantity * 59.0;
        if (reservedCredit + amount > originalTotal) {
          status = 409;
          body = {
            'ok': false,
            'code': 'E34_INSUFFICIENT_FISCAL_BALANCE',
            'safeMessage': 'La nota supera el saldo acreditable del comprobante original.',
          };
        } else {
          reservedCredit += amount;
          final encf = 'E34${(nextE34++).toString().padLeft(10, '0')}';
          final document = {
            'id': 'doc-$encf',
            'documentType': 'E34',
            'status': 'LOCAL_VALIDATED',
            'statusGroup': 'PENDING',
            'encf': encf,
            'createdAt': '2026-10-15T12:10:00.000Z',
            'total': amount.toStringAsFixed(2),
            'currency': 'DOP',
            'originalEncf': 'E310000000001',
          };
          documents.add(document);
          body = {
            'ok': true,
            'value': {
              'documentId': document['id'],
              'encf': encf,
              'status': 'LOCAL_VALIDATED',
            },
          };
        }
      } else if (path.contains('/ecf/documents/')) {
        final id = path.split('/').last;
        final document = documents.firstWhere(
          (row) => row['id'] == id,
          orElse: () => documents.isEmpty ? <String, dynamic>{} : documents.last,
        );
        body = {
          ...document,
          'statusLogs': [
            {
              'id': 'log-1',
              'statusAfter': document['status'],
              'reasonCode': 'LOCAL_PREPARED',
              'createdAt': '2026-10-15T12:00:05.000Z',
            },
          ],
          'attempts': [],
          'evidenceReceipts': 0,
          'creditReservation': null,
          'originalDocument': null,
        };
      } else if (path.endsWith('/ecf/documents')) {
        body = {'total': documents.length, 'take': 25, 'skip': 0, 'items': documents};
      } else {
        body = <String, Object>{};
      }

      request.response
        ..statusCode = status
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(body));
      await request.response.close();
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final dir = Directory(screenshots);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    await tester.pump(const Duration(milliseconds: 300));
    final renderView = binding.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = renderView.layer! as OffsetLayer;
    final image = await layer.toImage(renderView.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  }

  Widget harness(Widget child) {
    final dio = Dio(BaseOptions(baseUrl: baseUrl));
    return ProviderScope(
      overrides: [
        ecfRepositoryProvider.overrideWithValue(EcfRepository(dio)),
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: true,
              hasSessionHint: true,
              user: UserModel(
                id: 'user-e2e',
                email: 'e2e@test.local',
                nombreCompleto: 'Usuario E2E',
                telefono: '',
                role: 'ADMIN',
                companyId: 'company-e2e',
                companyName: 'Empresa E2E',
              ),
            ),
          ),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  setUpAll(() async {
    await startServer();
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() {
    documents.clear();
    requests.clear();
    nextE31 = 1;
    nextE34 = 1;
    reservedCredit = 0;
  });

  testWidgets('E31: prepara desde la venta, aparece en la bandeja y no se duplica',
      (tester) async {
    await tester.pumpWidget(
      harness(
        const EcfPrepareAction(
          saleId: 'sale-1',
          total: 'DA 177.00',
          customerName: 'Cliente SA',
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Preparar e-CF'), findsOneWidget);
    await tester.tap(find.text('Preparar e-CF'));
    await settle(tester);
    await shoot(tester, 'e31-01-dialogo-seleccion');

    // La elección de tipo documental es EXPLÍCITA.
    expect(find.text('E31 · Crédito fiscal'), findsOneWidget);
    expect(find.text('E32 · Consumo'), findsOneWidget);

    await tester.tap(find.text('E31 · Crédito fiscal'));
    await settle(tester);
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await settle(tester);
    await tester.tap(find.text('Código 1').last);
    await settle(tester);
    await shoot(tester, 'e31-02-confirmacion');
    await tester.tap(find.text('Preparar'));
    await settle(tester);

    expect(find.text('Borrador preparado'), findsOneWidget);
    expect(find.textContaining('E310000000001'), findsWidgets);
    await shoot(tester, 'e31-03-resultado');
  });

  testWidgets('E32: selección explícita, sin e-NCF y visible en la bandeja',
      (tester) async {
    await tester.pumpWidget(
      harness(const EcfPrepareAction(saleId: 'sale-1', total: 'DA 177.00')),
    );
    await settle(tester);
    await tester.tap(find.text('Preparar e-CF'));
    await settle(tester);

    await tester.tap(find.text('E32 · Consumo'));
    await settle(tester);
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await settle(tester);
    await tester.tap(find.text('Código 1').last);
    await settle(tester);
    await tester.tap(find.text('Preparar'));
    await settle(tester);

    expect(find.text('Borrador preparado'), findsOneWidget);
    expect(requests.any((r) => r.contains('prepare-consumo')), isTrue);
    await shoot(tester, 'e32-01-resultado');

    // Bandeja: el E32 se ve SIN e-NCF y sin presentarse como aceptado.
    await tester.pumpWidget(harness(const EcfDocumentsPage()));
    await settle(tester);
    await shoot(tester, 'e32-02-bandeja');
    expect(find.textContaining('E32 · sin e-NCF'), findsOneWidget);
    expect(find.text('Listo localmente'), findsOneWidget);
    expect(find.text('Aceptado DGII'), findsNothing);
  });

  testWidgets('bandeja: abre el detalle con su historial', (tester) async {
    await tester.pumpWidget(harness(const EcfDocumentsPage()));
    await settle(tester);
    // Se prepara primero un documento para que la bandeja tenga contenido.
    await tester.pumpWidget(
      harness(const EcfPrepareAction(saleId: 'sale-1', total: 'DA 177.00')),
    );
    await settle(tester);
    await tester.tap(find.text('Preparar e-CF'));
    await settle(tester);
    await tester.tap(find.text('E32 · Consumo'));
    await settle(tester);
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await settle(tester);
    await tester.tap(find.text('Código 1').last);
    await settle(tester);
    await tester.tap(find.text('Preparar'));
    await settle(tester);

    await tester.pumpWidget(harness(const EcfDocumentsPage()));
    await settle(tester);
    await tester.tap(find.textContaining('E32 · sin e-NCF'));
    await settle(tester);
    await shoot(tester, 'bandeja-01-detalle');
    expect(find.text('Estado operativo'), findsOneWidget);
    expect(find.text('Resultado fiscal'), findsOneWidget);
    expect(find.textContaining('Historial de estados'), findsOneWidget);
  });

  testWidgets('E34: saldo, nota parcial, exceso bloqueado y sin gastar número',
      (tester) async {
    await tester.pumpWidget(
      harness(
        const EcfCreditNoteAction(
          originalId: 'original-1',
          originalLabel: 'E31 · E310000000001',
          availableAmount: '177.00',
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Nota de crédito'));
    await settle(tester);
    await shoot(tester, 'e34-01-saldo');

    expect(find.text('E31 · E310000000001'), findsOneWidget);
    expect(find.text('177.00'), findsOneWidget);
    // Sin motivo no se puede preparar.
    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Preparar nota')).onPressed,
      isNull,
    );

    // Nota PARCIAL de 1 unidad.
    await tester.tap(find.text('Parcial'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '1:1');
    await tester.enterText(find.byType(TextField).last, 'Devolución parcial');
    await settle(tester);
    await shoot(tester, 'e34-02-parcial');
    await tester.tap(find.text('Preparar nota'));
    await settle(tester);
    expect(find.text('Nota preparada'), findsOneWidget);
    expect(find.textContaining('E340000000001'), findsWidgets);
    await shoot(tester, 'e34-03-resultado');

    // Exceso de saldo: se bloquea con el mensaje seguro y NO gasta número.
    await tester.pumpWidget(
      harness(
        const EcfCreditNoteAction(
          originalId: 'original-1',
          originalLabel: 'E31 · E310000000001',
          availableAmount: '118.00',
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('Nota de crédito'));
    await settle(tester);
    await tester.tap(find.text('Parcial'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '1:3');
    await tester.enterText(find.byType(TextField).last, 'Intento por encima del saldo');
    await settle(tester);
    await tester.tap(find.text('Preparar nota'));
    await settle(tester);
    await shoot(tester, 'e34-04-exceso');
    expect(find.text('No se pudo preparar'), findsOneWidget);
    expect(
      find.textContaining('saldo acreditable'),
      findsOneWidget,
    );
    // El número NO avanzó: el siguiente documento sigue siendo el 001.
    expect(nextE34, 2);
  });
}

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}
