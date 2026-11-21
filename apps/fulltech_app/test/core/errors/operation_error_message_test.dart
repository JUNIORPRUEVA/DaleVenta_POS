import 'dart:convert';

import 'package:daleventa_pos/core/api/api_error_mapper.dart';
import 'package:daleventa_pos/core/errors/api_exception.dart';
import 'package:daleventa_pos/core/errors/operation_error_message.dart';
import 'package:daleventa_pos/core/errors/user_safe_error_text.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('useful validation details are kept, including numeric product references', () {
    for (final message in ['El producto 429 no existe.', 'La cantidad máxima es 422.']) {
      expect(userSafeErrorMessage(ApiException(message, 422), fallback: 'Revisa los datos.'), message);
    }
  });
  for (final code in [401, 403, 422, 429, 500]) {
    test(
      'HTTP $code fallback stays brief without changing retry classification',
      () {
        final error = ApiException(
          'DioException status code $code /cash/movements',
          code,
        );
        final retryable = error.retryable;
        final result = userSafeErrorMessage(
          error,
          fallback: 'Consulta al encargado.',
        );
        expect(result.length, lessThan(120));
        expect(result, isNot(contains('DioException')));
        expect(result, isNot(contains('/cash/')));
        expect(error.retryable, retryable);
      },
    );
  }
  test(
    'ordinary authentication and permission errors retain their explanation',
    () {
      for (final status in [401, 403]) {
        final request = RequestOptions(path: '/auth/login');
        final error = DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: status,
            data: {'message': 'Consulta al administrador de tu empresa.'},
          ),
        );
        final mapped = ApiErrorMapper.fromDio(
          error,
          fallbackMessage: 'No se pudo entrar',
        );
        expect(mapped.message, 'Consulta al administrador de tu empresa.');
        expect(mapped.code, status);
      }
    },
  );
  final stock = {
    'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
    'message':
        'Esta venta no pudo sincronizarse porque el stock cambió mientras el dispositivo estaba sin conexión.',
    'details': {
      'productName': 'Tela de prueba',
      'requestedQuantity': '5.000000',
      'availableQuantity': '2.000000',
    },
  };

  test(
    'stock response explains which product and quantities, online or stored',
    () {
      for (final data in [stock, jsonEncode(stock)]) {
        final message = customerOperationErrorMessage(data, statusCode: 409)!;
        expect(message, contains('«Tela de prueba»'));
        expect(message, contains('Cantidad solicitada: 5. Disponible: 2.'));
        expect(message, contains('Revisa la cantidad antes de cobrar'));
        expect(message, isNot(contains('Registra una entrada')));
        expect(message, isNot(contains('sin conexión')));
        expect(message, isNot(contains('000000')));
      }
    },
  );

  test(
    'decimal quantities remain precise and missing data is not invented',
    () {
      final data = {
        'code': 'INSUFFICIENT_WAREHOUSE_STOCK',
        'details': {'requestedQuantity': 1.25, 'availableQuantity': 0.5},
      };
      final message = customerOperationErrorMessage(data)!;
      expect(message, contains('1,25'));
      expect(message, contains('0,5'));
      expect(message, isNot(contains('«')));
      expect(
        customerOperationErrorMessage({'code': 'INSUFFICIENT_WAREHOUSE_STOCK'}),
        isNot(contains('Disponible:')),
      );
    },
  );

  test(
    'a cash session from a previous day asks to close and reopen the shift',
    () {
      const raw =
          '{"code":"CASH_SESSION_STALE","errorCode":"CASH_SESSION_STALE",'
          '"sessionId":"54648624-a0ce-49f3-ae62-b8a3c1febb2a",'
          '"message":"Este turno es de un día anterior y ya no puede recibir '
          'operaciones."}';
      for (final data in [
        raw,
        {'code': 'CASH_SESSION_STALE', 'errorCode': 'CASH_SESSION_STALE'},
      ]) {
        final message = customerOperationErrorMessage(data, statusCode: 409)!;
        expect(message, contains('turno de caja'));
        expect(message, contains('Ciérralo y abre un turno nuevo'));
        expect(message, contains('facturar'));
        expect(message, isNot(contains('necesita revisión')));
      }
    },
  );

  test('Dio conversion retains diagnostics and the nonretryable conflict', () {
    final request = RequestOptions(path: '/sales', method: 'POST');
    final error = DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: request, statusCode: 409, data: stock),
    );
    final mapped = ApiErrorMapper.fromDio(
      error,
      fallbackMessage: 'No se pudo guardar',
    );
    expect(mapped.code, 409);
    expect(mapped.displayCode, 'INSUFFICIENT_WAREHOUSE_STOCK');
    expect(mapped.type, ApiErrorType.conflict);
    expect(mapped.retryable, isFalse);
    expect(mapped.responseBody, stock.toString());
    expect(mapped.technicalDetails, isNotEmpty);
    expect(
      userSafeErrorMessage(mapped, fallback: 'Error'),
      contains('«Tela de prueba»'),
    );
  });

  test(
    'unknown conflicts require review, never an automatic retry or stock guess',
    () {
      final message = customerOperationErrorMessage({
        'code': 'NEW_CONFLICT',
      }, statusCode: 409)!;
      expect(message, contains('historial'));
      expect(message, isNot(contains('inventario')));
      expect(message, isNot(contains('internet')));
      expect(message, isNot(contains('NEW_CONFLICT')));
    },
  );

  test(
    'technical API text is hidden, permissions differ from authentication',
    () {
      expect(
        userSafeErrorMessage(
          ApiException('NEW_BACKEND_ERROR'),
          fallback: 'Pide ayuda',
        ),
        'Pide ayuda',
      );
      expect(
        customerOperationErrorMessage(null, statusCode: 403),
        contains('permiso'),
      );
      expect(
        customerOperationErrorMessage(null, statusCode: 401),
        contains('iniciar sesión'),
      );
    },
  );
}
