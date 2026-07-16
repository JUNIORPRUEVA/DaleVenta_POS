import 'package:intl/intl.dart';

const String kRdMoneyLocaleCode = 'en_US';

NumberFormat rdAccountingNumberFormat() {
  return NumberFormat('#,##0.00', kRdMoneyLocaleCode);
}

String formatRdAccountingAmount(num value) {
  return rdAccountingNumberFormat().format(value);
}

String formatRdCurrencyAccounting(num value) {
  final absValue = value.abs();
  final formatted = rdAccountingNumberFormat().format(absValue);
  final sign = value < 0 ? '-' : '';
  return '${sign}RD\$ $formatted';
}
