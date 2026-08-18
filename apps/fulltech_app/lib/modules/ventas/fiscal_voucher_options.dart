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

List<FiscalVoucherOption> fiscalVoucherOptionsFromConfiguredTypes({
  required bool taxEnabled,
  required bool ncfEnabled,
  required Iterable<String> configuredTypes,
}) {
  if (!shouldShowFiscalVoucherControl(
    taxEnabled: taxEnabled,
    ncfEnabled: ncfEnabled,
  )) {
    return const [];
  }

  final normalized = configuredTypes
      .map((value) => value.trim().toUpperCase())
      .where(_supportedFiscalVoucherOptions.containsKey)
      .toSet();

  return [
    for (final type in const ['B01', 'B02'])
      if (normalized.contains(type)) _supportedFiscalVoucherOptions[type]!,
  ];
}

bool shouldResetFiscalVoucherSelection({
  required String? selectedType,
  required Iterable<FiscalVoucherOption> options,
}) {
  final normalized = selectedType?.trim().toUpperCase();
  if (normalized == null || normalized.isEmpty) return false;
  return !options.any((option) => option.type == normalized);
}

bool isB01FiscalClientValid(String? taxId) {
  final digits = (taxId ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length >= 9;
}

String fiscalVoucherLabel(String? type) {
  final normalized = type?.trim().toUpperCase();
  if (normalized == null || normalized.isEmpty) {
    return fiscalVoucherNoneLabel;
  }
  return _supportedFiscalVoucherOptions[normalized]?.label ?? normalized;
}
