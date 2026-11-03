import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/utils/app_feedback.dart';

/// Los avisos de acciones de la app son pequeños, flotan arriba a la derecha y
/// nunca son una barra inferior ni un modal.
void main() {
  tearDown(AppFeedback.clearToasts);

  // Contexto del botón: es el que las pantallas reales usan para pedir el aviso.
  late BuildContext captured;

  Widget harness() {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Pantalla')),
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => captured = context,
              child: const Text('mostrar'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> show(
    WidgetTester tester, {
    required String title,
    String body = '',
    AppFeedbackKind kind = AppFeedbackKind.success,
    String? dedupeKey,
    Duration? duration,
  }) async {
    await tester.tap(find.text('mostrar'));
    await tester.pump();
    AppFeedback.showToast(
      captured,
      title: title,
      body: body.isEmpty ? 'Texto del aviso.' : body,
      kind: kind,
      dedupeKey: dedupeKey,
      duration: duration,
    );
    await tester.pump();
  }

  testWidgets('aparece arriba a la derecha y no es una barra inferior', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await show(
      tester,
      title: 'Expediente guardado',
      body: 'Tu solicitud quedó registrada para revisión interna. Puedes '
          'continuar cuando corresponda.',
    );

    expect(find.text('Expediente guardado'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(MaterialBanner), findsNothing);

    final box = tester.getRect(
      find.byKey(const ValueKey('app_feedback_toast_Expediente guardado')),
    );
    // Esquina superior derecha: mitad derecha de la pantalla y zona alta.
    expect(box.left, greaterThan(1200 / 2));
    expect(box.top, lessThan(200));
    expect(box.right, lessThanOrEqualTo(1200));

    // Los avisos de éxito desaparecen solos.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Expediente guardado'), findsNothing);
  });

  testWidgets('el mismo aviso repetido no se duplica', (tester) async {
    await tester.pumpWidget(harness());
    await show(
      tester,
      title: 'Borrador guardado',
      dedupeKey: 'draft',
      duration: const Duration(seconds: 4),
    );
    await show(
      tester,
      title: 'Borrador guardado',
      dedupeKey: 'draft',
      duration: const Duration(seconds: 4),
    );

    expect(find.text('Borrador guardado'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Borrador guardado'), findsNothing);
  });

  testWidgets('varios avisos se apilan con un límite', (tester) async {
    await tester.pumpWidget(harness());
    for (final title in <String>['Uno', 'Dos', 'Tres', 'Cuatro']) {
      await show(
        tester,
        title: title,
        dedupeKey: title,
        duration: const Duration(seconds: 4),
      );
    }

    // El límite evita tapar la pantalla: el más antiguo deja de mostrarse.
    expect(find.text('Uno'), findsNothing);
    expect(find.text('Dos'), findsOneWidget);
    expect(find.text('Tres'), findsOneWidget);
    expect(find.text('Cuatro'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('el error permanece más tiempo y se puede cerrar a mano', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await show(
      tester,
      title: 'No se pudieron guardar los datos',
      body: 'Se perdió la conexión.',
      kind: AppFeedbackKind.error,
    );

    // A los 5 s un error sigue visible (un éxito ya habría desaparecido).
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('No se pudieron guardar los datos'), findsOneWidget);

    await tester.tap(find.byTooltip('Cerrar aviso'));
    await tester.pump();
    expect(find.text('No se pudieron guardar los datos'), findsNothing);
  });

  testWidgets('un texto largo se adapta sin desbordar en móvil', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await show(
      tester,
      title: 'Expediente guardado',
      body: 'Tu solicitud quedó registrada para revisión interna con la '
          'versión vigente del consentimiento. Todavía no se ha presentado '
          'oficialmente ante la DGII y puedes continuar cuando corresponda.',
      dedupeKey: 'long',
    );

    expect(tester.takeException(), isNull);
    final box = tester.getRect(
      find.byKey(const ValueKey('app_feedback_toast_Expediente guardado')),
    );
    // Ocupa el ancho disponible del móvil, sin salirse de los bordes.
    expect(box.left, greaterThan(0));
    expect(box.right, lessThanOrEqualTo(390));
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('sin overlay no bloquea la pantalla', (tester) async {
    // Un contexto sin Overlay (fuera de MaterialApp) no debe lanzar ni abrir un
    // diálogo modal: simplemente no muestra el aviso.
    late BuildContext plainContext;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            plainContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    AppFeedback.showToast(plainContext, title: 'Sin overlay', body: 'No debe '
        'romper nada.');
    await tester.pump();
    expect(find.text('Sin overlay'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

