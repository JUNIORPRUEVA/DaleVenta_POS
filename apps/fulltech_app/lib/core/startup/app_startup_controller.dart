import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/contabilidad/contabilidad_init.dart';
import '../api/env.dart';
import '../debug/trace_log.dart';

enum AppStartupPhase { critical, ready, failed }

class AppStartupState {
  final AppStartupPhase phase;
  final String title;
  final String? subtitle;
  final String? statusLabel;
  final String? errorMessage;
  final int elapsedMs;

  const AppStartupState({
    required this.phase,
    required this.title,
    this.subtitle,
    this.statusLabel,
    this.errorMessage,
    this.elapsedMs = 0,
  });

  factory AppStartupState.initial() {
    return const AppStartupState(
      phase: AppStartupPhase.critical,
      title: 'Iniciando FullPOS Cloud...',
      subtitle:
          'Preparando la configuración básica para abrir la app sin bloquear la interfaz.',
      statusLabel: 'Primer render',
    );
  }

  AppStartupState copyWith({
    AppStartupPhase? phase,
    String? title,
    String? subtitle,
    String? statusLabel,
    String? errorMessage,
    int? elapsedMs,
    bool clearError = false,
  }) {
    return AppStartupState(
      phase: phase ?? this.phase,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      statusLabel: statusLabel ?? this.statusLabel,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }

  bool get isReady => phase == AppStartupPhase.ready;

  bool get hasError => phase == AppStartupPhase.failed;
}

final appStartupProvider =
    StateNotifierProvider<AppStartupController, AppStartupState>((ref) {
      return AppStartupController();
    });

Future<void>? _prepareAppFirstFrameFuture;

Future<void> prepareAppFirstFrame() {
  if (_prepareAppFirstFrameFuture != null) {
    return _prepareAppFirstFrameFuture!;
  }

  late final Future<void> future;
  future = _prepareAppFirstFrame().whenComplete(() {
    if (identical(_prepareAppFirstFrameFuture, future)) {
      _prepareAppFirstFrameFuture = future;
    }
  });
  _prepareAppFirstFrameFuture = future;
  return future;
}

class AppStartupController extends StateNotifier<AppStartupState> {
  AppStartupController() : super(AppStartupState.initial());

  Future<void>? _startFuture;

  Future<void> retry() {
    state = AppStartupState.initial();
    return start(force: true);
  }

  Future<void> start({bool force = false}) {
    if (!force && _startFuture != null) {
      return _startFuture!;
    }

    late final Future<void> future;
    future = _runStartup().whenComplete(() {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    });
    _startFuture = future;
    return future;
  }

  Future<void> _runStartup() async {
    final seq = TraceLog.nextSeq();
    final stopwatch = Stopwatch()..start();
    TraceLog.log('Startup', 'critical startup begin', seq: seq);

    try {
      await _runStep(
        seq: seq,
        title: 'Cargando configuración…',
        subtitle: 'Resolviendo variables de entorno y base URL del backend.',
        statusLabel: 'Configuración',
        timeout: const Duration(seconds: 3),
        action: _ensureEnvLoaded,
      );

      await _runStep(
        seq: seq,
        title: 'Preparando formato regional…',
        subtitle:
            'Inicializando locale y formato de fechas antes de entrar a los módulos.',
        statusLabel: 'Locale',
        timeout: const Duration(seconds: 4),
        action: ensureContabilidadLocale,
      );

      stopwatch.stop();
      state = state.copyWith(
        phase: AppStartupPhase.ready,
        title: 'FullPOS Cloud listo',
        subtitle:
            'La aplicación ya puede mostrarse. Las verificaciones secundarias siguen en background.',
        statusLabel: 'OK',
        elapsedMs: stopwatch.elapsedMilliseconds,
        clearError: true,
      );
      TraceLog.log(
        'Startup',
        'critical startup ready (${stopwatch.elapsedMilliseconds}ms)',
        seq: seq,
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      state = state.copyWith(
        phase: AppStartupPhase.failed,
        title: 'No se pudo iniciar FullPOS Cloud',
        subtitle:
            'La configuración crítica falló antes de abrir la app. Puedes reintentar sin recargar manualmente.',
        statusLabel: 'Error de startup',
        errorMessage: error.toString(),
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
      TraceLog.log(
        'Startup',
        'critical startup failed',
        seq: seq,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _runStep({
    required int seq,
    required String title,
    required String subtitle,
    required String statusLabel,
    required Duration timeout,
    required Future<void> Function() action,
  }) async {
    state = state.copyWith(
      phase: AppStartupPhase.critical,
      title: title,
      subtitle: subtitle,
      statusLabel: statusLabel,
      clearError: true,
    );

    final sw = Stopwatch()..start();
    TraceLog.log('Startup', '$statusLabel start', seq: seq);
    await action().timeout(timeout);
    sw.stop();
    TraceLog.log(
      'Startup',
      '$statusLabel done (${sw.elapsedMilliseconds}ms)',
      seq: seq,
    );
  }
}

Future<void> _prepareAppFirstFrame() async {
  final seq = TraceLog.nextSeq();
  final stopwatch = Stopwatch()..start();
  TraceLog.log('Startup', 'prepare first frame begin', seq: seq);

  try {
    await _ensureEnvLoaded();
  } catch (error, stackTrace) {
    TraceLog.log(
      'Startup',
      'prepare first frame env failed',
      seq: seq,
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    await ensureContabilidadLocale().timeout(const Duration(seconds: 4));
  } catch (error, stackTrace) {
    TraceLog.log(
      'Startup',
      'prepare first frame locale failed',
      seq: seq,
      error: error,
      stackTrace: stackTrace,
    );
  }

  stopwatch.stop();
  TraceLog.log(
    'Startup',
    'prepare first frame done (${stopwatch.elapsedMilliseconds}ms)',
    seq: seq,
  );
}

Future<void> _ensureEnvLoaded() async {
  const candidates = <String>[
    '.env',
    'assets/.env',
    '.env.example',
    'assets/.env.example',
  ];

  var loaded = false;
  for (final file in candidates) {
    try {
      await dotenv.load(fileName: file);
      loaded = true;
      debugPrint('Loaded env file: $file');
      break;
    } on Object catch (error) {
      debugPrint('Could not load $file: $error');
    }
  }

  if (!loaded) {
    debugPrint('No env file could be loaded. Using runtime/fallback config.');
  }

  // SharedPreferences (Windows) stores data in `<AppSupport>/shared_preferences.json`.
  // If that JSON gets corrupted, any access can throw FormatException and break
  // multiple modules (auth tokens, manual "seenAt", settings cache, etc.).
  await _repairSharedPreferencesIfCorrupted();

  // Extra diagnostics in debug/profile to avoid confusion when testing locally
  // (eg. Windows desktop) but targeting a cloud API.
  if (!kReleaseMode) {
    const defineBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    const defineTimeout = String.fromEnvironment(
      'API_TIMEOUT_MS',
      defaultValue: '',
    );
    final dotenvBaseUrl = (dotenv.env['API_BASE_URL'] ?? '').trim();
    final dotenvTimeout = (dotenv.env['API_TIMEOUT_MS'] ?? '').trim();

    debugPrint(
      'Env sources: '
      'dart-define(API_BASE_URL)="${defineBaseUrl.isEmpty ? '(empty)' : defineBaseUrl}", '
      'dotenv(API_BASE_URL)="${dotenvBaseUrl.isEmpty ? '(empty)' : dotenvBaseUrl}"',
    );
    debugPrint(
      'Env sources: '
      'dart-define(API_TIMEOUT_MS)="${defineTimeout.isEmpty ? '(empty)' : defineTimeout}", '
      'dotenv(API_TIMEOUT_MS)="${dotenvTimeout.isEmpty ? '(empty)' : dotenvTimeout}"',
    );
  }

  try {
    final baseUrl = Env.apiBaseUrl;
    debugPrint('API_BASE_URL: $baseUrl');
  } on Object catch (error) {
    debugPrint('Invalid API_BASE_URL configuration: $error');
  }
}

Future<void> _repairSharedPreferencesIfCorrupted() async {
  // Only attempt filesystem repair on IO platforms.
  if (kIsWeb) return;

  try {
    await SharedPreferences.getInstance();
    return;
  } on FormatException catch (e) {
    debugPrint('SharedPreferences corrupted: $e');
  } catch (_) {
    // Non-format errors: don't try to delete files.
    return;
  }

  try {
    final dir = await getApplicationSupportDirectory();
    final prefsPath = p.join(dir.path, 'shared_preferences.json');
    final file = File(prefsPath);
    if (await file.exists()) {
      await file.delete();
      debugPrint('Deleted corrupted SharedPreferences file: $prefsPath');
    }
  } catch (e) {
    debugPrint('Failed to delete corrupted SharedPreferences file: $e');
  }

  // Retry once (will recreate a clean file).
  try {
    await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('SharedPreferences repair retry failed: $e');
  }
}
