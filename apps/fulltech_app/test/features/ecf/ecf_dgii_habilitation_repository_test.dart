import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato Flutter de la habilitación DGII por empresa.
///
/// Fija las rutas, los cuerpos enviados y —lo importante— que la aplicación
/// **nunca** envía un `companyId`: el ámbito lo impone el backend a partir de la
/// sesión autenticada, así que una empresa no puede alcanzar los datos de otra.
void main() {
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

  test('dgiiHabilitation lee el estado completo de la empresa', () async {
    final repository = repositoryWith({
      'companyId': 'company-a',
      'state': 'IN_CERTIFICATION',
      'reviewState': 'revision-1',
      'observations': 'Pendiente el set de pruebas',
      'externalId': 'EXP-1',
      'officialAuthorization': false,
      'authorizationSource': 'NONE',
      'moduleEnabled': true,
      'certificationStatus': 'IN_PROGRESS',
      'providerIntegrationConfigured': true,
      'progress': {
        'total': 14,
        'resolvedCount': 5,
        'mandatoryTotal': 13,
        'mandatoryResolved': 5,
        'percent': 36,
        'pendingMandatory': ['SET_TESTS', 'SERVICE_URLS'],
        'requirements': [
          {
            'key': 'FISCAL_DATA',
            'label': 'Datos fiscales de la empresa',
            'mandatory': true,
            'automatable': true,
            'status': 'COMPLETED',
            'resolved': true,
          },
          {
            'key': 'SET_TESTS',
            'label': 'Pruebas del SET',
            'mandatory': true,
            'automatable': false,
            'status': 'PENDING',
            'resolved': false,
          },
        ],
      },
      'evidence': [
        {
          'id': 'e1',
          'source': 'OFFICIAL_DOCUMENT',
          'isOfficialDocument': true,
          'kind': 'resolucion',
          'fileName': 'resolucion.pdf',
        },
        {
          'id': 'e2',
          'source': 'MANUAL_DECLARATION',
          'isOfficialDocument': false,
          'kind': 'nota',
        },
      ],
      'emission': {
        'realEmissionAuthorized': false,
        'simulatedDispatchAuthorized': true,
        'productionEmissionImplemented': false,
      },
      'blockers': [
        {'code': 'ECF_DGII_REQUIREMENTS_PENDING', 'message': 'Faltan requisitos'},
      ],
      'officialAuthorizationBlockers': [
        {'code': 'ECF_DGII_STATE_NOT_APPROVED', 'message': 'No aprobado'},
      ],
    });

    final view = await repository.dgiiHabilitation();

    expect(captured?.method, 'GET');
    expect(captured?.path, '/ecf/dgii/habilitation');

    expect(view.companyId, 'company-a');
    expect(view.state, 'IN_CERTIFICATION');
    expect(view.stateLabel, 'En certificación');
    expect(view.observations, 'Pendiente el set de pruebas');
    expect(view.officialAuthorization, isFalse);
    expect(view.officialAuthorizationBlockers, hasLength(1));
    expect(view.progress.total, 14);
    expect(view.progress.percent, 36);
    expect(view.progress.ratio, closeTo(5 / 14, 0.001));
    expect(view.progress.pendingMandatory, ['SET_TESTS', 'SERVICE_URLS']);
    expect(view.evidence, hasLength(2));
    expect(view.evidence.first.isOfficialDocument, isTrue);
    expect(view.evidence.first.sourceLabel, 'Documento oficial');
    expect(view.evidence.last.isOfficialDocument, isFalse);
    expect(view.evidence.last.sourceLabel, 'Declaración manual');

    // La emisión real NUNCA se lee como autorizada.
    expect(view.emission.realEmissionAuthorized, isFalse);
    expect(view.emission.productionEmissionImplemented, isFalse);
  });

  test('tolera una carga útil incompleta sin romper la pantalla', () async {
    final repository = repositoryWith(<String, Object?>{});
    final view = await repository.dgiiHabilitation();

    expect(view.state, 'NOT_STARTED');
    expect(view.stateLabel, 'Sin iniciar');
    expect(view.officialAuthorization, isFalse);
    expect(view.evidence, isEmpty);
    expect(view.blockers, isEmpty);
    expect(view.progress.total, 0);
    expect(view.progress.ratio, 0);
    expect(view.emission.realEmissionAuthorized, isFalse);
  });

  test('los estados avanzables nunca incluyen APPROVED', () async {
    // Se recorren TODOS los estados conocidos: la interfaz jamás debe ofrecer
    // una aprobación oficial como opción de avance.
    const states = [
      'NOT_STARTED',
      'PREPARING_REQUIREMENTS',
      'APPLICATION_PENDING',
      'IN_PROGRESS',
      'TESTS_PENDING',
      'IN_CERTIFICATION',
      'APPROVED',
      'REJECTED',
      'REQUIRES_CORRECTION',
    ];
    for (final state in states) {
      final repository = repositoryWith({'state': state});
      final view = await repository.dgiiHabilitation();
      expect(
        view.allowedNextStates,
        isNot(contains('APPROVED')),
        reason: 'El estado $state no puede ofrecer aprobación oficial',
      );
    }
  });

  test('updateDgiiHabilitation no envía companyId ni aprueba', () async {
    final repository = repositoryWith({'ok': true});
    await repository.updateDgiiHabilitation(
      state: 'IN_PROGRESS',
      observations: 'Avance',
    );

    expect(captured?.method, 'PATCH');
    expect(captured?.path, '/ecf/dgii/habilitation');
    final body = captured!.data as Map<String, dynamic>;
    expect(body['state'], 'IN_PROGRESS');
    expect(body['observations'], 'Avance');
    // El ámbito de empresa lo impone el backend desde la sesión.
    expect(body.containsKey('companyId'), isFalse);
  });

  test('registrar evidencia declara la procedencia', () async {
    final repository = repositoryWith({
      'id': 'e1',
      'source': 'OFFICIAL_DOCUMENT',
      'isOfficialDocument': true,
      'kind': 'resolucion',
    });

    final evidence = await repository.registerDgiiEvidence(
      source: 'OFFICIAL_DOCUMENT',
      kind: 'resolucion',
      storageRef: 'uat://empresa/resolucion-2026',
      description: 'Resolución recibida',
    );

    expect(captured?.method, 'POST');
    expect(captured?.path, '/ecf/dgii/evidence');
    final body = captured!.data as Map<String, dynamic>;
    expect(body['source'], 'OFFICIAL_DOCUMENT');
    expect(body['storageRef'], 'uat://empresa/resolucion-2026');
    expect(body['description'], 'Resolución recibida');
    expect(body.containsKey('companyId'), isFalse);
    expect(evidence.isOfficialDocument, isTrue);
  });

  test('registrar autorización exige fuente, evidencia e identificador', () async {
    final repository = repositoryWith({'ok': true});
    await repository.recordDgiiAuthorization(
      source: 'DGII_OFFICIAL_RECORD',
      evidenceId: 'e1',
      externalId: 'DGII-2026-1',
    );

    expect(captured?.method, 'POST');
    expect(captured?.path, '/ecf/dgii/authorization');
    expect(captured?.data, {
      'source': 'DGII_OFFICIAL_RECORD',
      'evidenceId': 'e1',
      'externalId': 'DGII-2026-1',
    });
  });

  test('revocar autorización usa la ruta dedicada', () async {
    final repository = repositoryWith({'ok': true});
    await repository.revokeDgiiAuthorization();

    expect(captured?.method, 'POST');
    expect(captured?.path, '/ecf/dgii/authorization/revoke');
  });

  test('historial y evidencias leen sus rutas y toleran listas vacías', () async {
    final repository = repositoryWith(<Object>[]);
    expect(await repository.dgiiHistory(), isEmpty);
    expect(captured?.path, '/ecf/dgii/history');
    expect(await repository.dgiiEvidence(), isEmpty);
    expect(captured?.path, '/ecf/dgii/evidence');
  });

  test('un error HTTP del backend se propaga como excepción', () async {
    final repository = repositoryWith({'message': 'No autorizado'}, status: 403);
    await expectLater(
      repository.dgiiHabilitation(),
      throwsA(isA<DioException>()),
    );
  });

  test('revisar una evidencia usa su ruta y no envía un motivo vacío', () async {
    final repository = repositoryWith({
      'id': 'e1',
      'source': 'OFFICIAL_DOCUMENT',
      'isOfficialDocument': true,
      'kind': 'resolucion',
      'reviewStatus': 'REVIEWED',
      'level': 'OFFICIAL_DOCUMENT_REVIEWED',
      'supportsOfficialAuthorization': true,
    });

    final reviewed = await repository.reviewDgiiEvidence(
      evidenceId: 'e1',
      decision: 'REVIEWED',
      note: '   ',
    );

    expect(captured?.method, 'PATCH');
    expect(captured?.path, '/ecf/dgii/evidence/e1/review');
    // Un motivo en blanco no se envía: el backend lo interpretaría como ausente.
    expect(captured?.data, {'decision': 'REVIEWED'});
    expect(reviewed.reviewStatus, 'REVIEWED');
    expect(reviewed.level, 'OFFICIAL_DOCUMENT_REVIEWED');
    expect(reviewed.supportsOfficialAuthorization, isTrue);
  });

  test('el rechazo viaja con su motivo, que el backend exige', () async {
    final repository = repositoryWith({
      'id': 'e1',
      'source': 'MANUAL_DECLARATION',
      'isOfficialDocument': false,
      'kind': 'nota',
      'reviewStatus': 'REJECTED',
      'reviewNote': 'Documento ilegible',
    });

    await repository.reviewDgiiEvidence(
      evidenceId: 'e1',
      decision: 'REJECTED',
      note: 'Documento ilegible',
    );

    expect(captured?.data, {
      'decision': 'REJECTED',
      'note': 'Documento ilegible',
    });
  });

  test('el seguimiento de un requisito usa su ruta y omite lo no informado',
      () async {
    final repository = repositoryWith({
      'companyId': 'company-a',
      'state': 'NOT_STARTED',
      'progress': {
        'requirements': [
          {
            'key': 'SET_TESTS',
            'label': 'Pruebas del SET',
            'mandatory': true,
            'automatable': false,
            'status': 'PENDING',
            'resolved': false,
            'tracking': {
              'status': 'IN_PROGRESS',
              'note': 'Faltan pruebas',
              'dueDate': '2026-11-30',
            },
          },
        ],
      },
    });

    final view = await repository.updateDgiiRequirement(
      key: 'SET_TESTS',
      status: 'IN_PROGRESS',
      note: 'Faltan pruebas',
      dueDate: '2026-11-30',
    );

    expect(captured?.method, 'PATCH');
    expect(captured?.path, '/ecf/dgii/requirements/SET_TESTS');
    expect(captured?.data, {
      'status': 'IN_PROGRESS',
      'note': 'Faltan pruebas',
      'dueDate': '2026-11-30',
    });

    final tracking = view.progress.requirements.single.tracking;
    expect(tracking?.status, 'IN_PROGRESS');
    expect(tracking?.dueDate, '2026-11-30');
    expect(tracking?.note, 'Faltan pruebas');
  });

  test('el seguimiento no altera el progreso real del requisito', () async {
    final repository = repositoryWith({
      'companyId': 'company-a',
      'state': 'NOT_STARTED',
      'progress': {
        'total': 1,
        'resolvedCount': 0,
        'percent': 0,
        'requirements': [
          {
            'key': 'SET_TESTS',
            'label': 'Pruebas del SET',
            'mandatory': true,
            'automatable': false,
            'status': 'PENDING',
            'resolved': false,
            'tracking': {'status': 'COMPLETED', 'updatedAt': '2026-10-16'},
          },
        ],
      },
    });

    final view = await repository.updateDgiiRequirement(
      key: 'SET_TESTS',
      status: 'COMPLETED',
    );

    final requirement = view.progress.requirements.single;
    // Marcar el seguimiento como completado NO resuelve el requisito: el
    // progreso lo sigue determinando el backend.
    expect(requirement.tracking?.status, 'COMPLETED');
    expect(requirement.resolved, isFalse);
    expect(view.progress.resolvedCount, 0);
  });
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
