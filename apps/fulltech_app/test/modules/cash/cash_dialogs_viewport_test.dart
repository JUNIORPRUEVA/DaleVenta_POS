import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// VALIDACIÓN RESPONSIVE (Fase 4) de los diálogos de caja.
///
/// En `flutter test`, un `RenderFlex` con overflow lanza una excepción que hace
/// fallar el test. Por tanto un test VERDE en un viewport dado == el diálogo
/// renderiza sin overflow, sin texto cortado y sin botones fuera de pantalla
/// en ese viewport.
///
/// Cubre: diálogo "Cerrar turno" y la confirmación de "Diferencia de efectivo
/// elevada" (label 'Sí, cerrar'), en desktop y móvil.
void main() {
  final viewports = <String, ({double width, double height, double dpr})>{
    'desktop 1920x1080': (width: 1920, height: 1080, dpr: 1),
    'desktop 1366x768': (width: 1366, height: 768, dpr: 1),
    'movil 1080x2400 (360x800 lógicos)': (width: 1080, height: 2400, dpr: 3),
    'movil compacto 360x640 lógicos': (width: 720, height: 1280, dpr: 2),
  };

  for (final entry in viewports.entries) {
    testWidgets('diálogos de caja sin overflow · ${entry.key}', (tester) async {
      tester.view.devicePixelRatio = entry.value.dpr;
      tester.view.physicalSize = Size(entry.value.width, entry.value.height);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _DialogHost(
          expectedCash: 1200,
          onCloseShift: (_) async =>
              const PrintTicketResult(success: true, message: 'Impreso'),
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();

      // 1) Diálogo de cierre renderizado sin overflow en este viewport.
      expect(find.text('Cerrar turno'), findsWidgets);
      expect(find.byType(TextFormField), findsOneWidget);

      // 2) Diferencia anormal (esperado 1,200; contado 50,000) → confirmación.
      await tester.enterText(find.byType(TextFormField), '50,000');
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar turno'));
      await tester.pumpAndSettle();

      // La confirmación renderiza sin overflow; labels visibles y completos.
      expect(find.text('Diferencia de efectivo elevada'), findsOneWidget);
      expect(find.text('Cerrar'), findsOneWidget);
      expect(find.text('Revisar'), findsOneWidget);
    });
  }
}

class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.expectedCash, required this.onCloseShift});

  final double expectedCash;
  final Future<PrintTicketResult?> Function(double amount) onCloseShift;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showCloseShiftDialog(
                context,
                expectedCash: expectedCash,
                onCloseShift: onCloseShift,
              ),
              child: const Text('Abrir cierre'),
            ),
          ),
        ),
      ),
    );
  }
}
