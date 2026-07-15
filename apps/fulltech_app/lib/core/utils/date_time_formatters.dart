import 'package:intl/intl.dart';

const String kRdLocaleCode = 'es_DO';

String formatRdDate(DateTime value) {
  return DateFormat('dd/MM/yyyy', kRdLocaleCode).format(value.toLocal());
}

String formatRdTime(DateTime value) {
  return DateFormat('h:mm a', kRdLocaleCode).format(value.toLocal());
}

String formatRdDateTime(DateTime value) {
  return DateFormat('dd/MM/yyyy h:mm a', kRdLocaleCode).format(value.toLocal());
}

String formatRdShortDateTime(DateTime value) {
  return DateFormat('dd/MM h:mm a', kRdLocaleCode).format(value.toLocal());
}

String formatRdWeekdayShortDateTime(DateTime value) {
  return DateFormat('EEE dd/MM h:mm a', kRdLocaleCode).format(value.toLocal());
}

String formatRdIsoLikeDateTime(DateTime value) {
  return DateFormat('yyyy-MM-dd h:mm a', kRdLocaleCode).format(value.toLocal());
}
