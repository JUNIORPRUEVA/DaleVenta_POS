import 'package:daleventa_pos/core/widgets/app_gesture_detector.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Paridad funcional entre el `GestureDetector` nativo y el envoltorio del
/// proyecto. Cada escenario se ejecuta con la MISMA configuración en ambos, y
/// se comparan los resultados: así la conclusión no depende de suposiciones.
///
/// Nota: Flutter prohíbe combinar `onPan*` con `onHorizontal/VerticalDrag*` en
/// el mismo detector, por eso cada escenario usa un detector especializado.
void main() {
  final log = <String>[];

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 260, height: 180, child: child)),
    ),
  );

  Future<void> reset(WidgetTester tester) async {
    log.clear();
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<void> runBoth(
    WidgetTester tester, {
    required Widget Function() native,
    required Widget Function() wrapped,
  }) async {
    await tester.pumpWidget(host(native()));
    await tester.pumpAndSettle();
  }

  testWidgets('clic: 1 tap en nativo y en envoltorio', (tester) async {
    Widget n() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => log.add('tap'),
      child: const SizedBox.expand(),
    );
    Widget w() => app.GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => log.add('tap'),
      child: const SizedBox.expand(),
    );

    await tester.pumpWidget(host(n()));
    await tester.tap(find.byType(GestureDetector).last);
    await tester.pumpAndSettle();
    final nativeTaps = log.where((e) => e == 'tap').length;

    await reset(tester);
    await tester.pumpWidget(host(w()));
    await tester.tap(find.byType(app.GestureDetector));
    await tester.pumpAndSettle();
    final wrappedTaps = log.where((e) => e == 'tap').length;

    expect(nativeTaps, 1);
    expect(wrappedTaps, 1);
    expect(wrappedTaps, nativeTaps);
    await runBoth(tester, native: n, wrapped: w);
  });

  testWidgets('pulsación prolongada: nativo y envoltorio', (tester) async {
    Widget n() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => log.add('long'),
      child: const SizedBox.expand(),
    );
    Widget w() => app.GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: () => log.add('long'),
      child: const SizedBox.expand(),
    );

    await tester.pumpWidget(host(n()));
    await tester.longPress(find.byType(GestureDetector).last);
    await tester.pumpAndSettle();
    expect(log.contains('long'), isTrue, reason: 'nativo');

    await reset(tester);
    await tester.pumpWidget(host(w()));
    await tester.longPress(find.byType(app.GestureDetector));
    await tester.pumpAndSettle();
    expect(log.contains('long'), isTrue, reason: 'envoltorio');
  });

  testWidgets('arrastre horizontal: nativo y envoltorio', (tester) async {
    var nativeHits = 0;
    var wrappedHits = 0;

    await tester.pumpWidget(
      host(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (_) => nativeHits++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.drag(find.byType(GestureDetector).last, const Offset(-90, 0));
    await tester.pumpAndSettle();

    await reset(tester);
    await tester.pumpWidget(
      host(
        app.GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (_) => wrappedHits++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.drag(find.byType(app.GestureDetector), const Offset(-90, 0));
    await tester.pumpAndSettle();

    expect(nativeHits, greaterThan(0), reason: 'nativo');
    expect(wrappedHits, greaterThan(0), reason: 'envoltorio');
  });

  testWidgets('arrastre vertical: nativo y envoltorio', (tester) async {
    var nativeHits = 0;
    var wrappedHits = 0;

    await tester.pumpWidget(
      host(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (_) => nativeHits++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.drag(find.byType(GestureDetector).last, const Offset(0, -90));
    await tester.pumpAndSettle();

    await reset(tester);
    await tester.pumpWidget(
      host(
        app.GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (_) => wrappedHits++,
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.drag(find.byType(app.GestureDetector), const Offset(0, -90));
    await tester.pumpAndSettle();

    expect(nativeHits, greaterThan(0), reason: 'nativo');
    expect(wrappedHits, greaterThan(0), reason: 'envoltorio');
  });

  testWidgets('sin callbacks no dispara nada ni lanza excepción', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(app.GestureDetector(child: const SizedBox.expand())),
    );
    await tester.tap(find.byType(app.GestureDetector));
    await tester.pumpAndSettle();
    expect(log, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conserva el tamaño del hijo', (tester) async {
    await tester.pumpWidget(
      host(
        app.GestureDetector(
          onTap: () {},
          child: const ColoredBox(color: Color(0xFF00FF00)),
        ),
      ),
    );
    final size = tester.getSize(find.byType(app.GestureDetector));
    expect(size.width, 260);
    expect(size.height, 180);
  });
}
