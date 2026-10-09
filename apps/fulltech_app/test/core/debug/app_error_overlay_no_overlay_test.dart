import 'package:daleventa_pos/core/debug/app_error_overlay.dart';
import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// BUG A — Regresión UAT Cafetería La Bomba.
///
/// En producción `AppErrorOverlay` NO se monta dentro de `home`, sino en el
/// `builder` de `MaterialApp` (`lib/main.dart`), es decir POR ENCIMA del
/// Navigator y por tanto SIN ningún `Overlay` ancestro:
///
/// ```dart
/// MaterialApp.router(builder: (context, child) => Stack(children: [
///   if (child != null) child, const AppLoadingOverlay(),
///   const AppErrorOverlay(), ...
/// ]))
/// ```
///
/// El banner incluía `IconButton(tooltip: 'Cerrar')`. `Tooltip`/`RawTooltip`
/// exige un `Overlay` ancestro y al mostrarse (hover/tap) lanzaba un
/// FlutterError duro (`RawTooltip widgets require an Overlay widget ancestor`),
/// es decir el sistema global de errores generaba un SEGUNDO error al intentar
/// mostrar el primer error.
///
/// El test anterior de este banner montaba el overlay dentro de
/// `MaterialApp(home: ...)`, donde SÍ existe Overlay, así que nunca podía
/// detectar el fallo real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => AppErrorReporter.instance.resetForTesting());
  tearDown(() => AppErrorReporter.instance.resetForTesting());

  /// Reproduce el árbol de producción: el banner hermano del Navigator (sin
  /// Overlay ancestro propio), pero con las localizaciones/theme que
  /// `MaterialApp` sí aporta por encima del `builder`.
  Future<void> pumpOverlayAsInProduction(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es', 'DO'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(body: SizedBox.shrink()),
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            const AppErrorOverlay(),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void recordIncident() {
    AppErrorReporter.instance.record(
      ApiException.detailed(
        message: 'No pudimos conectarnos al servidor.',
        type: ApiErrorType.network,
        displayCode: 'NETWORK_UNAVAILABLE',
        retryable: true,
      ),
      StackTrace.current,
      context: 'Test',
      retryLabel: 'Reintentar',
      onRetry: () async {},
    );
  }

  testWidgets('montado como en producción (sin Overlay ancestro) el banner '
      'aparece sin lanzar ningún error secundario', (tester) async {
    await pumpOverlayAsInProduction(tester);
    recordIncident();
    await tester.pump();
    await tester.pump();

    expect(find.text('Sin conexión'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'Mostrar una incidencia no puede generar un segundo error.',
    );
  });

  testWidgets('el hover sobre "Cerrar" (que antes disparaba RawTooltip) no '
      'rompe el banner', (tester) async {
    await pumpOverlayAsInProduction(tester);
    recordIncident();
    await tester.pump();
    await tester.pump();

    // Gesto exacto que en producción disparaba el Tooltip del botón cerrar.
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.close_rounded)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.takeException(),
      isNull,
      reason: 'RawTooltip exigía un Overlay ancestro inexistente en el builder.',
    );
    expect(find.text('Sin conexión'), findsOneWidget);
  });

  testWidgets('el banner no depende de Tooltip y "Cerrar" sigue accesible', (
    tester,
  ) async {
    await pumpOverlayAsInProduction(tester);
    recordIncident();
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(Tooltip),
      findsNothing,
      reason: 'Tooltip/RawTooltip exige un Overlay ancestro: el banner vive '
          'fuera del Navigator y no puede usarlo.',
    );

    final semantics = tester.ensureSemantics();
    // El árbol de semántica se construye en el siguiente frame.
    await tester.pump();
    expect(
      find.bySemanticsLabel('Cerrar'),
      findsOneWidget,
      reason: 'La accesibilidad se mantiene sin Tooltip.',
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Icon && widget.semanticLabel == 'Cerrar',
      ),
      findsOneWidget,
      reason: 'El botón cerrar expone su etiqueta sin depender de Tooltip.',
    );
    semantics.dispose();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sin conexión'), findsNothing);
    expect(AppErrorReporter.instance.lastError.value, isNull);
    expect(tester.takeException(), isNull);
  });
}
