import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_application_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Expediente del cliente: borrador, envío y versiones.
///
/// Se fija el contrato con el backend (rutas, cuerpos y parseo) y el
/// comportamiento ante errores. Lo que se persigue aquí es que la app **no**
/// pueda creer que guardó cuando el servidor rechazó, ni enviar sin la versión
/// de consentimiento vigente.

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

ResponseBody _json(Object body, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

EcfApplicationRepository _repositoryWith(
  Future<ResponseBody> Function(RequestOptions options) handler,
) {
  final dio = Dio()..httpClientAdapter = _FakeHttpClientAdapter(handler);
  return EcfApplicationRepository(dio);
}

const _completePayload = <String, dynamic>{
  'company': {
    'rnc': '131000001',
    'legalName': 'Empresa Sintética SRL',
    'address': 'Calle Sintética 1',
  },
  'representative': {
    'fullName': 'Ana Pérez',
    'identification': '001-0000000-1',
    'email': 'ana@example.test',
  },
};

void main() {
  group('borrador', () {
    test('recupera los datos guardados y su estado de guardado', () async {
      final repo = _repositoryWith((options) async {
        expect(options.method, 'GET');
        expect(options.path, '/ecf/dgii/application/draft');
        return _json({
          'state': 'NOT_STARTED',
          'draft': _completePayload,
          'draftUpdatedAt': '2026-10-19T10:00:00.000Z',
          'missingFields': <String>[],
          'currentSnapshotVersion': 0,
          'requiredConsentVersion': '2026-10-19.v1',
          'consentPurpose': 'Autorizo el uso de los datos…',
        });
      });

      final draft = await repo.draft();
      expect(draft.hasDraft, isTrue);
      expect(draft.isComplete, isTrue);
      expect(draft.consentAlreadyAccepted, isFalse);
      expect(draft.draftUpdatedAt, isNotNull);
      expect(draft.read('company.rnc'), '131000001');
      expect(draft.read('representative.email'), 'ana@example.test');
      // La versión y el texto vienen del servidor, no del código cliente.
      expect(draft.requiredConsentVersion, '2026-10-19.v1');
      expect(draft.consentPurpose, isNotEmpty);
    });

    test('sin borrador devuelve nulos y los campos que faltan', () async {
      final repo = _repositoryWith(
        (_) async => _json({
          'state': 'NOT_STARTED',
          'draft': null,
          'missingFields': ['company.rnc', 'representative.email'],
          'requiredConsentVersion': 'v1',
          'consentPurpose': 'texto',
        }),
      );
      final draft = await repo.draft();
      expect(draft.hasDraft, isFalse);
      expect(draft.isComplete, isFalse);
      expect(draft.missingFields, hasLength(2));
      expect(draft.read('company.rnc'), isNull);
    });

    test('guardar envía el payload completo por PUT', () async {
      late RequestOptions captured;
      final repo = _repositoryWith((options) async {
        captured = options;
        return _json({
          'draft': _completePayload,
          'missingFields': <String>[],
          'requiredConsentVersion': 'v1',
          'consentPurpose': 'texto',
        });
      });

      await repo.saveDraft(_completePayload);
      expect(captured.method, 'PUT');
      expect(captured.path, '/ecf/dgii/application/draft');
      final body = captured.data as Map<String, dynamic>;
      expect((body['payload'] as Map)['company'], _completePayload['company']);
    });

    test('un fallo del servidor al guardar se propaga', () async {
      final repo = _repositoryWith(
        (_) async => _json({'message': 'boom'}, 500),
      );
      await expectLater(
        repo.saveDraft(_completePayload),
        throwsA(isA<DioException>()),
      );
    });
  });

  group('envío', () {
    test('envía la versión de consentimiento vigente y el payload', () async {
      late RequestOptions captured;
      final repo = _repositoryWith((options) async {
        captured = options;
        return _json({
          'idempotent': false,
          'version': 1,
          'state': 'APPLICATION_PENDING',
        }, 201);
      });

      final result = await repo.submit(
        consentVersion: '2026-10-19.v1',
        payload: _completePayload,
      );

      expect(captured.method, 'POST');
      expect(captured.path, '/ecf/dgii/application/submit');
      final body = captured.data as Map<String, dynamic>;
      expect(body['consentVersion'], '2026-10-19.v1');
      expect(body['payload'], _completePayload);
      expect(result.version, 1);
      expect(result.idempotent, isFalse);
      expect(result.state, 'APPLICATION_PENDING');
    });

    test('un reenvío idempotente se informa como tal', () async {
      final repo = _repositoryWith(
        (_) async => _json({
          'idempotent': true,
          'version': 3,
          'state': 'APPLICATION_PENDING',
        }, 201),
      );
      final result = await repo.submit(
        consentVersion: 'v',
        payload: _completePayload,
      );
      expect(result.idempotent, isTrue);
      expect(result.version, 3);
    });

    test('el rechazo por consentimiento llega como error, no como éxito', () async {
      final repo = _repositoryWith(
        (_) async => _json({
          'message': 'ECF_DGII_CONSENT_REQUIRED',
          'statusCode': 400,
        }, 400),
      );
      await expectLater(
        repo.submit(consentVersion: '', payload: _completePayload),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status',
            400,
          ),
        ),
      );
    });

    test('una transición no permitida no se confunde con un envío correcto', () async {
      final repo = _repositoryWith(
        (_) async => _json({
          'message': 'ECF_DGII_TRANSITION_NOT_ALLOWED',
          'statusCode': 409,
        }, 409),
      );
      await expectLater(
        repo.submit(consentVersion: 'v', payload: _completePayload),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status',
            409,
          ),
        ),
      );
    });
  });

  group('versiones enviadas', () {
    test('parsea las versiones con sus hashes y consentimiento', () async {
      final repo = _repositoryWith((options) async {
        expect(options.path, '/ecf/dgii/application/snapshots');
        return _json([
          {
            'version': 2,
            'payloadHash': 'b' * 64,
            'documentsHash': 'c' * 64,
            'consentVersion': '2026-10-19.v1',
            'submittedAt': '2026-10-19T11:00:00.000Z',
          },
          {
            'version': 1,
            'payloadHash': 'a' * 64,
            'documentsHash': 'd' * 64,
            'consentVersion': '2026-10-19.v1',
            'submittedAt': '2026-10-19T10:00:00.000Z',
          },
        ]);
      });

      final versions = await repo.snapshots();
      expect(versions, hasLength(2));
      expect(versions.first.version, 2);
      expect(versions.first.payloadHash, 'b' * 64);
      expect(versions.first.consentVersion, '2026-10-19.v1');
      expect(versions.last.version, 1);
    });

    test('una respuesta inesperada no inventa versiones', () async {
      final repo = _repositoryWith((_) async => _json({'items': <Object>[]}));
      expect(await repo.snapshots(), isEmpty);
    });
  });
}
