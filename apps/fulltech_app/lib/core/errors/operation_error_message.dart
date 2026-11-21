import 'dart:convert';

import 'package:intl/intl.dart';

/// Presentation only. Never decides whether an operation may be retried.
/// Accepts historical stored text as well as structured server responses.
String? customerOperationErrorMessage(Object? source, {int? statusCode}) {
  Object? data = source;
  if (source is String) {
    try {
      data = jsonDecode(source);
    } on FormatException {
      // Historical records also contain plain messages and exception text.
    }
  }
  final map = data is Map ? data : const {};
  final text = (map['code'] ?? map['errorCode'] ?? source ?? '')
      .toString()
      .toLowerCase();
  if (text.contains('insufficient_warehouse_stock')) {
    final details = map['details'] is Map ? map['details'] as Map : const {};
    final product = details['productName'];
    final name = product is String && product.trim().isNotEmpty
        ? ' de «${product.trim()}»'
        : '';
    final requested = _quantity(details['requestedQuantity']);
    final available = _quantity(details['availableQuantity']);
    final quantities = requested != null && available != null
        ? ' Cantidad solicitada: $requested. Disponible: $available.'
        : '';
    return 'Existencias insuficientes$name.$quantities Revisa la cantidad antes de cobrar.';
  }
  if (text.contains('origin_session_closed')) {
    return 'El turno original está cerrado. Comprueba el registro; no repitas la operación.';
  }
  if (text.contains('origin_session_not_found') ||
      text.contains('legacy_missing_session')) {
    return 'No se pudo identificar el turno original. Comprueba el registro; no repitas la operación.';
  }
  if (text.contains('offline_protocol_unsupported')) {
    return 'Se necesita actualizar el servicio. Contacta a soporte; tus operaciones siguen guardadas.';
  }
  // Un turno de caja de un día anterior es un estado conocido y accionable:
  // decirlo así evita el mensaje genérico de 409, que invita a "revisar el
  // historial" cuando en realidad solo hay que cerrar y abrir el turno.
  if (text.contains('cash_session_stale')) {
    return 'El turno de caja está vencido. Ciérralo y abre un turno nuevo para facturar.';
  }
  if (text.contains('offline_sync_conflict') ||
      statusCode == 409 ||
      RegExp(r'\b409\b').hasMatch(text)) {
    return 'Comprueba la operación en el historial con el encargado antes de repetirla.';
  }
  // Old backends used this stock explanation for online sales too. Without
  // structured details, do not guess the product, quantities or connectivity.
  if (text.contains('stock cambió mientras el dispositivo')) {
    return 'Hay una diferencia de inventario. Revisa las existencias antes de repetir el cobro.';
  }
  if (statusCode == 401 || RegExp(r'\b401\b').hasMatch(text)) {
    return 'Necesitas iniciar sesión de nuevo para continuar.';
  }
  if (statusCode == 403) {
    return 'No tienes permiso para esta acción. Consulta al administrador.';
  }
  if (statusCode == 422) {
    return 'Revisa los datos de la operación. No se reintentará automáticamente.';
  }
  if (statusCode == 429) {
    return 'Espera un momento antes de volver a consultar.';
  }
  if (statusCode != null && statusCode >= 500) {
    return 'El servicio no está disponible ahora. Inténtalo más tarde.';
  }
  return null;
}

String? _quantity(Object? value) {
  final number = value is num ? value : num.tryParse('$value');
  if (number == null || !number.isFinite) return null;
  return NumberFormat('0.######', 'es_DO').format(number);
}
