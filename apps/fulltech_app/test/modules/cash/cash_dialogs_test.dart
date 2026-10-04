import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/modules/cash/cash_dialogs.dart';

void main() {
  group('parseDominicanAmount', () {
    test('accepts Dominican money formats', () {
      expect(parseDominicanAmount('0'), 0);
      expect(parseDominicanAmount('1200'), 1200);
      expect(parseDominicanAmount('1,200'), 1200);
      expect(parseDominicanAmount('1,200.00'), 1200);
      expect(parseDominicanAmount(r'RD$ 1,200.00'), 1200);
      expect(parseDominicanAmount('1200,50'), 1200.50);
    });

    test('rejects invalid or unsafe amounts', () {
      expect(parseDominicanAmount('abc'), isNull);
      expect(parseDominicanAmount('-1'), isNull);
      expect(parseDominicanAmount('NaN'), isNull);
      expect(parseDominicanAmount('Infinity'), isNull);
    });
  });

  group('resolveCashError (sin exponer detalles técnicos en UI)', () {
    test('quita el prefijo de clase y el sufijo (code:) de ApiException', () {
      final text = resolveCashError(
        const ApiException.detailed(
          message: 'El turno indicado no existe.',
          code: 404,
          type: ApiErrorType.notFound,
          displayCode: '404',
        ),
      );
      expect(text, 'El turno indicado no existe.');
    });

    test('quita el prefijo de Exception simple', () {
      expect(resolveCashError(Exception('Sin conexión')), 'Sin conexión');
    });

    test('ningún mensaje de cierre/cola expone términos técnicos', () {
      final messages = <String>[
        'Este turno ya fue cerrado.',
        'El turno indicado no existe.',
        'Necesitas actualizar Fullpos para cerrar el turno.',
        'No pudimos identificar el turno a cerrar. Actualiza Fullpos e inténtalo nuevamente.',
        'Una operación de caja pendiente no se aplicó porque ya no correspondía al turno actual. Revisa la caja.',
      ];
      for (final message in messages) {
        final text = resolveCashError(
          ApiException.detailed(message: message, displayCode: '409'),
        );
        expect(text, message);
        for (final forbidden in <String>[
          'code:',
          'apiexception',
          'sessionid',
          'shiftid',
          'replay',
          'obsolete',
          'obsoleta',
          'queue',
          'http',
          'uuid',
          'payload',
          'exception',
        ]) {
          expect(
            text.toLowerCase().contains(forbidden),
            isFalse,
            reason: 'no debe contener "$forbidden": $text',
          );
        }
      }
    });
  });

  group('CloseShiftDialog', () {
    testWidgets('Enter submits once and returns success', (tester) async {
      var calls = 0;
      CloseShiftResult? result;

      await tester.pumpWidget(
        _DialogHost(
          onResult: (value) => result = value,
          onCloseShift: (amount) async {
            calls += 1;
            expect(amount, 1200);
            return const PrintTicketResult(success: true, message: 'Impreso');
          },
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '1,200');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(result?.success, isTrue);
      expect(find.text('Cerrar turno'), findsNothing);
    });

    testWidgets('double Enter does not duplicate close request', (
      tester,
    ) async {
      var calls = 0;
      final completer = Completer<PrintTicketResult?>();

      await tester.pumpWidget(
        _DialogHost(
          onCloseShift: (_) {
            calls += 1;
            return completer.future;
          },
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextFormField));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(calls, 1);
      completer.complete(
        const PrintTicketResult(success: true, message: 'Impreso'),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('invalid amount keeps dialog open', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _DialogHost(
          onCloseShift: (_) async {
            calls += 1;
            return null;
          },
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar turno'));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.textContaining('Ingresa un monto válido'), findsOneWidget);
      expect(find.text('Cerrar turno'), findsWidgets);
    });

    testWidgets('API error keeps dialog open for retry', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _DialogHost(
          onCloseShift: (_) async {
            calls += 1;
            throw Exception('Sin conexión');
          },
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar turno'));
      await tester.pumpAndSettle();

      expect(calls, 1);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(find.text('Cerrar turno'), findsWidgets);
    });

    testWidgets('Esc cancels without submitting', (tester) async {
      var calls = 0;
      CloseShiftResult? result;

      await tester.pumpWidget(
        _DialogHost(
          onResult: (value) => result = value,
          onCloseShift: (_) async {
            calls += 1;
            return null;
          },
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(result, isNull);
      expect(find.text('Cerrar turno'), findsNothing);
    });

    testWidgets('diferencia anormal pide confirmación antes de cerrar', (
      tester,
    ) async {
      var calls = 0;

      await tester.pumpWidget(
        _DialogHost(
          onCloseShift: (_) async {
            calls += 1;
            return const PrintTicketResult(success: true, message: 'Impreso');
          },
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();
      // Esperado = 1,200; contado = 50,000 → diferencia anormal.
      await tester.enterText(find.byType(TextFormField), '50,000');
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar turno'));
      await tester.pumpAndSettle();

      expect(find.text('Diferencia de efectivo elevada'), findsOneWidget);
      expect(calls, 0);

      // "Revisar" cancela la confirmación y no llama al backend.
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();
      expect(calls, 0);

      // Volver a confirmar ejecuta el cierre UNA sola vez.
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar turno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    });

    testWidgets('diferencia pequeña NO pide confirmación', (tester) async {
      var calls = 0;

      await tester.pumpWidget(
        _DialogHost(
          onCloseShift: (_) async {
            calls += 1;
            return const PrintTicketResult(success: true, message: 'Impreso');
          },
        ),
      );

      await tester.tap(find.text('Abrir cierre'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '1,100');
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar turno'));
      await tester.pumpAndSettle();

      expect(find.text('Diferencia de efectivo elevada'), findsNothing);
      expect(calls, 1);
    });
  });
}

class _DialogHost extends StatelessWidget {
  const _DialogHost({required this.onCloseShift, this.onResult});

  final Future<PrintTicketResult?> Function(double amount) onCloseShift;
  final ValueChanged<CloseShiftResult?>? onResult;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await showCloseShiftDialog(
                    context,
                    expectedCash: 1200,
                    onCloseShift: onCloseShift,
                  );
                  onResult?.call(result);
                },
                child: const Text('Abrir cierre'),
              ),
            );
          },
        ),
      ),
    );
  }
}
