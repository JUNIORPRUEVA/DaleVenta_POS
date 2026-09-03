import 'dart:io';

import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mobile quick sale visible submit finalizes focus without keyboard Done',
    (tester) async {
      bool? result;
      var submittedFromKeyboard = false;
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: TextField(
                        focusNode: focusNode,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submittedFromKeyboard = true,
                      ),
                      actions: [
                        FilledButton(
                          onPressed: () =>
                              submitMobileExternalItemDialog(dialogContext),
                          child: const Text('Agregar'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Abrir venta rapida'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir venta rapida'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Servicio puntual');
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(submittedFromKeyboard, isFalse);
      expect(focusNode.hasFocus, isFalse);
    },
  );

  test('mobile quick sale Done and visible submit share the finalizing path', () {
    final source = File(
      'lib/modules/cotizaciones/cotizaciones_screen.dart',
    ).readAsStringSync();
    final normalizedSource = source.replaceAll('\r\n', '\n');

    expect(
      normalizedSource,
      contains(
        'onSubmitted: (_) =>\n'
        '                          submitMobileExternalItemDialog(dialogContext)',
      ),
    );
    expect(
      normalizedSource,
      contains(
        'onPressed: () =>\n'
        '                              submitMobileExternalItemDialog(dialogContext)',
      ),
    );
  });
}
