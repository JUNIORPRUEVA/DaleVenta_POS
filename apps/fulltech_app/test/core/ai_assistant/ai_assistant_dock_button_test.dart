import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_dock_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El botón del asistente vive en el `Stack` del `builder` de `MaterialApp`,
/// **por encima del Navigator**: no tiene `Overlay` ancestro.
///
/// Declaraba `Tooltip`, y `RawTooltip` exige uno: lanzaba
/// `No Overlay widget found` en cada reconstrucción y el manejador global lo
/// convertía en un aviso de error encima de la pantalla de ventas.
void main() {
  Future<void> pumpLikeProduction(
    WidgetTester tester,
    VoidCallback onPressed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            Positioned(
              left: 14,
              bottom: 14,
              child: AiAssistantDockButton(onPressed: onPressed),
            ),
          ],
        ),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('montado como en producción no lanza "No Overlay widget found"', (
    tester,
  ) async {
    await pumpLikeProduction(tester, () {});

    expect(
      find.byType(Tooltip),
      findsNothing,
      reason: 'Sin Overlay ancestro no puede haber Tooltip.',
    );
    final error = tester.takeException()?.toString() ?? '';
    expect(
      error,
      isNot(contains('No Overlay widget found')),
      reason: 'Era el error que aparecía como aviso al cliente.',
    );
  });

  testWidgets('sigue siendo accesible y abre el asistente', (tester) async {
    var taps = 0;
    await pumpLikeProduction(tester, () => taps += 1);

    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('Abrir el asistente de IA'), findsOneWidget);
    semantics.dispose();

    await tester.tap(find.byType(AiAssistantDockButton));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('cuando el panel está abierto anuncia que se puede cerrar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Stack(
          children: [
            if (child != null) child,
            Positioned(
              left: 14,
              bottom: 14,
              child: AiAssistantDockButton(onPressed: () {}, isActive: true),
            ),
          ],
        ),
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pumpAndSettle();

    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(
      find.bySemanticsLabel(
        RegExp('Cerrar el asistente', caseSensitive: false),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
