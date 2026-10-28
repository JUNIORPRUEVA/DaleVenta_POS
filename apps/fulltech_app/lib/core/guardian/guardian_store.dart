import 'dart:convert';

import 'guardian_event.dart';

/// Resultado de una operación de la cola local.
class GuardianQueueSnapshot {
  const GuardianQueueSnapshot({required this.count, required this.bytes});

  final int count;
  final int bytes;
}

/// Registro de descartes inevitables (cuota o corrupción).
class GuardianDiscardRecord {
  const GuardianDiscardRecord({required this.eventId, required this.reason, required this.at});

  final String eventId;
  final String reason;
  final DateTime at;
}

/// Almacenamiento de la cola de incidentes.
///
/// Se abstrae para poder probar toda la lógica sin base de datos y para permitir
/// un fallback en plataformas sin sqflite (web).
abstract class GuardianStore {
  Future<void> init();

  /// Inserta o actualiza por `eventId` (idempotente).
  Future<void> upsert(GuardianEvent event);

  /// Eventos listos para enviar (respetando `nextAttemptAtMs` y prioridad).
  Future<List<GuardianEvent>> dueEvents({required int limit, DateTime? now});

  /// Marca un intento fallido con su próximo momento de reintento.
  Future<void> markFailure(String eventId, {required int attempts, required int nextAttemptAtMs});

  /// Elimina eventos **solo** tras confirmación durable del servidor.
  Future<void> removeAll(Iterable<String> eventIds);

  Future<int> count();

  Future<int> totalBytes();

  /// Eventos que deben descartarse para respetar cuotas (los menos graves y más antiguos).
  Future<List<GuardianEvent>> selectForEviction({required int eventsToDrop, required int bytesToDrop});

  Future<void> recordDiscard(GuardianDiscardRecord record);

  Future<List<GuardianDiscardRecord>> discards();

  /// Evita reinsertar el mismo patrón en ráfaga.
  Future<bool> wasRecentlyRecorded(String fingerprint, {required Duration window});

  Future<void> markRecorded(String fingerprint);
}

/// Implementación en memoria (pruebas y fallback cuando no hay sqflite).
class InMemoryGuardianStore implements GuardianStore {
  final Map<String, GuardianEvent> _events = <String, GuardianEvent>{};
  final List<GuardianDiscardRecord> _discards = <GuardianDiscardRecord>[];
  final Map<String, DateTime> _fingerprints = <String, DateTime>{};

  @override
  Future<void> init() async {}

  @override
  Future<void> upsert(GuardianEvent event) async {
    _events.putIfAbsent(event.eventId, () => event);
  }

  @override
  Future<List<GuardianEvent>> dueEvents({required int limit, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final sorted = _events.values.toList()
      ..sort((a, b) {
        final bySeverity = a.severity.compareTo(b.severity);
        if (bySeverity != 0) return bySeverity;
        return a.occurredAt.compareTo(b.occurredAt);
      });
    return sorted
        .where((event) => event.nextAttemptAtMs <= at.millisecondsSinceEpoch)
        .take(limit)
        .toList();
  }

  @override
  Future<void> markFailure(String eventId, {required int attempts, required int nextAttemptAtMs}) async {
    final current = _events[eventId];
    if (current == null) return;
    _events[eventId] = current.copyWith(attempts: attempts, nextAttemptAtMs: nextAttemptAtMs);
  }

  @override
  Future<void> removeAll(Iterable<String> eventIds) async {
    for (final id in eventIds) {
      _events.remove(id);
    }
  }

  @override
  Future<int> count() async => _events.length;

  @override
  Future<int> totalBytes() async =>
      _events.values.fold<int>(0, (sum, event) => sum + utf8.encode(event.toDbJson()).length);

  @override
  Future<List<GuardianEvent>> selectForEviction({
    required int eventsToDrop,
    required int bytesToDrop,
  }) async {
    if (eventsToDrop <= 0 && bytesToDrop <= 0) return const [];
    final sorted = _events.values.toList()
      ..sort((a, b) {
        final bySeverity = b.severity.compareTo(a.severity);
        if (bySeverity != 0) return bySeverity;
        return a.occurredAt.compareTo(b.occurredAt);
      });

    final selected = <GuardianEvent>[];
    var bytes = 0;
    for (final event in sorted) {
      if (selected.length >= eventsToDrop && bytes >= bytesToDrop) break;
      // Nunca se descarta un SEV1/SEV2 por cuota.
      if (event.severity == 'SEV1' || event.severity == 'SEV2') continue;
      selected.add(event);
      bytes += utf8.encode(event.toDbJson()).length;
    }
    return selected;
  }

  @override
  Future<void> recordDiscard(GuardianDiscardRecord record) async {
    _discards.add(record);
  }

  @override
  Future<List<GuardianDiscardRecord>> discards() async => List.unmodifiable(_discards);

  @override
  Future<bool> wasRecentlyRecorded(String fingerprint, {required Duration window}) async {
    final at = _fingerprints[fingerprint];
    if (at == null) return false;
    return DateTime.now().difference(at) < window;
  }

  @override
  Future<void> markRecorded(String fingerprint) async {
    _fingerprints[fingerprint] = DateTime.now();
  }
}
