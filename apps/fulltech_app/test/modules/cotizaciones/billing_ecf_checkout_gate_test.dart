import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardas del cobro con comprobante electrónico en el punto de venta REAL
/// (`/cotizaciones`).
///
/// Son comprobaciones de texto porque lo que hay que proteger es el **orden**
/// de las operaciones dentro de una pantalla muy grande:
///
///   1. comprobar que hay comprobante disponible antes de abrir el cobro,
///   2. cobrar y avisar al usuario de que la venta quedó guardada,
///   3. emitir el comprobante (llamada lenta al proveedor, nunca antes del
///      aviso).
void main() {
  final screen = File(
    'lib/modules/cotizaciones/cotizaciones_screen.dart',
  ).readAsStringSync();
  final router = File('lib/core/routing/app_router.dart').readAsStringSync();

  test('el cobro comprueba el comprobante antes de abrir el diálogo', () {
    final gate = screen.indexOf('await _ensureEcfReadyBeforeCheckout()');
    final dialog = screen.indexOf('showDialog<_CheckoutResult>(');

    expect(gate, greaterThanOrEqualTo(0));
    expect(dialog, greaterThanOrEqualTo(0));
    expect(
      gate,
      lessThan(dialog),
      reason: 'Sin comprobante disponible no debe abrirse el cobro.',
    );
  });

  test('el comprobante se emite después de avisar que la venta se guardó', () {
    final notice = screen.indexOf('title: _saleSavedNoticeTitle(createdSale)');
    final emit = screen.indexOf('await _applyEcfFiscalMode(');

    expect(notice, greaterThanOrEqualTo(0));
    expect(emit, greaterThanOrEqualTo(0));
    expect(
      emit,
      greaterThan(notice),
      reason:
          'La emisión habla con el proveedor y no puede retrasar el aviso al '
          'usuario.',
    );
  });

  test('el comprobante viaja con el resultado del cobro', () {
    expect(screen, contains('this.ecfMode,'));
    expect(screen, contains('ecfMode: _ecfMode,'));
    expect(screen, contains('EcfPosFiscalSelector('));
  });

  test('la ruta antigua /ventas/nueva redirige al punto de venta real', () {
    expect(
      router,
      contains('redirect: (context, state) => Routes.cotizaciones'),
      reason:
          'Había dos pantallas para lo mismo y la antigua no emitía '
          'comprobante electrónico.',
    );
    expect(router, isNot(contains('RegistrarVentaScreen()')));
  });
}
