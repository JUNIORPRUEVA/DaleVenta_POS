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

EcfCertificateReport _validReport() => EcfCertificateReport.fromJson({
  'valid': true,
  'code': null,
  'message': 'El certificado es válido y está vigente.',
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
    'identity': 'NOT_EVALUATED',
    'trustChain': 'NOT_EVALUATED',
    'revocation': 'NOT_EVALUATED',
  },
  'identity': 'NOT_EVALUATED',
  'notes': ['La cadena de confianza no se ha comprobado.'],
});

EcfCertificateReport _errorReport() => EcfCertificateReport.fromJson({
  'valid': false,
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

  testWidgets('archivo + contraseña: valida y muestra datos verificables', (
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
    expect(find.text('Certificado válido y vigente'), findsOneWidget);
    expect(find.text('MANOLO LIO'), findsOneWidget);
    expect(find.text('40323211222'), findsOneWidget);
    // Lo no comprobado se declara, no se omite.
    expect(find.text('Lo que todavía no se comprobó'), findsOneWidget);
    expect(find.text('Cadena de confianza del certificado'), findsOneWidget);
    // DGII CA5241 y CA5388: identidad del administrador e-CF y delegación.
    expect(find.textContaining('administrador e-CF del RNC'), findsOneWidget);
    expect(
      find.textContaining('Delegación de firma registrada'),
      findsOneWidget,
    );
    expect(
      find.textContaining('no significa que la DGII haya aceptado'),
      findsOneWidget,
    );
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
    expect(find.text('Certificado válido y vigente'), findsNothing);
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
