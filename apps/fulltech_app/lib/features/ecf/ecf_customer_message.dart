/// Presentación para clientes. No modifica los mensajes ni códigos guardados.
/// Los identificadores internos siguen disponibles en el servidor para soporte.
String ecfCustomerMessage(String text) => text
    .replaceAll(
      RegExp(r'\b[A-Z0-9_]*DOSA_[A-Z0-9_]+\b'),
      'Referencia fiscal disponible para soporte',
    )
    .replaceAll(RegExp(r'\bDOSA\b', caseSensitive: false), 'el servicio fiscal');
