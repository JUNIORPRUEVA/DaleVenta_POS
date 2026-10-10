import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('service orders UI carga pagina y loadMore sin listAll por defecto', () {
    final controllerSource = File(
      'lib/modules/service_orders/application/service_orders_list_controller.dart',
    ).readAsStringSync();
    final screenSource = File(
      'lib/modules/service_orders/service_orders_list_screen.dart',
    ).readAsStringSync();

    final loadStart = controllerSource.indexOf('Future<void> load({');
    final loadEnd = controllerSource.indexOf(
      'Future<void> refresh()',
      loadStart,
    );
    final loadBody = controllerSource.substring(loadStart, loadEnd);

    expect(loadBody, contains('listOrdersPage()'));
    expect(loadBody, isNot(contains('listAllOrders')));
    expect(controllerSource, contains('Future<void> loadMore()'));
    expect(screenSource, contains('controller.loadMore()'));
    expect(screenSource, contains('Cargar mas ordenes'));
  });
}
