import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_intent_api.dart';

/// Preasociación empresa–RNC desde Flutter.
///
/// Se prueba el contrato tal como lo devuelve el backend: la intención debe
/// quedar confirmada **antes** de montar el asistente, y ningún error debe
/// abrirlo. Nada de aquí contiene claves: la respuesta del endpoint tampoco.
void main() {
  group('DosaCertificationIntent.fromJson', () {
    test('interpreta la respuesta del registro', () {
      final intent = DosaCertificationIntent.fromJson(const {
        'ok': true,
        'companyId': 'company-1',
        'rnc': '133306001',
        'sessionId': 'session-1',
        'attemptNo': 2,
        'created': true,
        'status': 'NOT_STARTED',
        'provider': 'DOSA',
        'ecfEnabled': true,
        'fiscalAuthorizationGranted': false,
      });

      expect(intent.companyId, 'company-1');
      expect(intent.rnc, '133306001');
      expect(intent.sessionId, 'session-1');
      expect(intent.attemptNo, 2);
      expect(intent.created, isTrue);
      expect(intent.provider, 'DOSA');
      expect(intent.ecfEnabled, isTrue);
    });

    test('nunca declara autorización fiscal', () {
      final intent = DosaCertificationIntent.fromJson(const {
        'sessionId': 'session-1',
        'fiscalAuthorizationGranted': true, // el backend no lo envía jamás
      });
      expect(intent.fiscalAuthorizationGranted, isFalse);
    });

    test('tolera campos ausentes sin lanzar', () {
      final intent = DosaCertificationIntent.fromJson(const {});
      expect(intent.sessionId, '');
      expect(intent.attemptNo, 0);
      expect(intent.created, isFalse);
    });
  });

  group('DosaIntentState.fromJson', () {
    test('lee el estado interno de la preparación', () {
      final state = DosaIntentState.fromJson(const {
        'ok': true,
        'companyId': 'company-1',
        'canonicalRnc': '133306001',
        'canonicalSource': 'FISCAL_CONFIG',
        'ecfEnabled': true,
        'provider': 'DOSA',
        'canRegister': true,
        'blockingReasons': <String>[],
        'session': {
          'id': 'session-1',
          'status': 'RUNNING',
          'attemptNo': 1,
          'sessionUrl': null,
        },
        'credentials': {
          'environment': 'test',
          'status': 'PENDING_CONFIRMATION',
          'present': {
            'hasProductionKey': true,
            'hasTestKey': true,
            'hasSecret': false,
          },
        },
        'fiscalAuthorizationGranted': false,
      });

      expect(state.canonicalRnc, '133306001');
      expect(state.canRegister, isTrue);
      expect(state.sessionStatus, 'RUNNING');
      expect(state.credentialStatus, 'PENDING_CONFIRMATION');
      expect(state.blockingReasons, isEmpty);
      expect(state.fiscalAuthorizationGranted, isFalse);
    });

    test('propaga los motivos de bloqueo', () {
      final state = DosaIntentState.fromJson(const {
        'canRegister': false,
        'blockingReasons': ['COMPANY_RNC_NOT_VERIFIED'],
      });
      expect(state.canRegister, isFalse);
      expect(state.blockingReasons, contains('COMPANY_RNC_NOT_VERIFIED'));
    });

    test('emisión apagada NO impide preparar', () {
      // Preparar y activar son estados distintos: el interruptor de emisión se
      // informa, pero no condiciona la preparación.
      final state = DosaIntentState.fromJson(const {
        'ecfEnabled': false,
        'canRegister': true,
        'blockingReasons': [],
      });
      expect(state.ecfEnabled, isFalse);
      expect(state.canRegister, isTrue);
      expect(state.blockingReasons, isEmpty);
    });
  });

  group('DosaIntentException', () {
    test('traduce cada código a un mensaje para el administrador', () {
      const codes = {
        'COMPANY_RNC_NOT_VERIFIED': 'RNC verificado',
        'RNC_DOES_NOT_MATCH_COMPANY_IDENTITY': 'no coincide',
        'AMBIGUOUS_RNC': 'comparte este RNC',
        'ECF_DOSA_INTENT_IN_PROGRESS': 'en curso',
        'SESSION_CLAIM_FAILED': 'No se pudo registrar',
        'ECF_DOSA_INTENT_UNAUTHENTICATED': 'Vuelve a iniciar sesión',
      };
      codes.forEach((code, fragment) {
        expect(
          DosaIntentException(code).message,
          contains(fragment),
          reason: 'código $code',
        );
      });
    });

    test('un código desconocido no filtra detalles internos', () {
      final message = DosaIntentException('HTTP_500').message;
      expect(message, contains('No se pudo registrar'));
      expect(message, isNot(contains('HTTP_500')));
    });
  });

  group('dosaIntentRegistrationProvider', () {
    test('registra la intención enviando el RNC solo como pista', () async {
      final api = _RecordingApi();
      final container = ProviderContainer(
        overrides: [dosaCertificationIntentApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final intent = await container.read(
        dosaIntentRegistrationProvider('133306001').future,
      );

      expect(intent.sessionId, 'session-1');
      expect(api.registerCalls, ['133306001']);
      expect(intent.fiscalAuthorizationGranted, isFalse);
    });

    test('si el backend rechaza, el provider falla y el asistente no se abre',
        () async {
      final api = _FailingApi('AMBIGUOUS_RNC');
      final container = ProviderContainer(
        overrides: [dosaCertificationIntentApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(dosaIntentRegistrationProvider('133306001').future),
        throwsA(
          isA<DosaIntentException>().having(
            (error) => error.code,
            'code',
            'AMBIGUOUS_RNC',
          ),
        ),
      );
    });

    test('el estado se consulta al volver al sistema', () async {
      final api = _RecordingApi();
      final container = ProviderContainer(
        overrides: [dosaCertificationIntentApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final state = await container.read(dosaIntentStateProvider.future);
      expect(state.sessionStatus, 'RUNNING');
      expect(api.stateCalls, 1);
    });
  });
}

class _RecordingApi implements DosaCertificationIntentApi {
  final List<String?> registerCalls = <String?>[];
  int stateCalls = 0;

  @override
  Future<DosaCertificationIntent> register({String? rnc}) async {
    registerCalls.add(rnc);
    return DosaCertificationIntent.fromJson(const {
      'companyId': 'company-1',
      'rnc': '133306001',
      'sessionId': 'session-1',
      'attemptNo': 1,
      'created': true,
      'status': 'NOT_STARTED',
      'provider': 'DOSA',
      'ecfEnabled': true,
    });
  }

  @override
  Future<DosaIntentState> state() async {
    stateCalls += 1;
    return DosaIntentState.fromJson(const {
      'session': {'id': 'session-1', 'status': 'RUNNING', 'attemptNo': 1},
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingApi implements DosaCertificationIntentApi {
  _FailingApi(this.code);
  final String code;

  @override
  Future<DosaCertificationIntent> register({String? rnc}) async {
    throw DosaIntentException(code);
  }

  @override
  Future<DosaIntentState> state() async => throw DosaIntentException(code);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
