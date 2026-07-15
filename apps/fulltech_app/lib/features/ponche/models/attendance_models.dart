import '../../../core/models/punch_model.dart';

DateTime? _parseDate(String? value) =>
    value == null ? null : DateTime.tryParse(value);

class AttendanceIncident {
  final String type;
  final int minutes;
  final DateTime? referenceTime;

  AttendanceIncident({
    required this.type,
    required this.minutes,
    this.referenceTime,
  });

  factory AttendanceIncident.fromJson(Map<String, dynamic> json) {
    return AttendanceIncident(
      type: json['type'] ?? 'UNKNOWN',
      minutes: json['minutes'] ?? 0,
      referenceTime: _parseDate(json['referenceTime']),
    );
  }
}

class AttendanceDayMetrics {
  final String date;
  final DateTime? entry;
  final DateTime? exit;
  final int expectedWorkMinutes;
  final int lunchMinutes;
  final bool lunchComplete;
  final int permisoMinutes;
  final bool permisoComplete;
  final int tardinessMinutes;
  final int earlyLeaveMinutes;
  final int? workedMinutesNet;
  final int favorableMinutes;
  final int unfavorableMinutes;
  final int balanceMinutes;
  final int notWorkedMinutes;
  final bool incomplete;
  final bool isWeekend;
  final List<AttendanceIncident> incidents;

  AttendanceDayMetrics({
    required this.date,
    this.entry,
    this.exit,
    required this.expectedWorkMinutes,
    required this.lunchMinutes,
    required this.lunchComplete,
    required this.permisoMinutes,
    required this.permisoComplete,
    required this.tardinessMinutes,
    required this.earlyLeaveMinutes,
    this.workedMinutesNet,
    required this.favorableMinutes,
    required this.unfavorableMinutes,
    required this.balanceMinutes,
    required this.notWorkedMinutes,
    required this.incomplete,
    required this.isWeekend,
    required this.incidents,
  });

  factory AttendanceDayMetrics.fromJson(Map<String, dynamic> json) {
    final incidentsJson = json['incidents'] as List<dynamic>?;
    return AttendanceDayMetrics(
      date: json['date'] ?? '',
      entry: _parseDate(json['entry']),
      exit: _parseDate(json['exit']),
      expectedWorkMinutes: json['expectedWorkMinutes'] ?? 0,
      lunchMinutes: json['lunchMinutes'] ?? 0,
      lunchComplete: json['lunchComplete'] ?? false,
      permisoMinutes: json['permisoMinutes'] ?? 0,
      permisoComplete: json['permisoComplete'] ?? false,
      tardinessMinutes: json['tardinessMinutes'] ?? 0,
      earlyLeaveMinutes: json['earlyLeaveMinutes'] ?? 0,
      workedMinutesNet: json['workedMinutesNet'],
      favorableMinutes: json['favorableMinutes'] ?? 0,
      unfavorableMinutes: json['unfavorableMinutes'] ?? 0,
      balanceMinutes: json['balanceMinutes'] ?? 0,
      notWorkedMinutes: json['notWorkedMinutes'] ?? 0,
      incomplete: json['incomplete'] ?? false,
      isWeekend: json['isWeekend'] ?? false,
      incidents: incidentsJson != null
          ? incidentsJson
                .whereType<Map<String, dynamic>>()
                .map(AttendanceIncident.fromJson)
                .toList()
          : const [],
    );
  }
}

class AttendanceAggregateMetrics {
  final int tardinessMinutes;
  final int earlyLeaveMinutes;
  final int notWorkedMinutes;
  final int workedMinutes;
  final int favorableMinutes;
  final int unfavorableMinutes;
  final int balanceMinutes;
  final int incompleteDays;
  final int incidentsCount;

  AttendanceAggregateMetrics({
    required this.tardinessMinutes,
    required this.earlyLeaveMinutes,
    required this.notWorkedMinutes,
    required this.workedMinutes,
    required this.favorableMinutes,
    required this.unfavorableMinutes,
    required this.balanceMinutes,
    required this.incompleteDays,
    required this.incidentsCount,
  });

  factory AttendanceAggregateMetrics.fromJson(Map<String, dynamic> json) {
    return AttendanceAggregateMetrics(
      tardinessMinutes: json['tardinessMinutes'] ?? 0,
      earlyLeaveMinutes: json['earlyLeaveMinutes'] ?? 0,
      notWorkedMinutes: json['notWorkedMinutes'] ?? 0,
      workedMinutes: json['workedMinutes'] ?? 0,
      favorableMinutes: json['favorableMinutes'] ?? 0,
      unfavorableMinutes: json['unfavorableMinutes'] ?? 0,
      balanceMinutes: json['balanceMinutes'] ?? 0,
      incompleteDays: json['incompleteDays'] ?? 0,
      incidentsCount: json['incidentsCount'] ?? 0,
    );
  }
}

class AttendanceUser {
  final String id;
  final String email;
  final String nombreCompleto;
  final String role;

  AttendanceUser({
    required this.id,
    required this.email,
    required this.nombreCompleto,
    required this.role,
  });

  factory AttendanceUser.fromJson(Map<String, dynamic> json) {
    return AttendanceUser(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      nombreCompleto: json['nombreCompleto'] ?? '',
      role: json['role'] ?? 'ASISTENTE',
    );
  }
}

class AttendanceUserSummary {
  final AttendanceUser user;
  final List<AttendanceDayMetrics> days;
  final AttendanceAggregateMetrics aggregate;

  AttendanceUserSummary({
    required this.user,
    required this.days,
    required this.aggregate,
  });

  factory AttendanceUserSummary.fromJson(Map<String, dynamic> json) {
    final daysJson = json['days'] as List<dynamic>?;
    return AttendanceUserSummary(
      user: AttendanceUser.fromJson(json['user'] as Map<String, dynamic>),
      days: daysJson != null
          ? daysJson
                .whereType<Map<String, dynamic>>()
                .map(AttendanceDayMetrics.fromJson)
                .toList()
          : const [],
      aggregate: AttendanceAggregateMetrics.fromJson(
        json['aggregate'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class AttendanceSummaryTotals {
  final int tardyCount;
  final int earlyLeaveCount;
  final int incompleteCount;
  final int workedMinutes;
  final int favorableMinutes;
  final int unfavorableMinutes;
  final int balanceMinutes;
  final int notWorkedMinutes;

  AttendanceSummaryTotals({
    required this.tardyCount,
    required this.earlyLeaveCount,
    required this.incompleteCount,
    required this.workedMinutes,
    required this.favorableMinutes,
    required this.unfavorableMinutes,
    required this.balanceMinutes,
    required this.notWorkedMinutes,
  });

  factory AttendanceSummaryTotals.fromJson(Map<String, dynamic> json) {
    return AttendanceSummaryTotals(
      tardyCount: json['tardyCount'] ?? 0,
      earlyLeaveCount: json['earlyLeaveCount'] ?? 0,
      incompleteCount: json['incompleteCount'] ?? 0,
      workedMinutes: json['workedMinutes'] ?? 0,
      favorableMinutes: json['favorableMinutes'] ?? 0,
      unfavorableMinutes: json['unfavorableMinutes'] ?? 0,
      balanceMinutes: json['balanceMinutes'] ?? 0,
      notWorkedMinutes: json['notWorkedMinutes'] ?? 0,
    );
  }
}

class AttendanceSummaryModel {
  final AttendanceSummaryTotals totals;
  final List<AttendanceUserSummary> users;
  final List<AttendanceDayMetrics> perDay;

  AttendanceSummaryModel({
    required this.totals,
    required this.users,
    required this.perDay,
  });

  factory AttendanceSummaryModel.fromJson(Map<String, dynamic> json) {
    final usersJson = json['users'] as List<dynamic>?;
    final perDayJson = json['perDay'] as List<dynamic>?;
    return AttendanceSummaryModel(
      totals: AttendanceSummaryTotals.fromJson(
        json['totals'] as Map<String, dynamic>? ?? {},
      ),
      users: usersJson != null
          ? usersJson
                .whereType<Map<String, dynamic>>()
                .map(AttendanceUserSummary.fromJson)
                .toList()
          : const [],
      perDay: perDayJson != null
          ? perDayJson
                .whereType<Map<String, dynamic>>()
                .map(AttendanceDayMetrics.fromJson)
                .toList()
          : const [],
    );
  }
}

class AttendanceDetailModel {
  final AttendanceUser user;
  final List<PunchModel> punches;
  final List<AttendanceDayMetrics> days;
  final AttendanceAggregateMetrics totals;

  AttendanceDetailModel({
    required this.user,
    required this.punches,
    required this.days,
    required this.totals,
  });

  factory AttendanceDetailModel.fromJson(Map<String, dynamic> json) {
    final punchesJson = json['punches'] as List<dynamic>?;
    final daysJson = json['days'] as List<dynamic>?;
    return AttendanceDetailModel(
      user: AttendanceUser.fromJson(json['user'] as Map<String, dynamic>),
      punches: punchesJson != null
          ? punchesJson
                .whereType<Map<String, dynamic>>()
                .map(PunchModel.fromJson)
                .toList()
          : const [],
      days: daysJson != null
          ? daysJson
                .whereType<Map<String, dynamic>>()
                .map(AttendanceDayMetrics.fromJson)
                .toList()
          : const [],
      totals: AttendanceAggregateMetrics.fromJson(
        json['totals'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}
