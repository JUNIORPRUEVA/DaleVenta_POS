import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_fiscal_data_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SettingsRepository implements CompanySettingsRepository {
  CompanySettings value = CompanySettings.empty().copyWith(
    companyName: 'Empresa de prueba',
    rnc: '131000001',
    address: 'Calle de prueba',
    ecfContactEmail: 'fiscal@example.test',
  );
  bool failSave = false;
  int writes = 0;

  @override
  Future<CompanySettings> getSettings() async => value;

  @override
  Future<bool> saveSettingsOrQueue(CompanySettings settings) async {
    if (failSave) throw StateError('Error simulado de guardado');
    writes++;
    value = settings;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  tearDown(AppFeedback.clearToasts);

  Future<void> pump(WidgetTester tester, _SettingsRepository repository,
      VoidCallback onSaved) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [companySettingsRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: Scaffold(body: EcfFiscalDataContent(onSaved: onSaved))),
    ));
    await tester.pumpAndSettle();
  }

  for (final failSave in [false, true]) {
    testWidgets('corregir RNC conserva el borrador si falla: $failSave', (tester) async {
      final repository = _SettingsRepository()..failSave = failSave;
      final original = repository.value;
      var saved = 0;
      await pump(tester, repository, () => saved++);
      final field = find.widgetWithText(TextField, original.rnc);
      final controller = tester.widget<TextField>(field).controller!;
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, '131000002');
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Guardar datos');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(controller.text, '131000002');
      expect(saved, failSave ? 0 : 1);
      expect(repository.writes, failSave ? 0 : 1);
      expect(
        find.byKey(const ValueKey('app_feedback_toast_No se pudieron guardar los datos')),
        failSave ? findsOneWidget : findsNothing,
      );
      expect(repository.value.rnc, failSave ? original.rnc : '131000002');
      expect(repository.value.companyName, original.companyName);
      expect(repository.value.ecfContactEmail, original.ecfContactEmail);
      expect(tester.takeException(), isNull);
    });
  }
}
