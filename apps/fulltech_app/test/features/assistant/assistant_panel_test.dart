import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/features/assistant/presentation/assistant_panel.dart';
import 'package:daleventa_pos/features/assistant/presentation/widgets/assistant_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpHost(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        companySettingsProvider.overrideWith(
          (ref) async => CompanySettings.empty(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => AssistantPanel.open(context),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPanel(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abre con las cuatro acciones y cierra', (tester) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    expect(find.text('Asistente FullPOS'), findsOneWidget);
    expect(find.text('Escribir vía WhatsApp'), findsOneWidget);
    expect(find.text('Reportar avería'), findsOneWidget);
    expect(find.text('Sugerir mejora'), findsOneWidget);
    expect(find.text('Cursos sobre el programa'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Escribir vía WhatsApp'), findsNothing);
  });

  testWidgets('avería: valida descripción obligatoria sin romper el panel', (
    tester,
  ) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    await tester.tap(find.text('Reportar avería'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Descripción del problema'), findsOneWidget);

    await tester.tap(find.text('Enviar por WhatsApp'));
    await tester.pumpAndSettle();

    expect(
      find.text('Describe el problema para poder ayudarte.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('avería: la vista previa usa el constructor de mensajes', (
    tester,
  ) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    await tester.tap(find.text('Reportar avería'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'Al cobrar sale error y no guarda la venta.',
    );
    await tester.tap(find.text('Revisar mensaje'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tipo: Avería'), findsOneWidget);
    expect(
      find.textContaining('Descripción: Al cobrar sale error'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sugerencia: valida título y descripción', (tester) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    await tester.tap(find.text('Sugerir mejora'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar por WhatsApp'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe un título breve.'), findsOneWidget);
    expect(find.text('Describe tu idea.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cursos: despliega un tema verificado y ofrece soporte', (
    tester,
  ) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    await tester.tap(find.text('Cursos sobre el programa'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Caja y turnos'));
    await tester.tap(find.text('Caja y turnos'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Registra entradas y salidas'), findsOneWidget);
    expect(find.text('Contactar soporte'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cursos: el buscador filtra el contenido real', (tester) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    await tester.tap(find.text('Cursos sobre el programa'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'impresora');
    await tester.pumpAndSettle();

    expect(find.text('Impresora y tickets'), findsOneWidget);
    expect(find.text('Registrar una venta'), findsNothing);
    expect(find.textContaining('1 tema para'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No encontramos esa guía'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('el buscador del inicio abre cursos con la consulta', (
    tester,
  ) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    await tester.enterText(
      find.byType(TextField).first,
      'usuarios y permisos',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Cursos sobre el programa'), findsOneWidget);
    expect(find.text('Usuarios y permisos'), findsOneWidget);
    expect(find.text('Registrar una venta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda en 632x340 (1264x681 al 200 %)', (tester) async {
    await _pumpHost(tester, const Size(632, 340));
    await _openPanel(tester);

    expect(find.text('Escribir vía WhatsApp'), findsOneWidget);
    await tester.ensureVisible(find.text('Reportar avería'));
    await tester.tap(find.text('Reportar avería'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Descripción del problema'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no desborda en móvil 390x780', (tester) async {
    await _pumpHost(tester, const Size(390, 780));
    await _openPanel(tester);

    expect(find.text('Reportar avería'), findsOneWidget);
    await tester.tap(find.text('Sugerir mejora'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Título breve'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('se abre pegado al borde derecho y a altura completa', (
    tester,
  ) async {
    await _pumpHost(tester, const Size(1280, 800));
    await _openPanel(tester);

    final rect = tester.getRect(find.byKey(const Key('assistant-panel-root')));
    expect(rect.right, closeTo(1280, 0.5));
    expect(rect.height, closeTo(800, 0.5));
    expect(rect.width, inInclusiveRange(480, 620));
    expect(tester.takeException(), isNull);
  });

  testWidgets('en móvil ocupa el ancho completo', (tester) async {
    await _pumpHost(tester, const Size(390, 780));
    await _openPanel(tester);

    final rect = tester.getRect(find.byKey(const Key('assistant-panel-root')));
    expect(rect.right, closeTo(390, 0.5));
    expect(rect.width, closeTo(390, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('FAB circular abre el asistente', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          companySettingsProvider.overrideWith(
            (ref) async => CompanySettings.empty(),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: Center(child: AssistantFab())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(AssistantFab)), const Size(52, 52));

    await tester.tap(find.byType(AssistantFab));
    await tester.pumpAndSettle();

    expect(find.text('Asistente FullPOS'), findsOneWidget);
    expect(find.text('Escribir vía WhatsApp'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
