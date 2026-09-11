import 'dart:developer' as dev;

/// Trazador de rendimiento OPT-IN para flujos críticos del POS
/// (crear/seleccionar ticket, guardar venta, post-venta).
///
/// Se activa compilando con:
///
/// ```
/// flutter run --dart-define=PERF_TRACE=true
/// ```
///
/// Sin ese define, `PerfTrace.begin()` devuelve `null` y **todos** los sitios
/// de instrumentación son no-ops: cero Stopwatch, cero `Timeline`, cero logs.
/// Por eso es seguro dejarlo instrumentado en el código productivo.
///
/// Los eventos se publican en el timeline de Flutter DevTools (categoría
/// `fullpos.perf`) y además se registran por `dart:developer` para poder
/// leerlos en la consola/observatory. No se envían a ningún backend y no
/// incluyen datos personales ni `companyId`.
class PerfTrace {
  PerfTrace._(this._name, this._startedAtUs);

  /// `true` solo si el binario se compiló con `--dart-define=PERF_TRACE=true`.
  static const bool enabled = bool.fromEnvironment('PERF_TRACE');

  static const String _category = 'fullpos.perf';

  final String _name;
  final int _startedAtUs;
  final List<String> _steps = <String>[];
  int _lastUs = 0;
  bool _finished = false;

  /// Inicia una traza nombrada. Devuelve `null` cuando la instrumentación está
  /// apagada (release normal), de modo que el llamador usa `trace?.step(...)`.
  static PerfTrace? begin(String name) {
    if (!enabled) return null;
    final startedAtUs = _nowUs();
    final trace = PerfTrace._(name, startedAtUs).._lastUs = startedAtUs;
    dev.Timeline.startSync(name, arguments: const {'cat': _category});
    return trace;
  }

  /// Marca una fase intermedia. `step` puede llamarse varias veces; cada marca
  /// registra el tiempo desde la marca anterior y el acumulado.
  void step(String label) {
    if (!enabled || _finished) return;
    final nowUs = _nowUs();
    final deltaMs = (nowUs - _lastUs) / 1000.0;
    final totalMs = (nowUs - _startedAtUs) / 1000.0;
    _lastUs = nowUs;
    _steps.add('$label=+${deltaMs.toStringAsFixed(1)}ms');
    dev.Timeline.instantSync(
      '$_name.$label',
      arguments: const {'cat': _category},
    );
    dev.log(
      '[PERF] $_name.$label +${deltaMs.toStringAsFixed(1)}ms '
      'total=${totalMs.toStringAsFixed(1)}ms',
      name: 'PerfTrace',
    );
  }

  /// Cierra la traza y emite el resumen de una línea con todas las fases.
  void finish({String? outcome}) {
    if (!enabled || _finished) return;
    _finished = true;
    final totalMs = (_nowUs() - _startedAtUs) / 1000.0;
    dev.Timeline.finishSync();
    dev.log(
      '[PERF] $_name.total=${totalMs.toStringAsFixed(1)}ms'
      '${outcome == null ? '' : ' outcome=$outcome'}'
      ' ${_steps.join(' ')}',
      name: 'PerfTrace',
    );
  }

  static int _nowUs() => DateTime.now().microsecondsSinceEpoch;
}
