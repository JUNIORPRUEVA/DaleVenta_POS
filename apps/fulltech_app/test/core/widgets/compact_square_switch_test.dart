import 'dart:ui' as ui;

import 'package:daleventa_pos/core/widgets/compact_square_switch.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cambia por toque y conserva un área de interacción accesible', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Align(
              alignment: Alignment.topLeft,
              child: CompactSquareSwitch(
                value: value,
                label: 'Módulo de prueba',
                onChanged: (next) => setState(() => value = next),
              ),
            ),
          ),
        ),
      ),
    );
    final control = find.byType(CompactSquareSwitch);
    expect(tester.getSize(control).width, greaterThanOrEqualTo(40));
    expect(tester.getSize(control).height, greaterThanOrEqualTo(40));
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(
      tester.getSemantics(control).getSemanticsData().flagsCollection.isToggled,
      ui.Tristate.isTrue,
    );
    semantics.dispose();
  });

  testWidgets('el teclado permite activar y desactivar sin ratón', (
    tester,
  ) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => CompactSquareSwitch(
              value: value,
              label: 'Módulo de prueba',
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(value, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(value, isFalse);
  });

  testWidgets('sin permiso queda deshabilitado también para accesibilidad', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CompactSquareSwitch(
            value: true,
            onChanged: null,
            label: 'Módulo protegido',
          ),
        ),
      ),
    );
    final control = find.byType(CompactSquareSwitch);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(tester.widget<CompactSquareSwitch>(control).value, isTrue);
    expect(
      tester.getSemantics(control).getSemanticsData().flagsCollection.isEnabled,
      ui.Tristate.isFalse,
    );
    semantics.dispose();
  });
}
