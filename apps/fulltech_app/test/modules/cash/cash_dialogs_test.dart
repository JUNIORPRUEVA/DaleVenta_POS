import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulltech_app/core/printing/unified_ticket_printer.dart';
import 'package:fulltech_app/modules/cash/cash_dialogs.dart';

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
