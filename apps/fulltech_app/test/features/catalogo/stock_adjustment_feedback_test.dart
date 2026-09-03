import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/features/catalogo/application/stock_adjustment_feedback.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dioError(
  int status, {
  required Object data,
  DioExceptionType type = DioExceptionType.badResponse,
}) {
  return DioException(
    requestOptions: RequestOptions(path: '/products/x/adjust-stock'),
    type: type,
    response: Response<Object>(
      requestOptions: RequestOptions(path: '/products/x/adjust-stock'),
      statusCode: status,
      data: data,
    ),
  );
}

void main() {
  group('StockAdjustmentFeedback.failure', () {
    test('raw DioException 409 does not leak technical text', () {
      final result = StockAdjustmentFeedback.failure(
        _dioError(409, data: {
          'statusCode': 409,
          'message': 'La fuente de productos actual no permite ajustes de stock.',
          'error': 'Conflict',
        }),
      );

      expect(result.title, 'No se pudo ajustar el stock');
      expect(result.body, contains('no permite modificar el stock'));
      expect(result.body, isNot(contains('DioException')));
      expect(result.body, isNot(contains('409')));
      expect(result.body, isNot(contains('RequestOptions')));
      expect(result.body, isNot(contains('validateStatus')));
      expect(result.body, isNot(contains('La fuente de productos')));
    });

    test('known insufficient-stock conflict code maps to friendly message', () {
      final result = StockAdjustmentFeedback.failure(
        _dioError(409, data: {
          'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
          'message': 'Esta venta no pudo sincronizarse porque el stock cambió.',
        }),
      );

      expect(result.title, 'No se pudo ajustar el stock');
      expect(result.body, contains('no alcanza'));
      expect(result.body, isNot(contains('sincronizarse')));
      expect(result.body, isNot(contains('409')));
      expect(result.body, isNot(contains('DioException')));
    });

    test('concurrent-modification conflict maps to friendly message', () {
      final result = StockAdjustmentFeedback.failure(
        _dioError(409, data: {
          'code': 'WAREHOUSE_STOCK_CONCURRENT_MODIFICATION',
          'message': 'WarehouseStock no encontrado o modificado concurrentemente',
        }),
      );

      expect(result.title, 'No se pudo ajustar el stock');
      expect(result.body, contains('cambió mientras se aplicaba'));
      expect(result.body, isNot(contains('WarehouseStock')));
    });

    test('unknown stock error uses safe fallback', () {
      final result = StockAdjustmentFeedback.failure(
        _dioError(500, data: {
          'message': 'Internal server error details hidden here',
        }),
      );

      expect(result.title, 'No se pudo ajustar el stock');
      expect(
        result.body,
        'Ocurrió un problema al actualizar el inventario. Inténtalo nuevamente.',
      );
      expect(result.body, isNot(contains('Internal')));
      expect(result.body, isNot(contains('500')));
    });

    test('generic exception never leaks its type', () {
      final result = StockAdjustmentFeedback.failure(
        Exception('DioException: something technical'),
      );

      expect(result.title, 'No se pudo ajustar el stock');
      expect(result.body, isNot(contains('DioException')));
      expect(result.body, isNot(contains('Exception')));
      expect(result.body, isNot(contains('something technical')));
    });

    test('network ApiException maps to connection message', () {
      const network = ApiException.detailed(
        message: 'timeout',
        type: ApiErrorType.timeout,
        displayCode: 'NETWORK_TIMEOUT',
      );
      final result = StockAdjustmentFeedback.failure(network);

      expect(result.title, 'No se pudo ajustar el stock');
      expect(result.body, contains('conectar con el servidor'));
      expect(result.body, isNot(contains('timeout')));
    });

    test('raw DioException connectionError maps to connection message', () {
      final result = StockAdjustmentFeedback.failure(
        DioException.connectionError(
          requestOptions: RequestOptions(path: '/products/x/adjust-stock'),
          reason: 'Connection refused',
        ),
      );

      expect(result.title, 'No se pudo ajustar el stock');
      expect(result.body, contains('conectar con el servidor'));
      expect(result.body, isNot(contains('Connection refused')));
    });
  });
}
