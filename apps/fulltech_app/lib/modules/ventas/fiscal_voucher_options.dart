const fiscalVoucherNoneLabel = 'Sin comprobante';

/// Etiquetas de los comprobantes NCF retirados. Solo se usan para mostrar el
/// histórico: el POS ya no ofrece B01/B02, el comprobante fiscal actual es el
/// e-CF (E31/E32) y se elige en la venta.
const _legacyVoucherLabels = <String, String>{
  'B01': 'B01 - Credito Fiscal',
  'B02': 'B02 - Consumo',
};

/// Normaliza un RNC / Cédula a solo dígitos para comparaciones consistentes.
/// `133020253` y `1-33-02025-3` se consideran el mismo documento.
String normalizeTaxId(String? input) {
  final raw = (input ?? '').trim();
  if (raw.isEmpty) return '';
  return raw.replaceAll(RegExp(r'\D'), '');
}

String fiscalVoucherLabel(String? type) {
  final normalized = type?.trim().toUpperCase();
  if (normalized == null || normalized.isEmpty) {
    return fiscalVoucherNoneLabel;
  }
  return _legacyVoucherLabels[normalized] ?? normalized;
}
