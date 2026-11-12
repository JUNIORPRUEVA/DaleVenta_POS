import 'dart:async';

import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/cotizaciones/presentation/widgets/sales_client_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const client = ClienteModel(
  id: '1',
  ownerId: 'test',
  nombre: 'Cliente de prueba',
  telefono: '8095550100',
);

Future<void> showSelector(
  WidgetTester tester,
  Future<List<ClienteModel>> Function(String) search, {
  VoidCallback? onCreate,
}) async {
  ClienteModel? selected;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, update) => Align(
            alignment: Alignment.topRight,
            child: SizedBox(
              width: 420,
              child: SalesClientSelector(
                name: selected?.nombre ?? '',
                phone: selected?.telefono ?? '',
                hasClient: selected != null,
                search: search,
                onSelected: (value) => update(() => selected = value),
                onClear: () => update(() => selected = null),
                onCreate: onCreate ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un solo campo busca en el selector y el icono abre creación', (
    tester,
  ) async {
    var createCalls = 0;
    await showSelector(
      tester,
      (_) async => [client],
      onCreate: () => createCalls++,
    );
    final original = tester.getRect(find.byType(TextField));
    await tester.tap(find.byTooltip('Mostrar clientes'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.getRect(find.byType(TextField)), original);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.decoration!.focusedBorder, InputBorder.none);
    expect(
      tester.widget<ImageIcon>(find.byType(ImageIcon)).image,
      const AssetImage(SalesClientSelector.createIconAsset),
    );
    await tester.tap(find.byTooltip('Crear cliente'));
    await tester.pumpAndSettle();
    expect(createCalls, 1);
    expect(find.text(client.nombre), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busca, selecciona y quita sin abrir una ruta lateral', (
    tester,
  ) async {
    final queries = <String>[];
    await showSelector(tester, (query) async {
      queries.add(query);
      return query.isEmpty || client.telefono.contains(query) ? [client] : [];
    });
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '809555');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(queries, ['', '809555']);
    await tester.tap(find.text(client.nombre));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(client.nombre), findsOneWidget);
    await tester.tap(find.byTooltip('Quitar cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Seleccionar cliente'), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'inexistente');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron clientes'), findsOneWidget);
    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron clientes'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('una respuesta antigua no reemplaza la búsqueda nueva', (
    tester,
  ) async {
    final old = Completer<List<ClienteModel>>();
    final current = Completer<List<ClienteModel>>();
    await showSelector(
      tester,
      (query) => query == 'anterior'
          ? old.future
          : query == 'actual'
          ? current.future
          : Future.value([]),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'anterior');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), 'actual');
    await tester.pump(const Duration(milliseconds: 250));
    current.complete([client]);
    await tester.pumpAndSettle();
    old.complete([]);
    await tester.pumpAndSettle();
    expect(find.text(client.nombre), findsOneWidget);
    expect(find.text('No se encontraron clientes'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'permite reintentar cuando falla la búsqueda y cerrar mientras carga',
    (tester) async {
      var fail = true;
      final pending = Completer<List<ClienteModel>>();
      await showSelector(tester, (query) async {
        if (query == 'pendiente') return pending.future;
        if (fail) throw StateError('error simulado');
        return [client];
      });
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.text('No se pudieron cargar los clientes.'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text(client.nombre), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'pendiente');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tapAt(const Offset(20, 400));
      await tester.pumpAndSettle();
      pending.complete([client]);
      await tester.pumpAndSettle();
      expect(find.text(client.nombre), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
