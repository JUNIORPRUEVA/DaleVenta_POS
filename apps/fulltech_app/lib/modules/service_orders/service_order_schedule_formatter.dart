import 'package:intl/intl.dart';

enum ServiceScheduleDayBucket {
  unscheduled,
  overdue,
  today,
  yesterday,
  tomorrow,
  future,
  past,
}

String formatServiceScheduledDateTime(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final referenceNow = (now ?? DateTime.now()).toLocal();

  final today = DateTime(
    referenceNow.year,
    referenceNow.month,
    referenceNow.day,
  );
  final targetDay = DateTime(local.year, local.month, local.day);
  final dayDiff = targetDay.difference(today).inDays;
  final timeLabel = DateFormat('h:mm a', 'en_US').format(local).toUpperCase();

  if (dayDiff == 0) {
    return 'Hoy · $timeLabel';
  }
  if (dayDiff == -1) {
    return 'Ayer · $timeLabel';
  }
  if (dayDiff == 1) {
    return 'Mañana · $timeLabel';
  }

  final dateLabel = DateFormat('dd/MM/yyyy').format(local);
  return '$dateLabel · $timeLabel';
}

String formatLastStatusMoment({
  required String statusLabel,
  required DateTime changedAt,
  DateTime? now,
}) {
  return '$statusLabel · ${formatServiceScheduledDateTime(changedAt, now: now)}';
}

ServiceScheduleDayBucket resolveServiceScheduleDayBucket(
  DateTime? value, {
  DateTime? now,
}) {
  if (value == null) {
    return ServiceScheduleDayBucket.unscheduled;
  }

  final local = value.toLocal();
  final referenceNow = (now ?? DateTime.now()).toLocal();

  final today = DateTime(
    referenceNow.year,
    referenceNow.month,
    referenceNow.day,
  );
  final targetDay = DateTime(local.year, local.month, local.day);
  final dayDiff = targetDay.difference(today).inDays;

  if (dayDiff == 0) {
    return ServiceScheduleDayBucket.today;
  }
  if (dayDiff == -1) {
    return ServiceScheduleDayBucket.yesterday;
  }
  if (dayDiff == 1) {
    return ServiceScheduleDayBucket.tomorrow;
  }
  if (dayDiff > 1) {
    return ServiceScheduleDayBucket.future;
  }

  if (local.isBefore(referenceNow)) {
    return ServiceScheduleDayBucket.overdue;
  }

  return ServiceScheduleDayBucket.past;
}
