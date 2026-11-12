import 'package:daleventa_pos/core/debug/app_error_overlay.dart';
import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ubicación y no bloqueo del aviso compacto de errores recuperables.
///
/// - Escritorio (Windows): esquina inferior derecha, por encima de la franja de
///   acciones del POS, para no tapar Cobrar/Guardar.
/// - Layouts compactos (móvil/web estrecho): arriba, porque el pie de pantalla
///   lo ocupa el carro y taparlo sí interrumpiría una venta.
/// - Nunca bloquea la interacción fuera de su propia caja.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const title = 'No pudimos comprobar las actualizaciones.';
  const message = 'Puedes seguir utilizando FullPOS normalmente.';

  setUp(() => AppErrorReporter.instance.resetForTesting());
  tearDown(() => AppErrorReporter.instance.resetForTesting());

  void setViewport(WidgetTester tester, Size logicalSize) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = logicalSize;
    addTearDown(tester.view.reset);
  }

  Widget app({required Widget home, double textScale = 1}) {
    return MaterialApp(
      locale: const Locale('es', 'DO'),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: Stack(
          children: [if (child != null) child, const AppErrorOverlay()],
        ),
      ),
      home: home,
    );
  }

  void recordUpdaterFailure() {
    AppErrorReporter.instance.record(
      StateError('updater persistence failed'),
      StackTrace.current,
      context: 'actualizacion:CHECK_ERROR',
      title: title,
      userMessage: message,
      severity: AppErrorSeverity.warning,
      noticeCategory: null,
    );
  }

  void recordCriticalFailure() {
    AppErrorReporter.instance.record(
      StateError('no se pudo guardar la venta'),
      StackTrace.current,
      context: 'ventas',
      noticeCategory: null,
    );
  }

  Rect cardRect(WidgetTester tester) => tester.getRect(
    find.ancestor(of: find.text(title), matching: find.byType(Material)).first,
  );

  testWidgets('escritorio 1440x900: el aviso aparece abajo a la derecha y es '
      'compacto', (tester) async {
    setViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    final rect = cardRect(tester);
    expect(rect.right, closeTo(1440 - 16, 1));
    expect(
      rect.bottom,
      closeTo(900 - 16 - kErrorNoticeBottomReservedHeight, 1),
    );
    expect(rect.left, greaterThan(1440 / 2));
    expect(rect.top, greaterThan(900 / 2));
    expect(
      rect.width,
      lessThanOrEqualTo(360),
      reason: 'El aviso debe ser pequeño y discreto.',
    );
    expect(find.text(title), findsOneWidget);
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('Windows de baja resolución (1024x600) mantiene el aviso abajo a '
      'la derecha sin desbordar', (tester) async {
    setViewport(tester, const Size(1024, 600));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    final rect = cardRect(tester);
    expect(rect.left, greaterThan(0));
    expect(rect.top, greaterThan(0));
    expect(rect.right, lessThanOrEqualTo(1024));
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(rect.bottom, greaterThan(600 / 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('escala DPI alta (texto x2) no rompe el aviso', (tester) async {
    setViewport(tester, const Size(1024, 600));
    await tester.pumpWidget(
      app(home: const Scaffold(body: SizedBox.expand()), textScale: 2),
    );
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    final rect = cardRect(tester);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1024));
    expect(tester.takeException(), isNull);
  });

  testWidgets('móvil web (360x640) mantiene el aviso arriba y sin '
      'desbordamientos', (tester) async {
    setViewport(tester, const Size(360, 640));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    final rect = cardRect(tester);
    expect(rect.top, lessThan(640 / 2));
    expect(rect.center.dx, closeTo(180, 2));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
    for (final chunk in <String>[
      'RenderFlex',
      'overflowed',
      'Exception',
      'StateError',
    ]) {
      expect(find.textContaining(chunk), findsNothing);
    }
  });

  testWidgets('no tapa la barra de acciones del POS ni bloquea la venta', (
    tester,
  ) async {
    setViewport(tester, const Size(1280, 800));
    var charges = 0;
    await tester.pumpWidget(
      app(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand()),
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => charges += 1,
                        child: const Text('Guardar venta'),
                      ),
                    ),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => charges += 1,
                        child: const Text('Cobrar'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    final rect = cardRect(tester);
    final barRect = tester.getRect(find.text('Cobrar'));
    expect(
      rect.bottom,
      lessThan(barRect.top),
      reason: 'El aviso nunca puede cubrir los controles de cobro.',
    );

    // La venta sigue funcionando con el aviso en pantalla.
    await tester.tap(find.text('Cobrar'));
    await tester.pump();
    expect(charges, 1);
  });

  testWidgets('la X cierra el aviso y la venta sigue respondiendo', (
    tester,
  ) async {
    setViewport(tester, const Size(1280, 800));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();
    expect(find.text(title), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.text(title), findsNothing);
    expect(AppErrorReporter.instance.lastError.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el aviso no muestra detalles técnicos al cliente', (
    tester,
  ) async {
    setViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    for (final forbidden in <String>[
      'DALEVENTAS_POS_ROOT',
      'StateError',
      'Stack trace',
      'Exception',
      'actualizacion:',
    ]) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: 'La interfaz del cliente no puede exponer "$forbidden".',
      );
    }
  });

  testWidgets('un fallo recuperable usa un estilo neutro, sin alarma', (
    tester,
  ) async {
    setViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
  });

  testWidgets('el aviso recuperable ocupa dos líneas y se lee completo', (
    tester,
  ) async {
    setViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    final rect = cardRect(tester);
    expect(
      rect.height,
      lessThan(56),
      reason: 'Debe ser una tarjeta de dos líneas, sin fila de acciones.',
    );

    // Exactamente dos textos: título y descripción, ambos en una sola línea
    // (el ajuste real del texto se comprueba en la verificación visual, porque
    // la fuente de `flutter_test` mide todos los glifos igual y no es
    // representativa).
    expect(find.byType(Text), findsNWidgets(2));
    expect(find.text('Detalles'), findsNothing);
    expect(find.byType(TextButton), findsNothing);

    for (final label in <String>[title, message]) {
      final text = tester.widget<Text>(find.text(label));
      expect(
        text.maxLines,
        1,
        reason: 'Cada línea del aviso debe ocupar exactamente una línea.',
      );
      expect(
        text.data,
        label,
        reason: 'El contenido completo debe llegar al widget.',
      );
    }
  });

  testWidgets('en 1024x600 el aviso sigue siendo de dos líneas', (
    tester,
  ) async {
    setViewport(tester, const Size(1024, 600));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordUpdaterFailure();
    await tester.pump();
    await tester.pump();

    expect(find.text(message), findsOneWidget);
    expect(tester.widget<Text>(find.text(message)).maxLines, 1);
    expect(cardRect(tester).height, lessThan(56));
  });

  testWidgets('un error crítico conserva su estilo de alerta', (tester) async {
    setViewport(tester, const Size(1440, 900));
    await tester.pumpWidget(app(home: const Scaffold(body: SizedBox.expand())));
    await tester.pumpAndSettle();

    recordCriticalFailure();
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
  });
}
