import 'package:flutter/material.dart';

/// Estado de una tarea del onboarding de activación.
///
/// El backend nunca envía `DONE` por una acción del usuario: `DONE` significa
/// que los datos reales de la empresa ya cumplen la condición (hay productos,
/// hay ventas, hay logo...). `SKIPPED` es una omisión explícita y NO cuenta
/// como completada.
enum ActivationTaskState {
  done,
  skipped,
  pending;

  static ActivationTaskState fromApi(String? raw) {
    switch ((raw ?? '').toUpperCase()) {
      case 'DONE':
        return ActivationTaskState.done;
      case 'SKIPPED':
        return ActivationTaskState.skipped;
      default:
        return ActivationTaskState.pending;
    }
  }

  bool get isResolved => this != ActivationTaskState.pending;
}

@immutable
class ActivationTask {
  const ActivationTask({
    required this.key,
    required this.phase,
    required this.title,
    required this.description,
    this.detail,
    required this.minutes,
    required this.actionLabel,
    required this.destination,
    required this.icon,
    required this.optional,
    required this.tourSteps,
    required this.tourStep,
    required this.tourSeen,
    required this.state,
  });

  final String key;
  final String phase;
  final String title;
  final String description;

  /// Etapa concreta cuando la tarea tiene subprocesos (hoy: facturación
  /// electrónica → configuración, habilitación DGII o certificación).
  final String? detail;
  final int minutes;
  final String actionLabel;

  /// Clave semántica de destino que el cliente traduce a su propia ruta.
  final String destination;
  final String icon;
  final bool optional;
  final int tourSteps;
  final int tourStep;
  final bool tourSeen;
  final ActivationTaskState state;

  bool get isDone => state == ActivationTaskState.done;
  bool get isSkipped => state == ActivationTaskState.skipped;
  bool get isPending => state == ActivationTaskState.pending;

  /// Una tarea omitida no se puede "abrir": no hay nada que hacer en ella.
  bool get canOpen => state != ActivationTaskState.skipped;

  factory ActivationTask.fromJson(Map<String, dynamic> json) {
    return ActivationTask(
      key: (json['key'] ?? '').toString(),
      phase: (json['phase'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      detail: (json['detail'] as String?)?.trim().isNotEmpty == true
          ? json['detail'].toString().trim()
          : null,
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      actionLabel: (json['actionLabel'] ?? 'Empezar').toString(),
      destination: (json['destination'] ?? '').toString(),
      icon: (json['icon'] ?? 'check').toString(),
      optional: json['optional'] == true,
      tourSteps: (json['tourSteps'] as num?)?.toInt() ?? 0,
      tourStep: (json['tourStep'] as num?)?.toInt() ?? 0,
      tourSeen: json['tourSeen'] == true,
      state: ActivationTaskState.fromApi(json['state']?.toString()),
    );
  }
}

@immutable
class ActivationPhase {
  const ActivationPhase({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.total,
    required this.done,
    required this.skipped,
    required this.resolved,
    required this.complete,
    required this.tasks,
  });

  final String key;
  final String title;
  final String subtitle;
  final int total;
  final int done;
  final int skipped;
  final int resolved;
  final bool complete;
  final List<ActivationTask> tasks;

  factory ActivationPhase.fromJson(Map<String, dynamic> json) {
    final rawTasks = json['tasks'];
    return ActivationPhase(
      key: (json['key'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      done: (json['done'] as num?)?.toInt() ?? 0,
      skipped: (json['skipped'] as num?)?.toInt() ?? 0,
      resolved: (json['resolved'] as num?)?.toInt() ?? 0,
      complete: json['complete'] == true,
      tasks: rawTasks is List
          ? rawTasks
                .whereType<Map>()
                .map(
                  (item) => ActivationTask.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <ActivationTask>[],
    );
  }
}

@immutable
class ActivationState {
  const ActivationState({
    required this.companyId,
    required this.required,
    required this.welcomeSeen,
    required this.dismissed,
    required this.allResolved,
    required this.total,
    required this.done,
    required this.skipped,
    required this.pending,
    required this.percent,
    required this.phases,
    required this.tasks,
    this.nextTaskKey,
  });

  final String companyId;

  /// Gate legacy de onboarding (empresas nuevas vs. existentes).
  final bool required;
  final bool welcomeSeen;
  final bool dismissed;
  final bool allResolved;
  final int total;
  final int done;
  final int skipped;
  final int pending;
  final int percent;
  final List<ActivationPhase> phases;
  final List<ActivationTask> tasks;
  final String? nextTaskKey;

  ActivationTask? get nextTask {
    final key = nextTaskKey;
    if (key == null) return null;
    for (final task in tasks) {
      if (task.key == key) return task;
    }
    return null;
  }

  /// Muestra la bienvenida solo la primera vez y solo si queda algo por hacer.
  bool get shouldWelcome => !welcomeSeen && !allResolved;

  /// El panel se abre automáticamente una vez; después queda el acceso visible.
  bool get shouldAutoOpen => !dismissed && !allResolved;

  factory ActivationState.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'];
    final progressMap =
        progress is Map ? progress.cast<String, dynamic>() : const {};
    final rawPhases = json['phases'];
    final rawTasks = json['tasks'];
    return ActivationState(
      companyId: (json['companyId'] ?? '').toString(),
      required: json['required'] == true,
      welcomeSeen: json['welcomeSeen'] == true,
      dismissed: json['dismissed'] == true,
      allResolved: json['allResolved'] == true,
      total: (progressMap['total'] as num?)?.toInt() ?? 0,
      done: (progressMap['done'] as num?)?.toInt() ?? 0,
      skipped: (progressMap['skipped'] as num?)?.toInt() ?? 0,
      pending: (progressMap['pending'] as num?)?.toInt() ?? 0,
      percent: (progressMap['percent'] as num?)?.toInt() ?? 0,
      phases: rawPhases is List
          ? rawPhases
                .whereType<Map>()
                .map(
                  (item) =>
                      ActivationPhase.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <ActivationPhase>[],
      tasks: rawTasks is List
          ? rawTasks
                .whereType<Map>()
                .map(
                  (item) => ActivationTask.fromJson(item.cast<String, dynamic>()),
                )
                .toList(growable: false)
          : const <ActivationTask>[],
      nextTaskKey: (json['nextTaskKey'] as String?)?.trim().isEmpty == false
          ? json['nextTaskKey'].toString()
          : null,
    );
  }
}
