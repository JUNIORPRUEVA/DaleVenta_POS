import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';

/// Cliente e-CF: solo lectura. Estas pruebas fijan el contrato con el backend
/// (rutas, parámetros y parseo) sin tocar ningún proveedor ni emitir nada.
void main() {
  EcfRepository repositoryWith(
    Future<ResponseBody> Function(RequestOptions options) handler,
  ) {
    final dio = Dio()..httpClientAdapter = _FakeHttpClientAdapter(handler);
    return EcfRepository(dio);
  }

  ResponseBody json(Object body, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  test('capabilities reports e-CF disabled with no emission path', () async {
    final repo = repositoryWith(
      (_) async => json({
        'enabled': false,
        'environment': 'SANDBOX',
        'certificationStatus': 'NOT_STARTED',
        'productionEnabled': false,
        'allowedTypes': <String>[],
        'emissionPathAvailable': false,
        'documentTypes': [
          {
            'documentType': 'E31',
            'contractStatus': 'CONFIRMED_OFFICIAL',
            'contractAllowsEmission': true,
            'allowedForCompany': false,
            'allocatable': true,
          },
          {
            'documentType': 'E32',
            'contractStatus': 'PARTIAL_OFFICIAL',
            'contractAllowsEmission': false,
            'allowedForCompany': false,
            'allocatable': false,
          },
        ],
      }),
    );

    final capabilities = await repo.capabilities();

    expect(capabilities.enabled, isFalse);
    expect(capabilities.emissionPathAvailable, isFalse);
    expect(capabilities.documentTypes, hasLength(2));
    expect(
      capabilities.documentTypes
          .firstWhere((type) => type.documentType == 'E32')
          .allocatable,
      isFalse,
    );
  });

  test('listDocuments sends the functional group exactly as the API expects',
      () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({
        'total': 1,
        'take': 50,
        'skip': 0,
        'items': [
          {
            'id': 'doc-1',
            'documentType': 'E31',
            'status': 'HUMAN_REVIEW_REQUIRED',
            'statusGroup': 'REQUIRES_REVIEW',
            'encf': 'E310000000123',
            'createdAt': '2026-10-14T12:00:00.000Z',
            'safeErrorCode': 'ECF_OBSERVED_ACCEPTED',
            'safeErrorMessage': 'Resultado observado; requiere revisión.',
          },
        ],
      });
    });

    final items = await repo.listDocuments(
      filter: const EcfDocumentFilter(
        group: EcfStatusGroup.requiresReview,
        documentType: 'E31',
        search: 'E3100000',
      ),
    );

    expect(captured?.method, 'GET');
    expect(captured?.path, '/ecf/documents');
    expect(captured?.queryParameters['group'], 'REQUIRES_REVIEW');
    expect(captured?.queryParameters['documentType'], 'E31');
    expect(captured?.queryParameters['search'], 'E3100000');
    expect(items, hasLength(1));
    expect(items.first.encf, 'E310000000123');
    expect(items.first.statusGroup, EcfStatusGroup.requiresReview);
  });

  test('omits the group parameter when no filter is selected', () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({'total': 0, 'items': <Object>[]});
    });

    await repo.listDocuments();

    expect(captured?.queryParameters.containsKey('group'), isFalse);
  });

  test('documentDetail parses history, reservation and original', () async {
    final repo = repositoryWith(
      (_) async => json({
        'id': 'note-1',
        'documentType': 'E34',
        'status': 'HUMAN_REVIEW_REQUIRED',
        'statusGroup': 'REQUIRES_REVIEW',
        'encf': 'E340000000007',
        'originalDocumentId': 'original-1',
        'evidenceReceipts': 1,
        'creditReservation': {
          'state': 'RESERVED',
          'amount': '40',
          'createdAt': '2026-10-14T12:00:00.000Z',
        },
        'originalDocument': {
          'id': 'original-1',
          'documentType': 'E31',
          'status': 'DGII_ACCEPTED',
          'externalDocumentNumber': 'E310000000001',
        },
        'statusLogs': [
          {
            'id': 'log-1',
            'statusBefore': 'SEND_IN_PROGRESS',
            'statusAfter': 'HUMAN_REVIEW_REQUIRED',
            'reasonCode': 'ECF_OBSERVED_ACCEPTED',
            'createdAt': '2026-10-14T12:00:01.000Z',
          },
        ],
        'attempts': [
          {
            'id': 'attempt-1',
            'operation': 'SEND_TO_PROVIDER',
            'createdAt': '2026-10-14T12:00:00.500Z',
          },
        ],
      }),
    );

    final detail = await repo.documentDetail('note-1');

    expect(detail.summary.encf, 'E340000000007');
    expect(detail.creditReservation?.state, 'RESERVED');
    expect(detail.creditReservation?.amount, '40');
    expect(detail.originalDocument?.encf, 'E310000000001');
    expect(detail.statusLogs.single.reasonCode, 'ECF_OBSERVED_ACCEPTED');
    expect(detail.attempts.single.operation, 'SEND_TO_PROVIDER');
    expect(detail.evidenceReceipts, 1);
  });

  test('eligibleOriginals exposes the shared fiscal balance', () async {
    final repo = repositoryWith(
      (_) async => json({
        'items': [
          {
            'id': 'original-1',
            'documentType': 'E31',
            'encf': 'E310000000001',
            'availableAmount': '60.00',
          },
        ],
      }),
    );

    final items = await repo.eligibleOriginals();

    expect(items.single.availableAmount, '60.00');
  });

  test('sequences expose consumed and remaining numbers', () async {
    final repo = repositoryWith(
      (_) async => json({
        'items': [
          {
            'id': 'seq-1',
            'documentType': 'E31',
            'prefix': 'E31',
            'startNumber': 1,
            'nextNumber': 3,
            'endNumber': 10,
            'active': true,
            'consumed': 2,
            'remaining': 8,
          },
        ],
      }),
    );

    final items = await repo.sequences();

    expect(items.single.consumed, 2);
    expect(items.single.remaining, 8);
    expect(items.single.active, isTrue);
  });

  test('updateEnabled only flips the company switch', () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({'enabled': true});
    });

    await repo.updateEnabled(enabled: true);

    expect(captured?.method, 'PATCH');
    expect(captured?.path, '/ecf/config');
    expect(captured?.data, {'enabled': true});
  });

  test('prepareFromSale posts an E31 draft and returns the assigned e-NCF', () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({
        'ok': true,
        'value': {
          'documentId': 'doc-1',
          'documentType': 'E31',
          'status': 'LOCAL_VALIDATED',
          'encf': 'E310000000001',
          'saleId': 'sale-1',
        },
      });
    });

    final outcome = await repo.prepareFromSale(
      saleId: 'sale-1',
      paymentType: 1,
      incomeType: 1,
      sequenceDueDate: '2026-12-31',
    );

    expect(captured?.method, 'POST');
    expect(captured?.path, '/ecf/documents/prepare');
    expect(captured?.data, {
      'saleId': 'sale-1',
      'documentType': 'E31',
      'paymentType': 1,
      'incomeType': 1,
      'sequenceDueDate': '2026-12-31',
    });
    expect(outcome.ok, isTrue);
    expect(outcome.encf, 'E310000000001');
    expect(outcome.status, 'LOCAL_VALIDATED');
  });

  test('a non-eligible sale returns a structured failure, not a thrown error',
      () async {
    final repo = repositoryWith(
      (_) async => json({
        'ok': false,
        'code': 'ECF_BUYER_DATA_REQUIRED',
        'safeMessage': 'E31 exige identificar al receptor.',
      }),
    );

    final outcome = await repo.prepareFromSale(saleId: 'sale-1', paymentType: 1);

    expect(outcome.ok, isFalse);
    expect(outcome.code, 'ECF_BUYER_DATA_REQUIRED');
    expect(outcome.message, contains('receptor'));
  });

  test('omits optional fiscal fields when they are not supplied', () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({
        'ok': true,
        'value': {
          'documentId': 'doc-1',
          'status': 'LOCAL_VALIDATED',
          'encf': 'E310000000002',
        },
      });
    });

    await repo.prepareFromSale(saleId: 'sale-1', paymentType: 2);

    expect(captured?.data, {
      'saleId': 'sale-1',
      'documentType': 'E31',
      'paymentType': 2,
    });
  });

  test('every functional group maps to a valid API value', () {
    expect(EcfStatusGroup.pending.apiValue, 'PENDING');
    expect(EcfStatusGroup.requiresReview.apiValue, 'REQUIRES_REVIEW');
    expect(EcfStatusGroup.accepted.apiValue, 'ACCEPTED');
    expect(EcfStatusGroup.rejected.apiValue, 'REJECTED');
    expect(EcfStatusGroup.cancelled.apiValue, 'CANCELLED');
    expect(EcfStatusGroup.unknown.apiValue, isEmpty);
  });

  test('an unknown status is never silently treated as accepted', () {
    expect(
      EcfStatusGroup.fromApi('SOMETHING_NEW'),
      EcfStatusGroup.unknown,
    );
    expect(
      EcfStatusGroup.fromApi('PROVIDER_ACCEPTED'),
      EcfStatusGroup.unknown,
    );
  });

  test('prepareCreditNote posts an E34 draft against the original', () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({
        'ok': true,
        'value': {
          'documentId': 'credit-1',
          'documentType': 'E34',
          'status': 'LOCAL_VALIDATED',
          'encf': 'E340000000001',
          'originalDocumentId': 'original-1',
          'originalEncf': 'E310000000001',
        },
      });
    });

    final outcome = await repo.prepareCreditNote(
      originalDocumentId: 'original-1',
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      refundKind: 'PARTIAL',
      modificationCode: 3,
      modificationReason: 'Devolución parcial de mercancía',
      paymentType: 1,
      creditNoteIndicator: 0,
      lines: [
        {'lineNumber': 2, 'quantity': '1.00'},
      ],
    );

    expect(captured?.method, 'POST');
    expect(captured?.path, '/ecf/documents/prepare-credit-note');
    expect(captured?.data, {
      'originalDocumentId': 'original-1',
      'clientRequestId': '11111111-1111-4111-8111-111111111111',
      'refundKind': 'PARTIAL',
      'modificationCode': 3,
      'modificationReason': 'Devolución parcial de mercancía',
      'paymentType': 1,
      'creditNoteIndicator': 0,
      'lines': [
        {'lineNumber': 2, 'quantity': '1.00'},
      ],
    });
    expect(outcome.ok, isTrue);
    expect(outcome.encf, 'E340000000001');
    expect(outcome.status, 'LOCAL_VALIDATED');
  });

  test('a TOTAL refund sends no lines: the server copies the original', () async {
    final bodies = <Map<String, dynamic>>[];
    final repo = repositoryWith((options) async {
      bodies.add(Map<String, dynamic>.from(options.data as Map));
      return json({
        'ok': true,
        'value': {'documentId': 'c', 'status': 'LOCAL_VALIDATED', 'encf': 'E34'},
      });
    });

    await repo.prepareCreditNote(
      originalDocumentId: 'original-1',
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      refundKind: 'TOTAL',
      modificationCode: 1,
      modificationReason: 'Anulación total',
      paymentType: 1,
      creditNoteIndicator: 1,
    );
    await repo.prepareCreditNote(
      originalDocumentId: 'original-1',
      clientRequestId: '22222222-2222-4222-8222-222222222222',
      refundKind: 'PARTIAL',
      modificationCode: 3,
      modificationReason: 'Devolución parcial',
      paymentType: 2,
      creditNoteIndicator: 0,
      lines: const [
        {'lineNumber': 1, 'quantity': '2'},
      ],
    );

    expect(bodies.first.containsKey('lines'), isFalse);
    expect(bodies.last['lines'], [
      {'lineNumber': 1, 'quantity': '2'},
    ]);
  });

  test('a credit note over the available balance fails with a safe code',
      () async {
    final repo = repositoryWith(
      (_) async => json({
        'ok': false,
        'code': 'E34_INSUFFICIENT_FISCAL_BALANCE',
        'safeMessage': 'La cantidad supera el saldo acreditable del original.',
      }),
    );

    final outcome = await repo.prepareCreditNote(
      originalDocumentId: 'original-1',
      clientRequestId: '11111111-1111-4111-8111-111111111111',
      refundKind: 'PARTIAL',
      modificationCode: 3,
      modificationReason: 'Devolución parcial',
      paymentType: 1,
      creditNoteIndicator: 0,
      lines: const [
        {'lineNumber': 1, 'quantity': '99'},
      ],
    );

    expect(outcome.ok, isFalse);
    expect(outcome.code, 'E34_INSUFFICIENT_FISCAL_BALANCE');
    expect(outcome.message, contains('saldo acreditable'));
  });

  test('the tray projection carries amount, currency and the original e-NCF',
      () async {
    final repo = repositoryWith(
      (_) async => json({
        'total': 1,
        'take': 50,
        'skip': 0,
        'items': [
          {
            'id': 'credit-1',
            'documentType': 'E34',
            'status': 'LOCAL_VALIDATED',
            'statusGroup': 'PENDING',
            'encf': 'E340000000001',
            'createdAt': '2026-10-15T12:00:00.000Z',
            'total': '59.00',
            'currency': 'DOP',
            'originalEncf': 'E310000000001',
          },
        ],
      }),
    );

    final items = await repo.listDocuments();

    expect(items, hasLength(1));
    expect(items.first.documentType, 'E34');
    expect(items.first.total, '59.00');
    expect(items.first.currency, 'DOP');
    expect(items.first.originalEncf, 'E310000000001');
  });

  test('a document without fiscal amounts keeps them null instead of guessing',
      () async {
    final repo = repositoryWith(
      (_) async => json({
        'total': 1,
        'items': [
          {
            'id': 'draft-1',
            'documentType': 'E31',
            'status': 'DRAFT',
            'statusGroup': 'PENDING',
            'encf': null,
            'createdAt': '2026-10-15T12:00:00.000Z',
          },
        ],
      }),
    );

    final items = await repo.listDocuments();

    expect(items.first.total, isNull);
    expect(items.first.currency, isNull);
    expect(items.first.originalEncf, isNull);
  });

  test('listDocumentsPage keeps the server total and sends take/skip',
      () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({
        'total': 40,
        'take': 25,
        'skip': 25,
        'items': [
          {
            'id': 'doc-3',
            'documentType': 'E34',
            'status': 'LOCAL_VALIDATED',
            'statusGroup': 'PENDING',
            'encf': 'E340000000003',
            'createdAt': '2026-10-15T12:00:00.000Z',
            'total': '59.00',
            'currency': 'DOP',
            'originalEncf': 'E310000000001',
            'receiverName': 'Ferretería del Sur',
            'receiverTaxId': '101000001',
          },
        ],
      });
    });

    final page = await repo.listDocumentsPage(take: 25, skip: 25);

    expect(captured?.queryParameters['take'], 25);
    expect(captured?.queryParameters['skip'], 25);
    expect(page.total, 40);
    expect(page.items, hasLength(1));
    expect(page.hasMore, isTrue);
    expect(page.nextSkip, 26);
    expect(page.items.first.receiverName, 'Ferretería del Sur');
    expect(page.items.first.receiverTaxId, '101000001');
  });

  test('a page without a server total never claims more rows than it has',
      () async {
    final repo = repositoryWith(
      (_) async => json({
        'items': [
          {
            'id': 'a',
            'documentType': 'E31',
            'status': 'LOCAL_DRAFT',
            'statusGroup': 'PENDING',
            'createdAt': '2026-10-15T12:00:00.000Z',
          },
        ],
      }),
    );

    final page = await repo.listDocumentsPage(take: 25, skip: 25);

    expect(page.total, 26);
    expect(page.hasMore, isFalse);
  });

  test('a receiver that was not frozen stays null instead of being guessed',
      () async {
    final repo = repositoryWith(
      (_) async => json({
        'total': 1,
        'items': [
          {
            'id': 'a',
            'documentType': 'E32',
            'status': 'LOCAL_VALIDATED',
            'statusGroup': 'PENDING',
            'createdAt': '2026-10-15T12:00:00.000Z',
            'receiverName': null,
            'receiverTaxId': null,
          },
        ],
      }),
    );

    final page = await repo.listDocumentsPage();

    expect(page.items.first.receiverName, isNull);
    expect(page.items.first.receiverTaxId, isNull);
  });

  test('prepareConsumoFromSale posts an E32 draft without a number', () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({
        'ok': true,
        'value': {
          'documentId': 'consumo-1',
          'documentType': 'E32',
          'status': 'LOCAL_VALIDATED',
          'encf': null,
          'numberingState': 'PENDING_SANDBOX_SLOT',
        },
      });
    });

    final outcome = await repo.prepareConsumoFromSale(
      saleId: 'sale-1',
      paymentType: 1,
      incomeType: 1,
    );

    expect(captured?.method, 'POST');
    expect(captured?.path, '/ecf/documents/prepare-consumo');
    expect(captured?.data, {
      'saleId': 'sale-1',
      'documentType': 'E32',
      'paymentType': 1,
      'incomeType': 1,
    });
    expect(outcome.ok, isTrue);
    // E32 no toma numeración del rango de la empresa en este flujo.
    expect(outcome.encf, isEmpty);
    expect(outcome.status, 'LOCAL_VALIDATED');
  });

  test('a consumo refusal comes back as a safe code, not a thrown error',
      () async {
    final repo = repositoryWith(
      (_) async => json({
        'ok': false,
        'code': 'ECF_SALE_ALREADY_PREPARED_AS_OTHER_TYPE',
        'safeMessage': 'La venta ya tiene un comprobante E31 preparado.',
      }),
    );

    final outcome = await repo.prepareConsumoFromSale(
      saleId: 'sale-1',
      paymentType: 2,
    );

    expect(outcome.ok, isFalse);
    expect(outcome.code, 'ECF_SALE_ALREADY_PREPARED_AS_OTHER_TYPE');
    expect(outcome.message, contains('E31'));
  });

  test('consumo preparation omits incomeType when it is not supplied',
      () async {
    RequestOptions? captured;
    final repo = repositoryWith((options) async {
      captured = options;
      return json({
        'ok': true,
        'value': {
          'documentId': 'c',
          'documentType': 'E32',
          'status': 'LOCAL_VALIDATED',
          'encf': null,
        },
      });
    });

    await repo.prepareConsumoFromSale(saleId: 'sale-1', paymentType: 1);

    expect(captured?.data, {
      'saleId': 'sale-1',
      'documentType': 'E32',
      'paymentType': 1,
    });
  });
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

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
