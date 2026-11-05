import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_session_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DosaCertificationSession', () {
    test('parsea companyId, URL, expiración y reused del backend', () {
      final session = DosaCertificationSession.fromJson(const {
        'companyId': 'company-a',
        'sessionUrl': 'https://dosasystem.com/sesion/abc',
        'expiresAt': '2026-11-04T18:00:00.000Z',
        'attemptNo': 2,
        'reused': true,
      });

      expect(session.companyId, 'company-a');
      expect(session.sessionUrl, 'https://dosasystem.com/sesion/abc');
      expect(session.attemptNo, 2);
      expect(session.reused, isTrue);
    });

    test('el enlace solo pertenece a la empresa autenticada', () {
      final session = DosaCertificationSession.fromJson(const {
        'companyId': 'company-a',
        'sessionUrl': 'https://dosasystem.com/sesion/abc',
      });
      expect(session.companyId == 'company-b', isFalse);
    });
  });

  group('DosaCertificationSessionException', () {
    test('solo cae al asistente cuando la API no está habilitada', () {
      expect(
        DosaCertificationSessionException('ECF_DOSA_SESSION_DISABLED')
            .canFallBackToAssistant,
        isTrue,
      );
      expect(
        DosaCertificationSessionException('HTTP_404').canFallBackToAssistant,
        isTrue,
      );
      // Un resultado incierto NUNCA debe caer al asistente: duplicaría la
      // postulación.
      expect(
        DosaCertificationSessionException('ECF_DOSA_SESSION_UNCERTAIN')
            .canFallBackToAssistant,
        isFalse,
      );
    });

    test('un 503 sin código legible sigue cayendo al asistente', () {
      // Caso real de producción: la apertura automática está apagada y el
      // cliente solo vio el estado HTTP. No debe quedarse sin asistente.
      for (final code in <String>['HTTP_503', 'HTTP_null', 'HTTP_500']) {
        expect(
          DosaCertificationSessionException(code).canFallBackToAssistant,
          isTrue,
          reason: code,
        );
      }
    });

    test('los estados que prohíben reintentar no caen al asistente', () {
      for (final code in <String>[
        'ECF_DOSA_SESSION_UNCERTAIN',
        'ECF_DOSA_SESSION_NOT_PERSISTED',
        'ECF_DOSA_SESSION_PROVIDER_ERROR',
        'ECF_DOSA_SESSION_IN_PROGRESS',
        'ECF_DOSA_SESSION_HISTORICAL_REVIEW_REQUIRED',
        'ECF_DOSA_SESSION_EMAIL_REQUIRED',
        'ECF_DOSA_SESSION_EMAIL_INVALID',
        'ECF_DOSA_SESSION_RNC_REQUIRED',
        'ECF_DOSA_SESSION_UNAUTHENTICATED',
      ]) {
        expect(
          DosaCertificationSessionException(code).canFallBackToAssistant,
          isFalse,
          reason: code,
        );
      }
    });

    test('explica correo faltante con un texto de usuario', () {
      final error =
          DosaCertificationSessionException('ECF_DOSA_SESSION_EMAIL_REQUIRED');
      expect(error.message.toLowerCase(), contains('correo'));
    });
  });

  group('DosaCertificationSessionApi — cuerpo de error del backend', () {
    /// Dio que devuelve el `body` recibido con el `status` indicado.
    Dio dioRespondiendo(Object? body, int status) {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response<dynamic>(
                requestOptions: options,
                statusCode: status,
                data: body,
              ),
            ),
          ),
        ),
      );
      return dio;
    }

    // Respuesta real de producción: POST /ecf/dosa/certification-session con
    // DOSA_CERTIFICATION_SESSIONS_ENABLED=false.
    const cuerpoReal =
        '{"message":"ECF_DOSA_SESSION_DISABLED","error":"Service Unavailable",'
        '"statusCode":503}';

    test('503 con el cuerpo en texto: lee el código y permite el fallback', () async {
      final api = DosaCertificationSessionApi(dioRespondiendo(cuerpoReal, 503));

      await expectLater(
        api.open(),
        throwsA(
          isA<DosaCertificationSessionException>()
              .having((e) => e.code, 'code', 'ECF_DOSA_SESSION_DISABLED')
              .having(
                (e) => e.canFallBackToAssistant,
                'canFallBackToAssistant',
                isTrue,
              ),
        ),
      );
    });

    test('cuerpo ya decodificado: mismo resultado', () async {
      final api = DosaCertificationSessionApi(
        dioRespondiendo(const {
          'message': 'ECF_DOSA_SESSION_DISABLED',
          'statusCode': 503,
        }, 503),
      );

      await expectLater(
        api.open(),
        throwsA(
          isA<DosaCertificationSessionException>()
              .having((e) => e.code, 'code', 'ECF_DOSA_SESSION_DISABLED')
              .having(
                (e) => e.canFallBackToAssistant,
                'canFallBackToAssistant',
                isTrue,
              ),
        ),
      );
    });

    test('un resultado incierto NO cae al asistente aunque llegue como texto', () async {
      final api = DosaCertificationSessionApi(
        dioRespondiendo(
          '{"message":"ECF_DOSA_SESSION_UNCERTAIN","statusCode":503}',
          503,
        ),
      );

      await expectLater(
        api.open(),
        throwsA(
          isA<DosaCertificationSessionException>().having(
            (e) => e.canFallBackToAssistant,
            'canFallBackToAssistant',
            isFalse,
          ),
        ),
      );
    });
  });

  group('CompanySettings.ecfContactEmail', () {
    test('sobrevive al round-trip de caché', () {
      final settings = CompanySettings.empty().copyWith(
        rnc: '101000001',
        ecfContactEmail: 'factura@empresa.com',
      );

      final restored = CompanySettings.fromMap(settings.toMap());

      expect(restored.ecfContactEmail, 'factura@empresa.com');
      expect(restored.copyWith().ecfContactEmail, 'factura@empresa.com');
      // Guardar otros campos no debe borrarlo.
      expect(
        restored.copyWith(phone: '809-000-0000').ecfContactEmail,
        'factura@empresa.com',
      );
    });
  });
}
