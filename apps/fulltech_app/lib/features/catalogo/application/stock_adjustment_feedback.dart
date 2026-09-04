import 'package:dio/dio.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/utils/app_feedback.dart';

/// Centraliza la conversión de errores del ajuste de stock a mensajes
/// entendibles para el cliente final.
///
/// Nunca expone detalles técnicos: DioException, códigos HTTP, RequestOptions,
/// trazas o endpoints. Si no se reconoce el error se usa un respaldo seguro y
/// el detalle técnico permanece únicamente en los logs internos.
class StockAdjustmentFeedback {
  const StockAdjustmentFeedback._();

  static const String title = 'No se pudo ajustar el stock';
  static const String fallbackBody =
      'Ocurrió un problema al actualizar el inventario. Inténtalo nuevamente.';

  static AppFeedbackNotification failure(Object error) {
    if (_isNetworkError(error)) {
      return const AppFeedbackNotification(
        title: title,
        body:
            'No se pudo conectar con el servidor. Revisa la conexión e inténtalo nuevamente.',
        kind: AppFeedbackKind.error,
      );
    }

    final code = _rawCode(error);
    final message = _rawMessage(error) ?? '';
    final normalized = _normalize(message);

    // El catálogo de productos no permite ajustes manuales de stock.
    if (normalized.contains('no permite ajustes de stock')) {
      return const AppFeedbackNotification(
        title: title,
        body:
            'Este catálogo de productos no permite modificar el stock manualmente. Coordina el ajuste por otra vía.',
        kind: AppFeedbackKind.warning,
      );
    }

    if (normalized.contains('control de inventario') &&
        normalized.contains('desactiv')) {
      return const AppFeedbackNotification(
        title: title,
        body:
            'El control de inventario está desactivado. Actívalo para ajustar stock físico.',
        kind: AppFeedbackKind.warning,
      );
    }

    if (normalized.contains('no maneja inventario fisico')) {
      return const AppFeedbackNotification(
        title: title,
        body:
            'Este artículo no maneja inventario físico. La venta o compra se registra sin ajuste de stock.',
        kind: AppFeedbackKind.warning,
      );
    }

    // Stock insuficiente / no puede quedar negativo.
    if (_codeIs(code, 'INSUFFICIENT_WAREHOUSE_STOCK') ||
        normalized.contains('insuficiente') ||
        normalized.contains('insufficient') ||
        normalized.contains('negativ')) {
      return const AppFeedbackNotification(
        title: title,
        body:
            'El stock disponible no alcanza para completar este ajuste. Verifica la cantidad e inténtalo nuevamente.',
        kind: AppFeedbackKind.warning,
      );
    }

    // El stock cambió mientras se aplicaba el ajuste.
    if (_codeIs(code, 'WAREHOUSE_STOCK_CONCURRENT_MODIFICATION') ||
        normalized.contains('modificado concurrentemente') ||
        normalized.contains('no coincide')) {
      return const AppFeedbackNotification(
        title: title,
        body:
            'El stock cambió mientras se aplicaba el ajuste. Revisa el stock actual e inténtalo nuevamente.',
        kind: AppFeedbackKind.warning,
      );
    }

    // Almacén ya no está activo o no existe.
    if (_codeIs(code, 'WAREHOUSE_INACTIVE') ||
        normalized.contains('almacen activo no encontrado')) {
      return const AppFeedbackNotification(
        title: title,
        body:
            'El almacén seleccionado ya no está activo. Selecciona otro almacén e inténtalo nuevamente.',
        kind: AppFeedbackKind.warning,
      );
    }

    // Error desconocido: respaldo seguro sin contenido técnico.
    return const AppFeedbackNotification(
      title: title,
      body: fallbackBody,
      kind: AppFeedbackKind.error,
    );
  }

  static bool _codeIs(String? code, String expected) =>
      code != null &&
      (code.toUpperCase() == expected || code.toUpperCase().contains(expected));

  static bool _isNetworkError(Object error) {
    if (error is ApiException) return error.isNetworkError;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.badCertificate:
        case DioExceptionType.connectionError:
          return true;
        case DioExceptionType.unknown:
          return error.response == null;
        case DioExceptionType.cancel:
        case DioExceptionType.badResponse:
          return false;
      }
    }
    return false;
  }

  static String? _rawCode(Object error) {
    if (error is ApiException) return error.displayCode;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final code = data['code'] ?? data['errorCode'];
        if (code is String && code.trim().isNotEmpty) return code;
      }
    }
    return null;
  }

  static String? _rawMessage(Object error) {
    if (error is ApiException) return error.message;
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final message = data['message'];
        if (message is String && message.trim().isNotEmpty) return message;
        final nested = data['error'];
        if (nested is String && nested.trim().isNotEmpty) return nested;
      }
    }
    return null;
  }

  static String _normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u');
}
