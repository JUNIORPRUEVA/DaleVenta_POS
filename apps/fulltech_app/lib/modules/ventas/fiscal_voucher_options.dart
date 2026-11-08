class FiscalVoucherOption {
  const FiscalVoucherOption({
    required this.type,
    required this.label,
    required this.shortLabel,
  });

  final String type;
  final String label;
  final String shortLabel;
}

const fiscalVoucherNoneLabel = 'Sin comprobante';

const _supportedFiscalVoucherOptions = <String, FiscalVoucherOption>{
  'B01': FiscalVoucherOption(
    type: 'B01',
    label: 'B01 - Credito Fiscal',
    shortLabel: 'B01',
  ),
  'B02': FiscalVoucherOption(
    type: 'B02',
    label: 'B02 - Consumo',
    shortLabel: 'B02',
  ),
};

bool shouldShowFiscalVoucherControl({
  required bool taxEnabled,
  required bool ncfEnabled,
}) {
  return taxEnabled && ncfEnabled;
}

/// Normaliza un RNC / Cédula a solo dígitos para comparaciones consistentes.
/// `133020253` y `1-33-02025-3` se consideran el mismo documento.
String normalizeTaxId(String? input) {
  final raw = (input ?? '').trim();
  if (raw.isEmpty) return '';
  return raw.replaceAll(RegExp(r'\D'), '');
}

bool isB01FiscalClientValid(String? taxId, [String? fiscalName]) {
  final digits = normalizeTaxId(taxId);
  final name = (fiscalName ?? '').trim();
  return digits.length >= 9 && name.isNotEmpty;
}

String fiscalVoucherLabel(String? type) {
  final normalized = type?.trim().toUpperCase();
  if (normalized == null || normalized.isEmpty) {
    return fiscalVoucherNoneLabel;
  }
  return _supportedFiscalVoucherOptions[normalized]?.label ?? normalized;
}
