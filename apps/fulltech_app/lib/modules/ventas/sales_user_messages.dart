import '../../core/debug/app_error_reporter.dart';
import '../../core/errors/api_exception.dart';

class SalesUserMessage {
  const SalesUserMessage({required this.title, required this.body});

  final String title;
  final String body;
}

SalesUserMessage salesReturnMessage(Object error) {
  final code = _errorCode(error);
  final normalized = _errorText(error);

  if (code == 'SALE_ALREADY_FULLY_RETURNED' ||
      normalized.contains('YA FUE DEVUELTA') ||
      normalized.contains('NO TIENE SUFICIENTES UNIDADES PENDIENTES')) {
    return const SalesUserMessage(
      title: 'No se pudo realizar la devolucion',
      body:
          'Esta factura ya fue devuelta completamente y no quedan productos pendientes por devolver.',
    );
  }

  if (code == 'RETURN_QUANTITY_EXCEEDED' ||
      normalized.contains('SUPERA LA CANTIDAD DISPONIBLE')) {
    return const SalesUserMessage(
      title: 'No se pudo completar la devolucion',
      body:
          'Esta factura no tiene suficientes unidades pendientes por devolver.',
    );
  }

  if (code == 'SALE_CANCELLED' || normalized.contains('VENTA CANCELADA')) {
    return const SalesUserMessage(
      title: 'No se pudo realizar la devolucion',
      body: 'Esta venta ya fue cancelada y no puede devolverse.',
    );
  }

  return _commonSalesMessage(error, 'No se pudo realizar la devolucion');
}

SalesUserMessage salesCancelMessage(Object error) {
  final code = _errorCode(error);
  final normalized = _errorText(error);

  if (code == 'SALE_ALREADY_CANCELLED' ||
      normalized.contains('YA FUE CANCELADA')) {
    return const SalesUserMessage(
      title: 'No se pudo cancelar la venta',
      body: 'Esta venta ya fue cancelada anteriormente.',
    );
  }

  if (code == 'SALE_ALREADY_FULLY_RETURNED' ||
      normalized.contains('YA FUE DEVUELTA')) {
    return const SalesUserMessage(
      title: 'No se pudo cancelar la venta',
      body:
          'Esta venta ya fue devuelta completamente y no necesita cancelarse.',
    );
  }

  return _commonSalesMessage(error, 'No se pudo cancelar la venta');
}

void recordSalesOperationError({
  required Object error,
  required StackTrace stackTrace,
  required String context,
  required SalesUserMessage userMessage,
}) {
  AppErrorReporter.instance.record(
    error,
    stackTrace,
    context: context,
    title: userMessage.title,
    userMessage: userMessage.body,
    notifyUser: false,
  );
}

SalesUserMessage _commonSalesMessage(Object error, String title) {
  if (error is ApiException) {
    if (error.isNetworkError) {
      return SalesUserMessage(
        title: title,
        body:
            'No pudimos completar la operacion porque no hay conexion con el servidor. Verifica tu conexion e intentalo nuevamente.',
      );
    }
    if (error.type == ApiErrorType.unauthorized ||
        error.type == ApiErrorType.forbidden) {
      return SalesUserMessage(
        title: title,
        body: 'No tienes permiso para realizar esta accion.',
      );
    }
  }

  return SalesUserMessage(
    title: title,
    body: 'No se pudo completar la operacion. Intentalo nuevamente.',
  );
}

String _errorCode(Object error) {
  if (error is ApiException) return error.displayCode.trim().toUpperCase();
  return '';
}

String _errorText(Object error) {
  final text = error is ApiException ? error.message : error.toString();
  return text.trim().toUpperCase();
}
