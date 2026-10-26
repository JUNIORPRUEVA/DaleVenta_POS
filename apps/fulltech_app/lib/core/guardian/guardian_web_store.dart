import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'guardian_event.dart';
import 'guardian_store.dart';

/// Cola de incidentes para **Web**.
///
/// sqflite no existe en navegador, así que se usa `shared_preferences`
/// (localStorage/IndexedDB según plataforma). Es una cola **separada** de la
/// sincronización comercial: nunca toca el almacenamiento de ventas.
class WebGuardianStore implements GuardianStore {
  WebGuardianStore({this.maxPersistedEvents = 100});

  static const String _eventsKey = 'guardian.outbox.events.v1';
  static const String _discardsKey = 'guardian.outbox.discards.v1';
  static const String _fingerprintsKey = 'guardian.outbox.fingerprints.v1';

  /// localStorage es limitado (~5 MB por origen); se acota más que en escritorio.
  final int maxPersistedEvents;

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return <dynamic>[];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<Map<String, dynamic>> _loadEvents() async {
    final prefs = await _prefs();
    return _decodeMap(prefs.getString(_eventsKey));
  }

  Future<void> _saveEvents(Map<String, dynamic> events) async {
    final prefs = await _prefs();
    await prefs.setString(_eventsKey, jsonEncode(events));
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> upsert(GuardianEvent event) async {
    final events = await _loadEvents();
    if (events.containsKey(event.eventId)) return;

    events[event.eventId] = <String, dynamic>{
      'payload': event.toApiJson(),
      'attempts': event.attempts,
      'next_attempt_at_ms': event.nextAttemptAtMs,
      'severity': event.severity,
      'occurred_at_ms': event.occurredAt.millisecondsSinceEpoch,
    };

    // Cuota dura del navegador: se descartan los menos graves más antiguos.
    if (events.length > maxPersistedEvents) {
      final entries = events.entries.toList()
        ..sort((a, b) {
          final bySeverity =
              (b.value['severity'] as String).compareTo(a.value['severity'] as String);
          if (bySeverity != 0) return bySeverity;
          return (a.value['occurred_at_ms'] as int).compareTo(b.value['occurred_at_ms'] as int);
        });
      for (final entry in entries) {
        if (events.length <= maxPersistedEvents) break;
        final severity = entry.value['severity'] as String?;
        if (severity == 'SEV1' || severity == 'SEV2') continue;
        events.remove(entry.key);
      }
    }

    await _saveEvents(events);
  }

  @override
  Future<List<GuardianEvent>> dueEvents({required int limit, DateTime? now}) async {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final events = await _loadEvents();
    final due = events.entries
        .where((entry) => ((entry.value['next_attempt_at_ms'] as int?) ?? 0) <= at)
        .toList()
      ..sort((a, b) {
        final bySeverity =
            (a.value['severity'] as String).compareTo(b.value['severity'] as String);
        if (bySeverity != 0) return bySeverity;
        return (a.value['occurred_at_ms'] as int).compareTo(b.value['occurred_at_ms'] as int);
      });

    return due.take(limit).map((entry) {
      final payload = (entry.value['payload'] as Map).cast<String, dynamic>();
      return GuardianEvent.fromDbRow(<String, dynamic>{
        'payload': jsonEncode(payload),
        'attempts': entry.value['attempts'] ?? 0,
        'next_attempt_at_ms': entry.value['next_attempt_at_ms'] ?? 0,
      });
    }).toList();
  }

  @override
  Future<void> markFailure(
    String eventId, {
    required int attempts,
    required int nextAttemptAtMs,
  }) async {
    final events = await _loadEvents();
    final current = events[eventId];
    if (current == null) return;
    events[eventId] = <String, dynamic>{
      ...current as Map<String, dynamic>,
      'attempts': attempts,
      'next_attempt_at_ms': nextAttemptAtMs,
    };
    await _saveEvents(events);
  }

  @override
  Future<void> removeAll(Iterable<String> eventIds) async {
    final events = await _loadEvents();
    for (final id in eventIds) {
      events.remove(id);
    }
    await _saveEvents(events);
  }

  @override
  Future<int> count() async => (await _loadEvents()).length;

  @override
  Future<int> totalBytes() async {
    final events = await _loadEvents();
    return utf8.encode(jsonEncode(events)).length;
  }

  @override
  Future<List<GuardianEvent>> selectForEviction({
    required int eventsToDrop,
    required int bytesToDrop,
  }) async {
    if (eventsToDrop <= 0 && bytesToDrop <= 0) return const [];
    final events = await _loadEvents();
    final candidates = events.entries
        .where((entry) => !['SEV1', 'SEV2'].contains(entry.value['severity'] as String?))
        .toList()
      ..sort((a, b) => (b.value['severity'] as String).compareTo(a.value['severity'] as String));

    final selected = <GuardianEvent>[];
    var bytes = 0;
    for (final entry in candidates) {
      if (selected.length >= eventsToDrop && bytes >= bytesToDrop) break;
      selected.add(
        GuardianEvent.fromDbRow(<String, dynamic>{
          'payload': jsonEncode(entry.value['payload']),
          'attempts': entry.value['attempts'] ?? 0,
          'next_attempt_at_ms': entry.value['next_attempt_at_ms'] ?? 0,
        }),
      );
      bytes += utf8.encode(jsonEncode(entry.value['payload'])).length;
    }
    return selected;
  }

  @override
  Future<void> recordDiscard(GuardianDiscardRecord record) async {
    final prefs = await _prefs();
    final discards = _decodeList(prefs.getString(_discardsKey));
    discards.add(<String, dynamic>{
      'eventId': record.eventId,
      'reason': record.reason,
      'at': record.at.millisecondsSinceEpoch,
    });
    await prefs.setString(_discardsKey, jsonEncode(discards.take(200).toList()));
  }

  @override
  Future<List<GuardianDiscardRecord>> discards() async {
    final prefs = await _prefs();
    return _decodeList(prefs.getString(_discardsKey)).whereType<Map>().map((row) {
      return GuardianDiscardRecord(
        eventId: (row['eventId'] ?? '').toString(),
        reason: (row['reason'] ?? '').toString(),
        at: DateTime.fromMillisecondsSinceEpoch((row['at'] as int?) ?? 0),
      );
    }).toList();
  }

  @override
  Future<bool> wasRecentlyRecorded(String fingerprint, {required Duration window}) async {
    final prefs = await _prefs();
    final entries = _decodeMap(prefs.getString(_fingerprintsKey));
    final at = entries[fingerprint];
    if (at is! int) return false;
    return DateTime.now().millisecondsSinceEpoch - at < window.inMilliseconds;
  }

  @override
  Future<void> markRecorded(String fingerprint) async {
    final prefs = await _prefs();
    final entries = _decodeMap(prefs.getString(_fingerprintsKey));
    entries[fingerprint] = DateTime.now().millisecondsSinceEpoch;
    await prefs.setString(_fingerprintsKey, jsonEncode(entries));
  }
}
