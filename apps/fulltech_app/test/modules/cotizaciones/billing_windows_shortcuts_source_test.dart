import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File(
      'lib/modules/cotizaciones/cotizaciones_screen.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');
  });

  test('Windows shortcuts are scoped to billing and Windows only', () {
    expect(source, contains('bool get _billingShortcutsEnabled'));
    expect(source, contains('defaultTargetPlatform == TargetPlatform.windows'));
    expect(source, contains('if (kIsWeb) return false'));
    expect(source, contains('CallbackShortcuts'));
    expect(source, contains('_windowsBillingShortcutBindings'));
    expect(source, contains('buildWindowsBillingShortcutScope'));
  });

  test('el scope usa FocusScope: un unfocus no apaga todos los atajos', () {
    final block = _blockFrom(
      source,
      'Widget buildWindowsBillingShortcutScope(',
    );
    expect(block, contains('CallbackShortcuts'));
    expect(block, contains('FocusScope(autofocus: true'));
    expect(block, isNot(contains('Focus(autofocus: true')));
  });

  test('los F1..F6 no se bloquean por foco en un campo de texto', () {
    final block = _blockFrom(
      source,
      'Map<ShortcutActivator, VoidCallback> _windowsBillingShortcutBindings()',
    );
    expect(block, contains('_canRunBillingFunctionKeyShortcut'));
    expect(block, isNot(contains('_canRunBillingShortcut')));
  });

  test('essential shortcuts reuse existing billing handlers', () {
    expect(source, contains('LogicalKeyboardKey.f1'));
    expect(source, contains('_openCheckoutDialogFromShortcut'));
    expect(source, contains('await _openCheckoutDialog()'));
    expect(source, contains('_shortcutCheckoutOpening'));
    expect(source, contains('if (_shortcutCheckoutOpening) return'));
    expect(source, contains('LogicalKeyboardKey.f2'));
    expect(source, contains('_requestDesktopSearchFocus'));
    expect(source, contains('LogicalKeyboardKey.f3'));
    expect(source, contains('_openClientDialog'));
    expect(source, contains('LogicalKeyboardKey.f4'));
    expect(source, contains('_openExternalItemDialog'));
    expect(source, contains('LogicalKeyboardKey.f5'));
    expect(source, contains('_createNewDesktopTicket'));
    expect(source, contains('LogicalKeyboardKey.f6'));
    expect(source, contains('_openRecentSalesPanel'));
  });

  test('destructive quantity shortcuts require selected cart line', () {
    expect(source, contains('_validDesktopSelectedCartIndex'));
    expect(source, contains('_removeSelectedCartLineFromShortcut'));
    expect(source, contains('_adjustSelectedCartLineFromShortcut'));
    expect(source, contains('LogicalKeyboardKey.delete'));
    expect(source, contains('LogicalKeyboardKey.numpadAdd'));
    expect(source, contains('LogicalKeyboardKey.numpadSubtract'));
  });

  test('unsafe or future shortcuts are not registered in first phase', () {
    expect(source, isNot(contains('LogicalKeyboardKey.f7')));
    expect(source, isNot(contains('LogicalKeyboardKey.f8')));
    expect(source, isNot(contains('LogicalKeyboardKey.f10')));
    expect(source, isNot(contains('control: true')));
  });
}

/// Devuelve el bloque de código que arranca en [marker], delimitado por el
/// emparejamiento de llaves de su propio cuerpo.
String _blockFrom(String source, String marker) {
  final start = source.indexOf(marker);
  expect(start, greaterThanOrEqualTo(0), reason: 'no se encontró: $marker');
  // El cuerpo arranca en el `{` de `) {` (la lista de parámetros nombrados usa
  // sus propias llaves, así que no sirve la primera llave a secas).
  final body = source.indexOf(') {', start);
  expect(body, greaterThanOrEqualTo(0), reason: 'sin cuerpo en: $marker');
  final open = body + 2;
  var depth = 0;
  for (var index = open; index < source.length; index++) {
    final String char = source[index];
    if (char == '{') {
      depth++;
    } else if (char == '}') {
      depth--;
      if (depth == 0) return source.substring(start, index + 1);
    }
  }
  return source.substring(start);
}
