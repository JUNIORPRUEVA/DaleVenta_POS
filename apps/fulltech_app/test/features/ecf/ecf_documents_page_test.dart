import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_documents_page.dart';

/// Bandeja electrónica: estas pruebas fijan QUÉ ve el usuario para cada estado
/// y qué consulta se envía al filtrar. No emiten ni modifican nada.
void main() {
  Map<String, dynamic> capabilitiesJson({bool enabled = true}) => {
    'enabled': enabled,
    'environment': 'SANDBOX',
    'certificationStatus': 'NOT_STARTED',
    'productionEnabled': false,
    'allowedTypes': <String>[],
    'emissionPathAvailable': false,
    'documentTypes': <Object>[],
  };

  Map<String, dynamic> countersJson({int total = 0}) => {
    'total': total,
    'byStatus': <String, int>{},
    'byGroup': {
      'PENDING': 0,
      'REQUIRES_REVIEW': 0,
      'ACCEPTED': 0,
      'REJECTED': 0,
      'CANCELLED': 0,
    },
  };

  Map<String, dynamic> document({
    required String id,
    String documentType = 'E31',
    String status = 'LOCAL_VALIDATED',
    String statusGroup = 'PENDING',
    String? encf,
    String? total,
    String? currency,
    String? receiverName,
    String? receiverTaxId,
    String? originalEncf,
    String? safeErrorMessage,
  }) => {
    'id': id,
    'documentType': documentType,
    'status': status,
    'statusGroup': statusGroup,
    'encf': encf,
    'createdAt': '2026-10-15T14:30:00.000Z',
    'total': total,
    'currency': currency,
    'receiverName': receiverName,
    'receiverTaxId': receiverTaxId,
    'originalEncf': originalEncf,
    'safeErrorMessage': safeErrorMessage,
  };

  /// Lista de peticiones a la bandeja, para comprobar los filtros enviados.
  late List<Map<String, dynamic>> listQueries;

  setUp(() => listQueries = <Map<String, dynamic>>[]);

  Widget harness(Future<ResponseBody> Function(RequestOptions) handler) {
    final dio = Dio()..httpClientAdapter = _FakeAdapter(handler);
    return ProviderScope(
      overrides: [ecfRepositoryProvider.overrideWithValue(EcfRepository(dio))],
      child: const MaterialApp(home: EcfDocumentsPage()),
    );
  }

  /// Responde configuración, contadores y bandeja; la bandeja la decide el test.
  Future<ResponseBody> Function(RequestOptions) tray(
    Object Function(Map<String, dynamic> query) onList, {
    Object? capabilities,
  }) {
    return (options) async {
      final path = options.path;
      if (path.endsWith('/capabilities')) {
        return _json(capabilities ?? capabilitiesJson());
      }
      if (path.endsWith('/documents/summary')) {
        return _json(countersJson(total: 4));
      }
      final query = (options.queryParameters).map(
        (key, value) => MapEntry(key, value),
      );
      listQueries.add(query);
      if (path.endsWith('/documents')) {
        return _json(onList(query));
      }
      return _json(<String, Object>{});
    };
  }

  Future<void> pumpTray(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  testWidgets('shows each document real status instead of one generic badge',
      (tester) async {
    await pumpTray(
      tester,
      harness(
        tray(
          (_) => {
            'total': 3,
            'items': [
              document(id: 'a', status: 'LOCAL_VALIDATED', encf: 'E310000000001'),
              document(id: 'b', status: 'SEND_IN_PROGRESS', encf: 'E310000000002'),
              document(id: 'c', status: 'DGII_ACCEPTED', encf: 'E310000000003'),
            ],
          },
        ),
      ),
    );

    expect(find.text('Listo localmente'), findsOneWidget);
    expect(find.text('Envío en curso'), findsOneWidget);
    expect(find.text('Aceptado DGII'), findsOneWidget);
  });

  testWidgets('a provider acceptance is never shown as a DGII acceptance',
      (tester) async {
    await pumpTray(
      tester,
      harness(
        tray(
          (_) => {
            'total': 1,
            'items': [
              document(
                id: 'a',
                status: 'PROVIDER_ACCEPTED',
                encf: 'E310000000009',
              ),
            ],
          },
        ),
      ),
    );

    expect(find.text('Aceptado por el proveedor'), findsOneWidget);
    expect(find.text('Aceptado DGII'), findsNothing);
  });

  testWidgets('shows amount, frozen receiver and the original reference',
      (tester) async {
    await pumpTray(
      tester,
      harness(
        tray(
          (_) => {
            'total': 1,
            'items': [
              document(
                id: 'a',
                documentType: 'E34',
                status: 'LOCAL_VALIDATED',
                encf: 'E340000000001',
                total: '59.00',
                currency: 'DOP',
                receiverName: 'Ferretería del Sur',
                receiverTaxId: '101000001',
                originalEncf: 'E310000000001',
              ),
            ],
          },
        ),
      ),
    );

    expect(find.textContaining('59.00 DOP'), findsOneWidget);
    expect(
      find.textContaining('Ferretería del Sur · 101000001'),
      findsOneWidget,
    );
    expect(find.textContaining('sobre E310000000001'), findsOneWidget);
  });

  testWidgets('shows the safe error message of a document under review',
      (tester) async {
    await pumpTray(
      tester,
      harness(
        tray(
          (_) => {
            'total': 1,
            'items': [
              document(
                id: 'a',
                status: 'HUMAN_REVIEW_REQUIRED',
                statusGroup: 'REQUIRES_REVIEW',
                safeErrorMessage: 'Resultado observado; requiere revisión.',
              ),
            ],
          },
        ),
      ),
    );

    expect(find.text('Requiere revisión'), findsWidgets);
    expect(
      find.text('Resultado observado; requiere revisión.'),
      findsOneWidget,
    );
  });

  testWidgets('an empty tray says so instead of inventing rows', (tester) async {
    await pumpTray(
      tester,
      harness(tray((_) => {'total': 0, 'items': <Object>[]})),
    );

    expect(find.text('Todavía no hay comprobantes electrónicos.'), findsOneWidget);
  });

  testWidgets('a filter with no matches offers to clear the filters',
      (tester) async {
    await pumpTray(
      tester,
      harness(tray((_) => {'total': 0, 'items': <Object>[]})),
    );

    await tester.tap(find.text('E34'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ningún comprobante coincide con los filtros aplicados.'),
      findsOneWidget,
    );
    expect(find.text('Quitar filtros'), findsOneWidget);
  });

  testWidgets('a failure to load the tray shows a retry, not an empty tray',
      (tester) async {
    await pumpTray(
      tester,
      harness((options) async {
        final path = options.path;
        if (path.endsWith('/capabilities')) return _json(capabilitiesJson());
        if (path.endsWith('/documents/summary')) {
          return _json(countersJson());
        }
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }),
    );

    expect(find.text('No se pudieron cargar los comprobantes.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Todavía no hay comprobantes electrónicos.'), findsNothing);
  });

  testWidgets('filtering by document type asks the backend for that type',
      (tester) async {
    await pumpTray(
      tester,
      harness(
        tray((_) => {'total': 0, 'items': <Object>[]}),
      ),
    );

    await tester.tap(find.text('E34'));
    await tester.pumpAndSettle();

    expect(listQueries.last['documentType'], 'E34');
    expect(listQueries.last.containsKey('group'), isFalse);
  });

  testWidgets('the search is applied after the debounce, not on every key',
      (tester) async {
    await pumpTray(
      tester,
      harness(tray((_) => {'total': 0, 'items': <Object>[]})),
    );
    final before = listQueries.length;

    await tester.enterText(find.byType(TextField), 'E310000000007');
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      listQueries.length,
      before,
      reason: 'no debe consultar en cada pulsación',
    );

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(listQueries.last['search'], 'E310000000007');
  });

  testWidgets('loads more rows on demand and stops at the server total',
      (tester) async {
    await pumpTray(
      tester,
      harness(
        tray((query) {
          final skip = query['skip'] as int? ?? 0;
          if (skip == 0) {
            return {
              'total': 3,
              'items': [
                document(id: 'a', encf: 'E310000000001'),
                document(id: 'b', encf: 'E310000000002'),
              ],
            };
          }
          return {
            'total': 3,
            'items': [document(id: 'c', encf: 'E310000000003')],
          };
        }),
      ),
    );

    expect(find.text('Mostrando 2 de 3'), findsOneWidget);
    expect(find.text('Cargar más (1)'), findsOneWidget);

    await tester.tap(find.text('Cargar más (1)'));
    await tester.pumpAndSettle();

    expect(listQueries.last['skip'], 2);
    expect(find.textContaining('E310000000003'), findsOneWidget);
    expect(find.text('3 comprobantes'), findsOneWidget);
    expect(find.textContaining('Cargar más'), findsNothing);
  });

  testWidgets('the environment banner states that emission is not a UI action',
      (tester) async {
    await pumpTray(
      tester,
      harness(tray((_) => {'total': 0, 'items': <Object>[]})),
    );

    expect(
      find.textContaining('La emisión no se realiza desde la aplicación'),
      findsOneWidget,
    );
  });

  group('formatters', () {
    test('an amount without currency is shown without inventing one', () {
      const noAmount = EcfDocumentSummary(
        id: 'a',
        documentType: 'E31',
        status: 'LOCAL_DRAFT',
        statusGroup: EcfStatusGroup.pending,
        encf: null,
        createdAt: null,
      );
      expect(formatEcfAmount(noAmount), isNull);

      const totalOnly = EcfDocumentSummary(
        id: 'b',
        documentType: 'E31',
        status: 'LOCAL_DRAFT',
        statusGroup: EcfStatusGroup.pending,
        encf: null,
        createdAt: null,
        total: '100.00',
      );
      expect(formatEcfAmount(totalOnly), '100.00');

      const withCurrency = EcfDocumentSummary(
        id: 'c',
        documentType: 'E31',
        status: 'LOCAL_DRAFT',
        statusGroup: EcfStatusGroup.pending,
        encf: null,
        createdAt: null,
        total: '100.00',
        currency: 'DOP',
      );
      expect(formatEcfAmount(withCurrency), '100.00 DOP');
    });

    test('a receiver is only shown when it was actually frozen', () {
      const none = EcfDocumentSummary(
        id: 'a',
        documentType: 'E32',
        status: 'LOCAL_DRAFT',
        statusGroup: EcfStatusGroup.pending,
        encf: null,
        createdAt: null,
      );
      expect(formatEcfReceiver(none), isNull);

      const nameOnly = EcfDocumentSummary(
        id: 'b',
        documentType: 'E31',
        status: 'LOCAL_DRAFT',
        statusGroup: EcfStatusGroup.pending,
        encf: null,
        createdAt: null,
        receiverName: 'Ferretería del Sur',
      );
      expect(formatEcfReceiver(nameOnly), 'Ferretería del Sur');

      const both = EcfDocumentSummary(
        id: 'c',
        documentType: 'E31',
        status: 'LOCAL_DRAFT',
        statusGroup: EcfStatusGroup.pending,
        encf: null,
        createdAt: null,
        receiverName: 'Ferretería del Sur',
        receiverTaxId: '101000001',
      );
      expect(formatEcfReceiver(both), 'Ferretería del Sur · 101000001');
    });

    test('dates are rendered in the local format used across the app', () {
      expect(
        formatEcfDateTime(DateTime(2026, 10, 15, 14, 30)),
        '15/10/2026 14:30',
      );
      expect(
        formatEcfDateTime(DateTime(2026, 1, 5, 9, 7)),
        '05/01/2026 09:07',
      );
    });
  });

  test('the tray page size is the one the backend was asked for', () {
    expect(kEcfTrayPageSize, 25);
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
