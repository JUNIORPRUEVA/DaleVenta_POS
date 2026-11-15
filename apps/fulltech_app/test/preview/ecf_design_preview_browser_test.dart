@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ecf_design_preview.dart';

@JS('fullposCompleteWebStartup')
external set _startupComplete(JSFunction? callback);

void main() {
  testWidgets('el primer frame del preview libera la cubierta de carga web', (
    tester,
  ) async {
    dotenv.testLoad(fileInput: 'APP_ENV=uat\nAPI_BASE_URL=http://127.0.0.1:9');
    var completions = 0;
    _startupComplete = (() {
      completions++;
    }).toJS;
    addTearDown(() {
      _startupComplete = null;
    });

    await tester.pumpWidget(const EcfDesignPreview());
    await tester.pumpAndSettle();
    expect(find.text('Vista previa · datos ficticios'), findsOneWidget);
    expect(completions, 1);

    await tester.tap(find.text('2. Entrada al módulo'));
    await tester.pumpAndSettle();
    expect(find.text('Comenzar'), findsOneWidget);
    expect(completions, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
