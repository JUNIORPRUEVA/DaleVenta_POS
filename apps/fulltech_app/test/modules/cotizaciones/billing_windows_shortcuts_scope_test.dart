import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión auditada (pantalla de cobro en Windows):
///
/// `CallbackShortcuts` sólo entrega teclas mientras el foco primario es
/// descendiente de su nodo. La pantalla envolvia el contenido con
/// `Focus(autofocus: true)`, así que cualquier `unfocus()` (Escape al salir de
/// un campo de texto, cierre del diálogo de nota, etc.) mandaba el foco al
/// scope de la RUTA — ancestro del `CallbackShortcuts` — y **ningún** atajo se
/// entregaba más: usar una tecla rápida desactivaba todas las demás.
///
/// Se verifica el widget real de producción: `buildWindowsBillingShortcutScope`.
void main() {
  group('buildWindowsBillingShortcutScope', () {
    testWidgets('entrega los atajos con el scope enfocado', (tester) async {
      await tester.pumpWidget(const _ShortcutHost());
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pump();

      expect(_state(tester).f1, 1);
    });

    testWidgets(
      'sigue entregando atajos tras unfocus() (Escape fuera de un campo)',
      (tester) async {
        await tester.pumpWidget(const _ShortcutHost());
        await tester.pumpAndSettle();

        // El usuario busca (F2) y luego sale del campo con Escape: eso es
        // exactamente lo que hace `_handleBillingShortcutEscape`.
        await tester.tap(find.byType(TextField));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.context?.widget is EditableText,
          isFalse,
          reason: 'Escape debe sacar el foco del campo de texto',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.f4);
        await tester.pump();

        expect(
          _state(tester).f4,
          1,
          reason: 'tras salir del campo, los demás atajos deben seguir vivos',
        );
      },
    );

    testWidgets('sigue entregando atajos tras cerrar un diálogo', (
      tester,
    ) async {
      await tester.pumpWidget(const _ShortcutHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      expect(find.text('cerrar'), findsOneWidget);

      await tester.tap(find.text('cerrar'));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pump();

      expect(_state(tester).f1, 1);
    });

    testWidgets('entrega atajos aunque el foco esté en un campo de texto', (
      tester,
    ) async {
      await tester.pumpWidget(const _ShortcutHost());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(TextField));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pump();

      expect(
        _state(tester).f1,
        1,
        reason: 'la entrega no depende del foco en el campo: la regla es el gate',
      );
    });
  });

  group('canRunBillingFunctionKeyShortcut', () {
    test('los F1..F6 no se desactivan por foco en un campo de texto', () {
      expect(
        canRunBillingFunctionKeyShortcut(
          shortcutsEnabled: true,
          textInputFocused: true,
        ),
        isTrue,
      );
      expect(
        canRunBillingFunctionKeyShortcut(
          shortcutsEnabled: true,
          textInputFocused: false,
        ),
        isTrue,
      );
    });

    test('los F1..F6 siguen deshabilitados fuera de Windows', () {
      expect(
        canRunBillingFunctionKeyShortcut(
          shortcutsEnabled: false,
          textInputFocused: false,
        ),
        isFalse,
      );
    });
  });
}

_ShortcutHostState _state(WidgetTester tester) =>
    tester.state<_ShortcutHostState>(find.byType(_ShortcutHost));

class _ShortcutHost extends StatefulWidget {
  const _ShortcutHost();

  @override
  State<_ShortcutHost> createState() => _ShortcutHostState();
}

class _ShortcutHostState extends State<_ShortcutHost> {
  int f1 = 0;
  int f4 = 0;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: buildWindowsBillingShortcutScope(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.f1): () =>
              setState(() => f1++),
          const SingleActivator(LogicalKeyboardKey.f4): () =>
              setState(() => f4++),
          const SingleActivator(LogicalKeyboardKey.escape): () {
            // Réplica del comportamiento real: Escape sale del campo de texto.
            FocusManager.instance.primaryFocus?.unfocus();
          },
        },
        child: Scaffold(
          body: Column(
            children: <Widget>[
              const TextField(),
              Text('f1=$f1 f4=$f4'),
              Builder(
                builder: (BuildContext inner) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: inner,
                    builder: (BuildContext dialogContext) => AlertDialog(
                      content: const TextField(autofocus: true),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('cerrar'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
