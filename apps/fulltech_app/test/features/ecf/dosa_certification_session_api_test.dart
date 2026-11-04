import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/features/ecf/dosa/dosa_certification_session_api.dart';
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

    test('explica correo faltante con un texto de usuario', () {
      final error =
          DosaCertificationSessionException('ECF_DOSA_SESSION_EMAIL_REQUIRED');
      expect(error.message.toLowerCase(), contains('correo'));
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
