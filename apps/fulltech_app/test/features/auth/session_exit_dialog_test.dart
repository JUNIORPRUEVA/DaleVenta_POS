import 'package:daleventa_pos/features/auth/presentation/session_exit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets('lock and logout are distinct choices at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SessionExitAction? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showSessionExitDialog(context);
                },
                child: const Text('Salir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ya está autorizado'), findsOneWidget);
      await tester.tap(find.text('Bloquear equipo'));
      await tester.pumpAndSettle();
      expect(selected, SessionExitAction.lock);
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(selected, SessionExitAction.logout);
      await tester.tap(find.text('Salir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(selected, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
