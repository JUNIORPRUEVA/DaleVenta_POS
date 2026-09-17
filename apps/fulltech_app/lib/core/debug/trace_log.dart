import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

import 'trace_log_sink_stub.dart' if (dart.library.io) 'trace_log_sink_io.dart';

class TraceLog {
  static int _seq = 0;

  static int nextSeq() => ++_seq;

  static void log(
    String scope,
    String message, {
    int? seq,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final id = seq ?? nextSeq();
    final ts = DateTime.now().toIso8601String();
    final base = '[TRACE][$id][$ts][$scope] $message';

    TraceLogSink.write(base);

    if (kDebugMode) {
      if (error != null) {
        dev.log(base, name: 'TraceLog', error: error, stackTrace: stackTrace);
        return;
      }

      dev.log(base, name: 'TraceLog');
    }
  }
}
