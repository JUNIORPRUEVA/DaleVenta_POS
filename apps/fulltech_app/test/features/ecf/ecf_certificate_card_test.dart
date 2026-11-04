import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/ecf/data/ecf_certificate_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_certificate_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_certificate_card.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_habilitacion_video_card.dart';

class _FakeCertificateRepository implements EcfCertificateRepository {
  _FakeCertificateRepository(this._result);

  final EcfCertificateReport Function() _result;
  String? lastPassword;
  String? lastFileName;
  int calls = 0;

  @override
  Future<EcfCertificateReport> validate({
    required List<int> bytes,
    required String fileName,
    required String password,
  }) async {
    calls += 1;
    lastPassword = password;
    lastFileName = fileName;
    return _result();
  }
}

EcfCertificateReport _report({
  bool valid = true,
  bool canProceed = true,
  String? code,
  String identity = 'MATCH_REPRESENTATIVE',
  String? matchedAs = 'REPRESENTATIVE',
  bool hasCompanyTaxId = true,
  bool hasRepresentativeId = true,
  List<String> missing = const <String>[],
  String holderKind = 'PERSON',
  String message = 'El certificado es válido y está vigente.',
}) => EcfCertificateReport.fromJson({
  'valid': valid,
  'canProceed': canProceed,
  'code': code,
  'message': message,
  'certificate': {
    'commonName': 'MANOLO LIO',
    'organization': 'ECF VISUAL UAT DEMO',
    'serialNumber': '40323211222',
    'issuer': 'AC DEMO',
    'notBefore': '2026-01-01T00:00:00.000Z',
    'notAfter': '2027-01-01T00:00:00.000Z',
    'daysRemaining': 61,
    'fingerprintShort': '…AA:BB:CC',
  },
  'checks': {
    'format': 'PASS',
    'password': 'PASS',
    'privateKey': 'PASS',
    'keyMatch': 'PASS',
    'validity': 'PASS',
    'identity': valid && canProceed ? 'PASS' : 'NOT_EVALUATED',
    'trustChain': 'NOT_EVALUATED',
    'revocation': 'NOT_EVALUATED',
  },
  'identity': identity,
  'notes': ['Esta comprobación es local y no confirma ninguna aceptación.'],
  'diagnostics': {
    'identityMatchedAs': matchedAs,
    'canonical': {
      'hasCompanyTaxId': hasCompanyTaxId,
      'hasRepresentativeId': hasRepresentativeId,
    },
    'missingCanonicalFields': missing,
    'certificate': {
      'hasSerialNumber': true,
      'hasCommonNameDigits': true,
      'hasOrganizationDigits': false,
      'holderKind': holderKind,
      'certificatesInContainer': 1,
    },
    'validity': {
      'notBefore': '2026-01-01T00:00:00.000Z',
      'notAfter': '2027-01-01T00:00:00.000Z',
      'daysRemaining': 61,
    },
    'privateKey': {'present': true, 'matchesCertificate': true},
  },
});

EcfCertificateReport _validReport() => _report();

/// El archivo es correcto pero falta la cédula del representante: no habilita
/// a continuar y NO se presenta como certificado ajeno.
EcfCertificateReport _notVerifiableReport() => _report(
  canProceed: false,
  code: 'ECF_CERTIFICATE_IDENTITY_NOT_VERIFIABLE',
  identity: 'NOT_VERIFIABLE',
  matchedAs: null,
  hasRepresentativeId: false,
  missing: const <String>['representative.identification'],
  message:
      'El certificado se abrió correctamente, pero el expediente todavía no '
      'tiene la cédula del representante legal.',
);

EcfCertificateReport _mismatchReport() => _report(
  valid: false,
  canProceed: false,
  code: 'ECF_CERTIFICATE_IDENTITY_MISMATCH',
  identity: 'MISMATCH',
  matchedAs: null,
  message:
      'El certificado no corresponde a la empresa o al representante del '
      'expediente.',
);

EcfCertificateReport _errorReport() => EcfCertificateReport.fromJson({
  'valid': false,
  'canProceed': false,
  'code': 'ECF_CERTIFICATE_WRONG_PASSWORD',
  'message': 'La contraseña no corresponde a este certificado.',
  'certificate': null,
  'checks': {
    'format': 'PASS',
    'password': 'FAIL',
    'privateKey': 'NOT_EVALUATED',
    'keyMatch': 'NOT_EVALUATED',
    'validity': 'NOT_EVALUATED',
    'identity': 'NOT_EVALUATED',
    'trustChain': 'NOT_EVALUATED',
    'revocation': 'NOT_EVALUATED',
  },
  'identity': 'NOT_EVALUATED',
  'notes': [],
});

Widget _harness(Widget child) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  testWidgets('sin archivo ni contraseña el botón está deshabilitado', (
    tester,
  ) async {
    final repository = _FakeCertificateRepository(_validReport);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(const EcfCertificateCard(pickFile: _noFile)),
      ),
    );

    final button = find.widgetWithText(FilledButton, 'Validar certificado');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(find.text('Ningún archivo seleccionado'), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets('éxito compacto: datos y salvedades solo en detalles', (
    tester,
  ) async {
    final repository = _FakeCertificateRepository(_validReport);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(
          EcfCertificateCard(
            pickFile: () async =>
                (name: 'certificado.pfx', bytes: const [1, 2, 3]),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    expect(find.text('certificado.pfx'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      'clave-secreta',
    );
    await tester.pump();

    final button = find.widgetWithText(FilledButton, 'Validar certificado');
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.lastPassword, 'clave-secreta');
    expect(repository.lastFileName, 'certificado.pfx');
    expect(find.text('Certificado verificado correctamente'), findsOneWidget);
    expect(
      find.text('Vigente hasta ${_validReport().certificate!.notAfterLabel}'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('ecf_certificate_password')),
      findsNothing,
    );
    expect(find.text('MANOLO LIO'), findsNothing);
    expect(find.text('40323211222'), findsNothing);
    expect(find.text('…AA:BB:CC'), findsNothing);
    expect(find.text('Lo que todavía no se comprobó'), findsNothing);
    expect(find.text('Cambiar certificado'), findsOneWidget);
    await tester.tap(find.text('Ver detalles'));
    await tester.pumpAndSettle();
    expect(find.text('MANOLO LIO'), findsOneWidget);
    expect(find.text('40323211222'), findsOneWidget);
    expect(find.text('…AA:BB:CC'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ecf_certificate_password')),
      findsOneWidget,
    );
    expect(find.text('Lo que todavía no se comprobó'), findsOneWidget);
    expect(find.text('Cadena de confianza del certificado'), findsOneWidget);
    // DGII CA5241 y CA5388: identidad del administrador e-CF y delegación.
    expect(find.textContaining('administrador e-CF del RNC'), findsOneWidget);
    expect(
      find.textContaining('Delegación de firma registrada'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no es una validación de la DGII'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ocultar detalles'));
    await tester.pumpAndSettle();
    expect(find.text('40323211222'), findsNothing);
  });

  testWidgets('contraseña incorrecta: error claro, sin éxito falso', (
    tester,
  ) async {
    final repository = _FakeCertificateRepository(_errorReport);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(
          EcfCertificateCard(
            pickFile: () async => (name: 'certificado.p12', bytes: const [9]),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      'mala',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Validar certificado'));
    await tester.pumpAndSettle();

    expect(find.text('El certificado no es utilizable'), findsOneWidget);
    expect(
      find.text('La contraseña no corresponde a este certificado.'),
      findsOneWidget,
    );
    expect(find.text('Certificado verificado correctamente'), findsNothing);
  });

  testWidgets(
    'al volver muestra el resultado de la misma sesión sin repetir clave',
    (tester) async {
      final report = _validReport();
      final repository = _FakeCertificateRepository(_validReport);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ecfCertificateRepositoryProvider.overrideWithValue(repository),
          ],
          child: _harness(
            EcfCertificateCard(
              initialReport: report,
              initialFileName: 'certificado.pfx',
              pickFile: _noFile,
            ),
          ),
        ),
      );

      expect(find.text('Certificado verificado correctamente'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ecf_certificate_password')),
        findsNothing,
      );
      expect(repository.calls, 0);
      await tester.tap(find.text('Cambiar certificado'));
      await tester.pumpAndSettle();
      expect(find.text('Certificado verificado correctamente'), findsOneWidget);
    },
  );

  testWidgets('titular no verificable: bloquea el avance y dice qué falta', (
    tester,
  ) async {
    final repository = _FakeCertificateRepository(_notVerifiableReport);
    final gates = <EcfCertificateGate>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(
          EcfCertificateCard(
            pickFile: () async =>
                (name: 'certificado.pfx', bytes: const [1, 2, 3]),
            onGateChanged: gates.add,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      'clave',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Validar certificado'));
    await tester.pumpAndSettle();

    expect(gates.last.ready, isFalse);
    expect(gates.last.reason, contains('cédula del representante'));
    // Mensaje propio, no «no es utilizable»: el archivo está bien.
    expect(find.text('Falta comprobar el titular'), findsOneWidget);
    expect(find.text('El certificado no es utilizable'), findsNothing);
    expect(find.text('Certificado verificado correctamente'), findsNothing);
    // Diagnóstico seguro: qué dato canónico falta, sin exponer el valor.
    expect(find.text('Por qué'), findsOneWidget);
    expect(find.text('Cédula del representante'), findsOneWidget);
    expect(find.text('RNC en el expediente'), findsOneWidget);
  });

  testWidgets('identidad no coincidente: diagnóstico sin datos personales', (
    tester,
  ) async {
    final repository = _FakeCertificateRepository(_mismatchReport);
    final gates = <EcfCertificateGate>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(
          EcfCertificateCard(
            pickFile: () async => (name: 'ajeno.p12', bytes: const [7]),
            onGateChanged: gates.add,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      'clave',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Validar certificado'));
    await tester.pumpAndSettle();

    expect(gates.last.ready, isFalse);
    expect(gates.last.reason, contains('no coincide'));
    expect(find.text('El certificado no es utilizable'), findsOneWidget);
    expect(find.text('Tipo de titular'), findsOneWidget);
  });

  testWidgets('cambiar la contraseña invalida el resultado anterior', (
    tester,
  ) async {
    final repository = _FakeCertificateRepository(_validReport);
    final gates = <EcfCertificateGate>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(
          EcfCertificateCard(
            pickFile: () async =>
                (name: 'certificado.pfx', bytes: const [1, 2, 3]),
            onGateChanged: gates.add,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      'clave-buena',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Validar certificado'));
    await tester.pumpAndSettle();
    expect(gates.last.ready, isTrue);
    expect(find.text('Certificado verificado correctamente'), findsOneWidget);
    await tester.tap(find.text('Ver detalles'));
    await tester.pumpAndSettle();

    // Con otra contraseña, el informe anterior ya no vale.
    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      'otra-clave',
    );
    await tester.pumpAndSettle();

    expect(gates.last.ready, isFalse);
    expect(gates.last.reason, isNotNull);
    expect(find.text('Certificado verificado correctamente'), findsNothing);
  });

  testWidgets('cambiar el archivo invalida el resultado anterior', (
    tester,
  ) async {
    var pick = 0;
    final repository = _FakeCertificateRepository(_validReport);
    final gates = <EcfCertificateGate>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(
          EcfCertificateCard(
            pickFile: () async {
              pick += 1;
              return (name: 'certificado-$pick.pfx', bytes: const [1, 2, 3]);
            },
            onGateChanged: gates.add,
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      'clave-buena',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Validar certificado'));
    await tester.pumpAndSettle();
    expect(gates.last.ready, isTrue);

    await tester.tap(find.text('Cambiar certificado'));
    await tester.pumpAndSettle();

    expect(gates.last.ready, isFalse);
    expect(find.text('Certificado verificado correctamente'), findsNothing);
    expect(find.text('certificado-2.pfx'), findsOneWidget);
  });

  testWidgets('no expone la contraseña del certificado en la interfaz', (
    tester,
  ) async {
    const password = 'clave-super-secreta-987';
    final repository = _FakeCertificateRepository(_validReport);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ecfCertificateRepositoryProvider.overrideWithValue(repository),
        ],
        child: _harness(
          EcfCertificateCard(
            pickFile: () async =>
                (name: 'certificado.pfx', bytes: const [1, 2, 3]),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ecf_certificate_password')),
      password,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Validar certificado'));
    await tester.pumpAndSettle();

    // La contraseña solo vive en el controlador del campo oscurecido: ningún
    // texto visible la repite (ni el informe, ni el diagnóstico, ni las notas).
    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');
    expect(rendered.contains(password), isFalse);
    expect(repository.lastPassword, password);
  });

  for (final width in <double>[360, 768, 1366]) {
    testWidgets('la tarjeta no desborda a ${width.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repository = _FakeCertificateRepository(_validReport);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ecfCertificateRepositoryProvider.overrideWithValue(repository),
          ],
          child: _harness(
            EcfCertificateCard(
              pickFile: () async => (name: 'certificado.pfx', bytes: const [1]),
            ),
          ),
        ),
      );
      await tester.tap(find.widgetWithText(OutlinedButton, 'Seleccionar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ecf_certificate_password')),
        'x',
      );
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Validar certificado'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('el vídeo no existe: marcador 16:9 sin simular reproducción', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(const EcfHabilitacionVideoCard()));
    // El espacio reservado existe y se identifica, pero no hay reproductor.
    expect(
      find.byKey(const ValueKey('ecf_habilitacion_video_placeholder')),
      findsOneWidget,
    );
    expect(find.text('Aquí irá el vídeo de preparación'), findsOneWidget);
    expect(find.text('Todavía no está disponible'), findsOneWidget);
    expect(find.text('Ver el vídeo de preparación'), findsNothing);
    expect(find.text('Antes de empezar'), findsOneWidget);
    expect(find.text('Vídeo no disponible'), findsOneWidget);
    // Sin vídeo no se repiten los requisitos: ya están en la portada.
    expect(find.textContaining('FI-GDF-016'), findsNothing);
    expect(find.textContaining('Los tres puntos anteriores'), findsOneWidget);
    expect(find.text('Abrir portal de la DGII'), findsOneWidget);
  });

  testWidgets('con URL configurada aparece el espacio 16:9', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(
        const EcfHabilitacionVideoCard(videoUrl: 'https://example.test/video'),
      ),
    );
    expect(
      find.byKey(const ValueKey('ecf_habilitacion_video_surface')),
      findsOneWidget,
    );
    expect(find.text('Ver el vídeo de preparación'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ecf_habilitacion_video_placeholder')),
      findsNothing,
    );
    expect(find.text('Vídeo no disponible'), findsNothing);
    final surface = tester.getSize(
      find.byKey(const ValueKey('ecf_habilitacion_video_surface')),
    );
    expect(surface.width / surface.height, closeTo(16 / 9, 0.05));
    expect(tester.takeException(), isNull);
  });
}

Future<EcfPickedCertificate?> _noFile() async => null;
