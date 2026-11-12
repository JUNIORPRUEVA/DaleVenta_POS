/// Nombres de archivo legibles para los PDF de documentos comerciales.
///
/// Se usan tanto para guardar en Descargas como para compartir, así que el
/// nombre debe quedar presentable: «Cotización de Juan Pérez.pdf».
library;

/// Nombres de cliente que no identifican a nadie y no deben ir en el archivo.
const Set<String> _placeholderCustomerNames = <String>{
  '',
  'sin cliente',
  'cliente',
  'cliente no especificado',
  'consumidor final',
  'consumidor',
};

/// Partículas que se escriben en minúscula dentro de un nombre propio.
const Set<String> _lowercaseParticles = <String>{
  'de',
  'del',
  'el',
  'la',
  'las',
  'lo',
  'los',
  'y',
  'e',
  'da',
  'das',
  'do',
  'dos',
  'van',
  'von',
};

/// Siglas que deben conservarse en mayúscula.
const Set<String> _acronyms = <String>{
  'SRL',
  'SAS',
  'SA',
  'EIRL',
  'RL',
  'CXP',
  'DGII',
  'RNC',
};

/// Construye el nombre del archivo: «Cotización de Juan Pérez.pdf».
///
/// [documentKind] es el tipo de documento ya escrito («Cotización», «Factura»).
/// Si no hay un nombre de cliente real se usa [fallbackCode] para no dejar el
/// archivo sin identificar.
String buildPdfDocumentFileName({
  required String documentKind,
  String? customerName,
  String? fallbackCode,
}) {
  final customer = _sanitizeToken(formatCustomerNameForFile(customerName));
  if (customer.isEmpty) {
    final code = _sanitizeToken(fallbackCode);
    return code.isEmpty ? '$documentKind.pdf' : '$documentKind $code.pdf';
  }
  return '$documentKind de $customer.pdf';
}

/// Normaliza el nombre del cliente para mostrarlo en un archivo.
///
/// Devuelve cadena vacía cuando el nombre es un marcador genérico
/// («Consumidor final», «Sin cliente»…) o está vacío.
String formatCustomerNameForFile(String? value) {
  final cleaned = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return '';
  if (_placeholderCustomerNames.contains(cleaned.toLowerCase())) return '';
  return _titleCaseName(cleaned);
}

String _titleCaseName(String value) {
  final words = value.split(' ').where((word) => word.isNotEmpty);
  final formatted = <String>[];
  for (final word in words) {
    if (_acronyms.contains(word.toUpperCase())) {
      formatted.add(word.toUpperCase());
      continue;
    }
    final lower = word.toLowerCase();
    if (formatted.isNotEmpty && _lowercaseParticles.contains(lower)) {
      formatted.add(lower);
      continue;
    }
    formatted.add(_capitalize(lower));
  }
  return formatted.join(' ');
}

String _capitalize(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}

String _sanitizeToken(String? value) {
  final cleaned = (value ?? '')
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}
