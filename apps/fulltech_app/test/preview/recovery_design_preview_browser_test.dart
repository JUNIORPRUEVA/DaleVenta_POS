@TestOn('browser')
library;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'recovery_design_preview.dart';

void main() {
  testWidgets('gallery exposes every current recovery state with synthetic data', (tester) async {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(fileInput: 'APP_ENV=uat\nAPI_BASE_URL=http://127.0.0.1:9');
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const RecoveryDesignPreview());
    await tester.pumpAndSettle();
    expect(find.text('Verificar ahora'), findsOneWidget);
    await tester.tap(find.text('Verificar ahora'));
    await tester.pumpAndSettle();
    expect(find.text('Resultado de la verificación'), findsOneWidget);
    expect(find.textContaining('No repitas'), findsWidgets);
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();
    for (final scenario in RecoveryPreviewCase.values) {
      await tester.tap(find.byType(DropdownButton<RecoveryPreviewCase>));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(scenario.label).last);
      await tester.tap(find.text(scenario.label).last);
      await tester.pumpAndSettle();
      expect(find.text(scenario.help), findsOneWidget);
      if (scenario == RecoveryPreviewCase.cashier) {
        expect(find.text('Acceso de administrador'), findsOneWidget);
        expect(find.text('Operaciones guardadas'), findsNothing);
      } else if (scenario == RecoveryPreviewCase.empty || scenario == RecoveryPreviewCase.archive) {
        expect(find.text('Todo en orden'), findsOneWidget);
      } else {
        expect(find.text('Pendientes'), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: scenario.name);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
