import 'package:dio/dio.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../errors/api_exception.dart';

enum AppErrorSeverity { warning, error, fatal }

typedef AppErrorRetryCallback = Future<void> Function();

class AppErrorDetails {
  final int eventId;
  final DateTime capturedAt;
  final String title;
  final String userMessage;
  final String message;
  final String stackTrace;
  final String? context;
  final String? endpointUrl;
  final String? method;
  final String? apiResponse;
  final String? technicalDetails;
  final String errorType;
  final AppErrorSeverity severity;
  final String? retryLabel;
  final AppErrorRetryCallback? onRetry;

  const AppErrorDetails({
    required this.eventId,
    required this.capturedAt,
    required this.title,
    required this.userMessage,
    required this.message,
    required this.stackTrace,
    required this.errorType,
    required this.severity,
    this.retryLabel,
    this.onRetry,
    this.context,
    this.endpointUrl,
    this.method,
    this.apiResponse,
    this.technicalDetails,
  });

  String toConsoleString() {
    final lines = <String>[
      '[AppError][$eventId][${severity.name}] $title',
      'message: $message',
      'type: $errorType',
      if (context != null && context!.trim().isNotEmpty) 'context: $context',
      if (method != null && method!.trim().isNotEmpty) 'method: $method',
      if (endpointUrl != null && endpointUrl!.trim().isNotEmpty)
        'endpoint: $endpointUrl',
      if (technicalDetails != null && technicalDetails!.trim().isNotEmpty)
        'details: $technicalDetails',
      if (apiResponse != null && apiResponse!.trim().isNotEmpty)
        'apiResponse:\n$apiResponse',
      if (stackTrace.trim().isNotEmpty) 'stackTrace:\n$stackTrace',
    ];
    return lines.join('\n');
  }

  String toClipboardString() {
    final lines = <String>[
      'Evento: $eventId',
      'Capturado: ${capturedAt.toIso8601String()}',
      'Titulo: $title',
      'Mensaje para usuario: $userMessage',
      'Mensaje: $message',
      'Severidad: ${severity.name}',
      'Tipo: $errorType',
      if (context != null && context!.trim().isNotEmpty) 'Contexto: $context',
      if (method != null && method!.trim().isNotEmpty) 'Metodo: $method',
      if (endpointUrl != null && endpointUrl!.trim().isNotEmpty)
        'Endpoint: $endpointUrl',
      if (technicalDetails != null && technicalDetails!.trim().isNotEmpty)
        'Detalle tecnico: $technicalDetails',
      if (apiResponse != null && apiResponse!.trim().isNotEmpty)
        'Respuesta API:\n$apiResponse',
      if (stackTrace.trim().isNotEmpty) 'Stack trace:\n$stackTrace',
    ];
    return lines.join('\n\n');
  }

  String get primaryTechnicalMessage {
    final details = technicalDetails?.trim();
    if (details != null && details.isNotEmpty) {
      return details;
    }
    return message.trim();
  }
}

class AppErrorReporter {
  AppErrorReporter._();

  static final AppErrorReporter instance = AppErrorReporter._();

  int _eventSeq = 0;

  final ValueNotifier<AppErrorDetails?> lastError =
      ValueNotifier<AppErrorDetails?>(null);

  final List<AppErrorDetails> _history = <AppErrorDetails>[];
  final Map<String, DateTime> _recentDedupe = <String, DateTime>{};

  List<AppErrorDetails> get history => List.unmodifiable(_history);

  AppErrorDetails? _pendingLastError;
  bool _lastErrorUpdateScheduled = false;

  void _setLastError(AppErrorDetails? value) {
    _pendingLastError = value;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final canNotifyNow =
        phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;

    if (canNotifyNow) {
      _flushLastError();
      return;
    }

    if (_lastErrorUpdateScheduled) return;
    _lastErrorUpdateScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _lastErrorUpdateScheduled = false;
      _flushLastError();
    });
  }

  void _flushLastError() {
    final value = _pendingLastError;
    _pendingLastError = null;

    if (lastError.value == value) return;
    lastError.value = value;
  }

  void clear() => _setLastError(null);

  void record(
    Object error,
    StackTrace stack, {
    String? context,
    String? title,
    String? userMessage,
    String? technicalDetails,
    AppErrorSeverity severity = AppErrorSeverity.error,
    String? dedupeKey,
    String? retryLabel,
    AppErrorRetryCallback? onRetry,
    bool notifyUser = true,
  }) {
    if (_shouldSkipDedupe(dedupeKey)) return;
    final details = _buildDetails(
      error,
      stack,
      context: context,
      title: title,
      userMessage: userMessage,
      technicalDetails: technicalDetails,
      severity: severity,
      retryLabel: retryLabel,
      onRetry: onRetry,
    );
    _log(details);
    _remember(details);
    if (notifyUser) {
      _setLastError(details);
    }
  }

  bool _shouldSkipDedupe(String? dedupeKey) {
    final key = _clean(dedupeKey);
    if (key == null) return false;

    final now = DateTime.now();
    _recentDedupe.removeWhere(
      (_, at) => now.difference(at) > const Duration(minutes: 2),
    );
    final lastSeenAt = _recentDedupe[key];
    if (lastSeenAt != null &&
        now.difference(lastSeenAt) < const Duration(minutes: 2)) {
      return true;
    }
    _recentDedupe[key] = now;
    return false;
  }

  void _remember(AppErrorDetails details) {
    _history.insert(0, details);
    if (_history.length > 10) {
      _history.removeRange(10, _history.length);
    }
  }

  void _log(AppErrorDetails details) {
    debugPrint(details.toConsoleString());
  }

  AppErrorDetails _buildDetails(
    Object error,
    StackTrace stack, {
    String? context,
    String? title,
    String? userMessage,
    String? technicalDetails,
    required AppErrorSeverity severity,
    String? retryLabel,
    AppErrorRetryCallback? onRetry,
  }) {
    final stackText = stack.toString();
    final normalizedStack = _truncate(stackText, maxChars: 16000);
    final normalizedContext = _clean(context);
    final eventId = ++_eventSeq;
    final resolvedTitle = _clean(title) ?? _defaultTitleForSeverity(severity);
    final resolvedUserMessage =
        _clean(userMessage) ?? _defaultUserMessageForSeverity(severity);

    if (error is ApiException) {
      return AppErrorDetails(
        eventId: eventId,
        capturedAt: DateTime.now(),
        title: resolvedTitle,
        userMessage: resolvedUserMessage,
        message: error.message,
        stackTrace: normalizedStack,
        context: normalizedContext,
        endpointUrl: error.uri?.toString(),
        method: _clean(error.method),
        apiResponse: _clean(error.responseBody),
        technicalDetails:
            _clean(technicalDetails) ?? _clean(error.technicalDetails),
        errorType: error.runtimeType.toString(),
        severity: severity,
        retryLabel: _clean(retryLabel),
        onRetry: onRetry,
      );
    }

    if (error is DioException) {
      return AppErrorDetails(
        eventId: eventId,
        capturedAt: DateTime.now(),
        title: resolvedTitle,
        userMessage: resolvedUserMessage,
        message: error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : error.toString(),
        stackTrace: normalizedStack,
        context: normalizedContext,
        endpointUrl: error.requestOptions.uri.toString(),
        method: _clean(error.requestOptions.method.toUpperCase()),
        apiResponse: _clean(_stringifyApiResponse(error.response?.data)),
        technicalDetails:
            _clean(technicalDetails) ?? _clean(error.error?.toString()),
        errorType: error.runtimeType.toString(),
        severity: severity,
        retryLabel: _clean(retryLabel),
        onRetry: onRetry,
      );
    }

    return AppErrorDetails(
      eventId: eventId,
      capturedAt: DateTime.now(),
      title: resolvedTitle,
      userMessage: resolvedUserMessage,
      message: error.toString(),
      stackTrace: normalizedStack,
      context: normalizedContext,
      technicalDetails: _clean(technicalDetails),
      errorType: error.runtimeType.toString(),
      severity: severity,
      retryLabel: _clean(retryLabel),
      onRetry: onRetry,
    );
  }

  void recordFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    final stack = details.stack ?? StackTrace.current;
    final exceptionMessage = details.exceptionAsString();
    final isRenderFlexOverflow = _isRenderFlexOverflowMessage(exceptionMessage);
    final isKnownWindowsRawKeyboardStateIssue =
        _isKnownWindowsRawKeyboardStateIssue(exceptionMessage);

    if (isKnownWindowsRawKeyboardStateIssue) {
      record(
        exception,
        stack,
        context: 'FlutterError',
        title: 'Incidencia de teclado detectada',
        userMessage:
            'Se detectó una incidencia menor de teclado en Windows y fue manejada automáticamente.',
        technicalDetails: exceptionMessage,
        severity: AppErrorSeverity.warning,
        dedupeKey: 'flutter-windows-raw-keyboard-alt-left',
        notifyUser: false,
      );
      return;
    }

    record(
      exception,
      stack,
      context: 'FlutterError',
      title: isRenderFlexOverflow ? 'Incidencia visual detectada' : null,
      userMessage: isRenderFlexOverflow
          ? 'Detectamos un ajuste visual temporal en pantalla. La aplicacion puede seguir funcionando mientras corregimos el acomodo.'
          : null,
      technicalDetails: isRenderFlexOverflow ? exceptionMessage : null,
      severity: isRenderFlexOverflow
          ? AppErrorSeverity.warning
          : AppErrorSeverity.error,
      dedupeKey: isRenderFlexOverflow
          ? 'flutter-renderflex-overflow-${_normalizeOverflowMessage(exceptionMessage)}'
          : null,
      notifyUser: !isRenderFlexOverflow,
    );
  }

  bool _isRenderFlexOverflowMessage(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.startsWith('a renderflex overflowed by ');
  }

  String _normalizeOverflowMessage(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\d+'), '#')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isKnownWindowsRawKeyboardStateIssue(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains('raw_keyboard.dart') &&
        normalized.contains(
          'attempted to send a key down event when no keys are in keyspressed',
        ) &&
        normalized.contains('alt left');
  }

  String _defaultTitleForSeverity(AppErrorSeverity severity) {
    switch (severity) {
      case AppErrorSeverity.warning:
        return 'Atencion del sistema';
      case AppErrorSeverity.fatal:
        return 'No fue posible continuar';
      case AppErrorSeverity.error:
        return 'Algo salio mal';
    }
  }

  String _defaultUserMessageForSeverity(AppErrorSeverity severity) {
    switch (severity) {
      case AppErrorSeverity.warning:
        return 'Detectamos una incidencia menor. Puedes seguir usando la aplicacion mientras lo intentamos de nuevo.';
      case AppErrorSeverity.fatal:
        return 'Ocurrio un problema que impide completar esta accion en este momento.';
      case AppErrorSeverity.error:
        return 'No pudimos completar la accion. Intentalo nuevamente en unos segundos.';
    }
  }

  String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String _truncate(String value, {required int maxChars}) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}\n…';
  }

  String? _stringifyApiResponse(dynamic data) {
    if (data == null) return null;
    final raw = data is String ? data : data.toString();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return _truncate(trimmed, maxChars: 6000);
  }
}
