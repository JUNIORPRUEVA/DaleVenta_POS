import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_config_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Interruptor de la excepción fiscal «vender sin comprobante electrónico».
///
/// Lo que se prueba es lo que puede salir mal de verdad: que el aviso completo
/// llegue al usuario antes de habilitar, que cancelar no guarde nada, que el
/// valor mostrado sea el del servidor y no una suposición local, y que sin
/// permiso no se pueda cambiar.
class _FakeRepository extends EcfRepository {
  _FakeRepository() : super(Dio());

  Object? failure;
  int calls = 0;
  bool? lastAllow;

  @override
  Future<void> updateAllowSalesWithoutEcf({required bool allow}) async {
    calls++;
    lastAllow = allow;
    if (failure != null) throw failure!;
  }
}

const _warning =
    'Advertencia fiscal: esta opción permite registrar ventas sin emitir un '
    'comprobante fiscal electrónico. Estos documentos no sustituyen los e-CF '
    'exigidos por la DGII. La empresa es responsable de utilizar esta función '
    'únicamente en operaciones permitidas por la normativa vigente. FullPOS '
    'conservará un registro de estas operaciones para control y auditoría.';

EcfCapabilities _capabilities({bool allow = false, String warning = _warning}) {
  return EcfCapabilities(
    enabled: true,
    environment: 'SANDBOX',
    certificationStatus: 'NOT_STARTED',
    productionEnabled: false,
    allowedTypes: const ['E31', 'E32', 'E34'],
    emissionPathAvailable: false,
    documentTypes: const [],
    allowSalesWithoutEcf: allow,
    salesWithoutEcfWarning: warning,
  );
}

Future<_FakeRepository> _pump(
  WidgetTester tester, {
  bool allow = false,
  bool canManage = true,
  Object? failure,
  double width = 800,
  bool embedded = false,
}) async {
  final repository = _FakeRepository()..failure = failure;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ecfRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: EcfSalesWithoutDocumentSection(
                  capabilities: _capabilities(allow: allow),
                  canManage: canManage,
                  embedded: embedded,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets(
    'embebida no crea una superficie propia: no anida tarjetas en Empresa',
    (tester) async {
      await _pump(tester, embedded: true);

      // El panel propio es el contenedor blanco con borde. Embebida no debe
      // existir, porque el panel fiscal de Empresa ya es la superficie.
      expect(
        find.descendant(
          of: find.byType(EcfSalesWithoutDocumentSection),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.decoration is BoxDecoration &&
                (widget.decoration! as BoxDecoration).color == Colors.white,
          ),
        ),
        findsNothing,
      );
      // El contenido sigue completo: título, explicación y switch.
      expect(find.text('Ventas sin comprobante electrónico'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    },
  );

  testWidgets('encendida: el aviso del servidor se muestra una sola vez', (
    tester,
  ) async {
    await _pump(tester, allow: true);

    // Un único párrafo explicativo: el del servidor. El subtítulo corto no se
    // repite cuando ya hay aviso.
    expect(find.textContaining('Advertencia fiscal'), findsOneWidget);
    expect(find.textContaining('Actívala cuando necesites'), findsNothing);
  });

  testWidgets('apagada: explica qué hace sin soltar el aviso completo', (
    tester,
  ) async {
    await _pump(tester, allow: false);

    expect(find.textContaining('Actívala cuando necesites'), findsOneWidget);
    expect(find.textContaining('Advertencia fiscal'), findsNothing);
  });
  testWidgets('apagado: explica qué hace y no muestra el aviso rojo', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.text('Ventas sin comprobante electrónico'),
      findsOneWidget,
    );
    expect(find.textContaining('Advertencia fiscal'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('encendido: muestra el aviso fiscal completo', (tester) async {
    await _pump(tester, allow: true);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('cancelar el diálogo no guarda nada', (tester) async {
    final repository = await _pump(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // El diálogo muestra el aviso íntegro antes de habilitar.
    expect(find.text(_warning), findsWidgets);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repository.calls, 0);
  });

  testWidgets('confirmar envía el cambio al servidor', (tester) async {
    final repository = await _pump(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entiendo y habilito'));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.lastAllow, isTrue);
  });

  testWidgets('deshabilitar pide confirmación y envía false', (tester) async {
    final repository = await _pump(tester, allow: true);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    // Al deshabilitar no se repite el aviso: se explica la consecuencia.
    expect(find.textContaining('dejará de ofrecer la opción'), findsOneWidget);

    await tester.tap(find.text('Deshabilitar'));
    await tester.pumpAndSettle();

    expect(repository.calls, 1);
    expect(repository.lastAllow, isFalse);
  });

  testWidgets('un fallo del servidor se informa y mantiene el estado real', (
    tester,
  ) async {
    await _pump(tester, failure: DioException(requestOptions: RequestOptions()));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entiendo y habilito'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No se pudo guardar el cambio'), findsOneWidget);
    // El interruptor sigue reflejando lo que dice el servidor, no el intento.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('sin permiso el interruptor está deshabilitado', (tester) async {
    final repository = await _pump(tester, canManage: false);

    final widget = tester.widget<Switch>(find.byType(Switch));
    expect(widget.onChanged, isNull);
    expect(find.textContaining('Solo un administrador'), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets('a 320 px no desborda', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester, allow: true, width: 288);

    expect(tester.takeException(), isNull);
  });
}
