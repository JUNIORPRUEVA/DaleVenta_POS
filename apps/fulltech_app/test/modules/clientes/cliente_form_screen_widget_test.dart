import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/realtime/operations_realtime_service.dart';
import 'package:daleventa_pos/modules/clientes/application/clientes_controller.dart';
import 'package:daleventa_pos/modules/clientes/cliente_form_screen.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';

/// Fake controller que evita red/BD y registra llamadas a `saveCliente`
/// para poder verificar el comportamiento del formulario.
class _FakeClientesController extends ClientesController {
  _FakeClientesController(super.ref) : super() {
    state = const ClientesState();
  }

  int saveCalls = 0;
  String? lastNombre;
  String? lastTelefono;
  String? lastTaxId;

  @override
  Future<void> load({String? search}) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<ClienteModel> saveCliente({
    required String nombre,
    required String telefono,
    String? direccion,
    String? locationUrl,
    String? correo,
    String? taxId,
    String? businessName,
    String? taxIdType,
    String? id,
  }) async {
    saveCalls++;
    lastNombre = nombre;
    lastTelefono = telefono;
    lastTaxId = taxId;
    state = state.copyWith(saving: true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    state = state.copyWith(saving: false);
    return ClienteModel(
      id: (id == null || id.isEmpty) ? 'client-new' : id,
      ownerId: 'owner-1',
      nombre: nombre.trim(),
      telefono: telefono.trim(),
      direccion: (direccion ?? '').trim().isEmpty ? null : direccion?.trim(),
      taxId: (taxId ?? '').trim().isEmpty ? null : taxId?.trim(),
    );
  }
}

Future<_FakeClientesController> _pumpForm(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      operationsRealtimeServiceProvider.overrideWith(
        (ref) => OperationsRealtimeService(TokenStorage()),
      ),
      clientesControllerProvider.overrideWith(
        (ref) => _FakeClientesController(ref),
      ),
    ],
  );
  addTearDown(container.dispose);
  final controller = container.read(
    clientesControllerProvider.notifier,
  ) as _FakeClientesController;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const ClienteFormScreen(
                      returnSavedClient: true,
                      compactDialog: true,
                    ),
                  ),
                ),
                child: const Text('Abrir formulario'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Abrir formulario'));
  await tester.pumpAndSettle();

  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cliente con solo nombre se puede guardar (teléfono opcional)', (
    tester,
  ) async {
    final controller = await _pumpForm(tester);

    // Sin nombre: la validación bloquea.
    await tester.tap(find.text('Guardar'));
    await tester.pump();
    expect(controller.saveCalls, 0);
    expect(find.text('El nombre es obligatorio'), findsOneWidget);

    // Solo nombre, sin teléfono ni RNC.
    await tester.enterText(find.byType(TextFormField).at(0), 'Juan Perez');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(controller.saveCalls, 1);
    expect(controller.lastNombre, 'Juan Perez');
    expect(controller.lastTelefono, '');
    expect(controller.lastTaxId, '');
  });

  testWidgets('cliente con nombre + RNC se puede guardar sin teléfono', (
    tester,
  ) async {
    final controller = await _pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Empresa SA');
    await tester.enterText(find.byType(TextFormField).at(2), '133020253');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(controller.saveCalls, 1);
    expect(controller.lastNombre, 'Empresa SA');
    expect(controller.lastTelefono, '');
    expect(controller.lastTaxId, '133020253');
  });

  testWidgets('Enter ejecuta Guardar y no crea cliente duplicado', (
    tester,
  ) async {
    final controller = await _pumpForm(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'Maria Lopez');
    await tester.pump();

    // Enter estando el campo de nombre enfocado.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    // Un segundo Enter mientras se guarda no debe duplicar.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.saveCalls, 1);
    expect(controller.lastNombre, 'Maria Lopez');

    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.saveCalls, 1);
  });

  testWidgets('solo Nombre se muestra como obligatorio (sin * en Teléfono)', (
    tester,
  ) async {
    await _pumpForm(tester);

    expect(find.text('Nombre o razón social *'), findsOneWidget);
    expect(find.text('Teléfono'), findsOneWidget);
    expect(find.text('Teléfono *'), findsNothing);
  });

  testWidgets('orden visual: Nombre, Teléfono, RNC/Cédula, Dirección', (
    tester,
  ) async {
    await _pumpForm(tester);

    final nombreY = tester.getCenter(find.text('Nombre o razón social *')).dy;
    final telefonoY = tester.getCenter(find.text('Teléfono')).dy;
    final rncY = tester.getCenter(find.text('RNC / Cédula')).dy;
    final direccionY = tester.getCenter(find.text('Dirección')).dy;

    expect(nombreY, lessThan(telefonoY));
    expect(telefonoY, lessThan(rncY));
    expect(rncY, lessThan(direccionY));
  });
}
