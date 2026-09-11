import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/modules/ventas/sales_user_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const forbiddenTokens = [
    'ApiException',
    'code: 400',
    'Exception:',
    'StackTrace',
    'Prisma',
    'HTTP 400',
  ];

  void expectClean(SalesUserMessage message) {
    final visible = '${message.title}\n${message.body}';
    for (final token in forbiddenTokens) {
      expect(visible, isNot(contains(token)));
    }
  }

  test('FULLY_RETURNED maps to a specific user message', () {
    final message = salesReturnMessage(
      const ApiException.detailed(
        message: 'ApiException: La devolucion supera la cantidad disponible',
        code: 400,
        displayCode: 'SALE_ALREADY_FULLY_RETURNED',
      ),
    );

    expect(message.title, 'No se pudo realizar la devolucion');
    expect(
      message.body,
      'Esta factura ya fue devuelta completamente y no quedan productos pendientes por devolver.',
    );
    expectClean(message);
  });

  test('RETURN_QUANTITY_EXCEEDED maps to available quantity guidance', () {
    final message = salesReturnMessage(
      const ApiException.detailed(
        message: 'La devolucion de Producto supera la cantidad disponible.',
        code: 400,
        displayCode: 'RETURN_QUANTITY_EXCEEDED',
      ),
    );

    expect(
      message.body,
      'Esta factura no tiene suficientes unidades pendientes por devolver.',
    );
    expectClean(message);
  });

  test('SALE_CANCELLED maps to cancelled sale copy', () {
    final message = salesReturnMessage(
      const ApiException.detailed(
        message: 'Esta venta ya fue cancelada.',
        code: 400,
        displayCode: 'SALE_CANCELLED',
      ),
    );

    expect(message.body, 'Esta venta ya fue cancelada y no puede devolverse.');
    expectClean(message);
  });

  test('PERMISSION_DENIED hides technical details', () {
    final message = salesReturnMessage(
      const ApiException.detailed(
        message: 'ForbiddenException: HTTP 403',
        code: 403,
        type: ApiErrorType.forbidden,
        displayCode: '403',
      ),
    );

    expect(message.body, 'No tienes permiso para realizar esta accion.');
    expectClean(message);
  });

  test('NETWORK uses connection recovery copy', () {
    final message = salesReturnMessage(
      const ApiException.detailed(
        message: 'DioException connection failed',
        type: ApiErrorType.network,
        displayCode: 'NETWORK_UNAVAILABLE',
      ),
    );

    expect(message.body, contains('conexion con el servidor'));
    expectClean(message);
  });

  test('UNKNOWN falls back without exposing raw exception text', () {
    final message = salesReturnMessage(
      Exception('Prisma StackTrace HTTP 400 ApiException code: 400'),
    );

    expect(
      message.body,
      'No se pudo completar la operacion. Intentalo nuevamente.',
    );
    expectClean(message);
  });
}
