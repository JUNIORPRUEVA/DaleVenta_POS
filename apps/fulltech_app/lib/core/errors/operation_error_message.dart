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
    return 'No hay existencias suficientes$name.$quantities '
        'Revisa la cantidad y el inventario antes de cobrar. '
        'Registra una entrada solo si recibiste mercancía.';
  }
  if (text.contains('origin_session_closed')) {
    return 'El turno de esta operación ya está cerrado. Pide al encargado que revise la operación y el cierre original; no la registres en otro turno.';
  }
  if (text.contains('origin_session_not_found') ||
      text.contains('legacy_missing_session')) {
    return 'No pudimos comprobar a qué turno pertenece esta operación. Pide al encargado que la revise con soporte; no la registres en otro turno.';
  }
  if (text.contains('offline_protocol_unsupported')) {
    return 'Esta función necesita una actualización del servicio para sincronizarse. Contacta a soporte y conserva las operaciones pendientes en este equipo.';
  }
  if (text.contains('offline_sync_conflict') ||
      statusCode == 409 ||
      RegExp(r'\b409\b').hasMatch(text)) {
    return 'Esta operación necesita revisión. Comprueba si ya aparece en el historial y pide ayuda al encargado antes de repetirla.';
  }
  // Old backends used this stock explanation for online sales too. Without
  // structured details, do not guess the product, quantities or connectivity.
  if (text.contains('stock cambió mientras el dispositivo')) {
    return 'No se pudo completar la venta por una diferencia de inventario. Revisa las existencias de los productos y consulta al encargado antes de repetir el cobro.';
  }
  if (statusCode == 401 || RegExp(r'\b401\b').hasMatch(text)) {
    return 'Necesitas iniciar sesión nuevamente para continuar sincronizando.';
  }
  if (statusCode == 403) {
    return 'Tu usuario no tiene permiso para completar esta operación. Pide ayuda al administrador de la empresa.';
  }
  return null;
}

String? _quantity(Object? value) {
  final number = value is num ? value : num.tryParse('$value');
  if (number == null || !number.isFinite) return null;
  return NumberFormat('0.######', 'es_DO').format(number);
}
