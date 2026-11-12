import 'dart:io';

import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `LicensePurchaseOverlay` vive en el `Stack` del `builder` de `MaterialApp`,
/// es decir **por encima del Navigator y sin ningún `Overlay` ancestro**.
///
/// Su botón de cerrar declaraba `tooltip: 'Cerrar aviso'`. `Tooltip`/`RawTooltip`
/// exige un `Overlay` ancestro y lanzaba `No Overlay widget found` en cada
/// reconstrucción, que el manejador global convertía en un aviso genérico
/// («No pudimos completar la operación») encima del aviso real.
///
/// Estas pruebas montan el overlay **igual que producción** para que la
/// regresión no pueda volver.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AuthSessionEvents expiredLicense() =>
      AuthSessionEvents()..requestUnauthorizedLogout(reason: 'license_expired');

  Future<void> pumpLikeProduction(
    WidgetTester tester,
    AuthSessionEvents events, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authSessionEventsProvider.overrideWith((ref) => events)],
        child: MaterialApp(
          locale: const Locale('es', 'DO'),
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => Stack(
            children: [
              if (child != null) child,
              const LicensePurchaseOverlay(),
            ],
          ),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('montado como en producción no lanza "No Overlay widget found"', (
    tester,
  ) async {
    await pumpLikeProduction(tester, expiredLicense());

    expect(find.text('Plan demo finalizado'), findsOneWidget);
    expect(
      find.byType(Tooltip),
      findsNothing,
      reason: 'Sin Overlay ancestro no puede haber Tooltip.',
    );
    expect(
      tester.takeException(),
      isNull,
      reason:
          'Construir el aviso de licencia no puede generar un segundo error.',
    );
  });

  testWidgets('el aviso de licencia conserva su contenido y su compra', (
    tester,
  ) async {
    await pumpLikeProduction(tester, expiredLicense());

    expect(find.text('Plan demo finalizado'), findsOneWidget);
    expect(find.text('Comprar por WhatsApp'), findsOneWidget);
    expect(find.textContaining('829-531-9442'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Cerrar aviso" sigue accesible y cierra el aviso', (
    tester,
  ) async {
    final events = expiredLicense();
    await pumpLikeProduction(tester, events);

    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(
      find.bySemanticsLabel('Cerrar aviso'),
      findsOneWidget,
      reason: 'La accesibilidad se conserva con Icon.semanticLabel.',
    );
    semantics.dispose();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text('Plan demo finalizado'), findsNothing);
    expect(events.isLicenseLogout, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('en pantalla compacta tampoco lanza errores', (tester) async {
    await pumpLikeProduction(
      tester,
      expiredLicense(),
      size: const Size(360, 640),
    );

    expect(find.text('Plan demo finalizado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('en el árbol de la app el aviso de error va DESPUÉS del de licencia', () {
    final source = File('lib/main.dart').readAsStringSync();
    final licenseIndex = source.indexOf('const LicensePurchaseOverlay()');
    final errorOverlayIndex = source.indexOf('const AppErrorOverlay()');

    expect(licenseIndex, greaterThan(-1));
    expect(errorOverlayIndex, greaterThan(-1));
    expect(
      errorOverlayIndex,
      greaterThan(licenseIndex),
      reason:
          'El aviso compacto debe pintarse encima de los overlays de bloqueo; '
          'si vuelve a colocarse antes, queda ilegible bajo el velo.',
    );
  });
}
