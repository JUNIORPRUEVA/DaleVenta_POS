import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const businessTimeZoneName = 'America/Santo_Domingo';

bool _initialized = false;

tz.Location get businessLocation {
  _ensureInitialized();
  return tz.getLocation(businessTimeZoneName);
}

void _ensureInitialized() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

DateTime? parseServerInstant(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  if (!_hasExplicitTimeZone(text)) {
    return toBusinessTime(
      DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
      ),
    );
  }
  return toBusinessTime(parsed.toUtc());
}

tz.TZDateTime toBusinessTime(DateTime instant) {
  return tz.TZDateTime.from(instant.toUtc(), businessLocation);
}

DateTime businessNow([DateTime? instant]) {
  return toBusinessTime(instant ?? DateTime.now().toUtc());
}

String formatBusinessDate(DateTime instant, {String pattern = 'dd/MM/yyyy'}) {
  return DateFormat(pattern, 'es_DO').format(toBusinessTime(instant));
}

String formatBusinessDateTime(
  DateTime instant, {
  String pattern = 'dd/MM/yyyy HH:mm',
}) {
  return DateFormat(pattern, 'es_DO').format(toBusinessTime(instant));
}

String businessDateKey(DateTime instant) {
  return DateFormat('yyyy-MM-dd').format(toBusinessTime(instant));
}

DateTime businessDayStartUtc(DateTime businessDate) {
  final location = businessLocation;
  return tz
      .TZDateTime(
        location,
        businessDate.year,
        businessDate.month,
        businessDate.day,
      )
      .toUtc();
}

DateTime businessDayEndExclusiveUtc(DateTime businessDate) {
  final location = businessLocation;
  return tz
      .TZDateTime(
        location,
        businessDate.year,
        businessDate.month,
        businessDate.day + 1,
      )
      .toUtc();
}

bool sameBusinessDay(DateTime left, DateTime right) {
  return businessDateKey(left) == businessDateKey(right);
}

bool _hasExplicitTimeZone(String text) {
  return RegExp(r'(Z|[+-]\d{2}:\d{2})$', caseSensitive: false).hasMatch(text);
}
