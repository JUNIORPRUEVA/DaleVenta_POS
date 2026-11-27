import '../errors/api_exception.dart';

/// Shared by repositories and restart coordination; reserved only on install.
class UpdateCriticalOperationGate {
  static final instance = UpdateCriticalOperationGate();
  int _activeOperations = 0;
  bool _restartReserved = false;
  bool get hasActiveCriticalOperation => _activeOperations > 0;
  bool get restartReserved => _restartReserved;

  UpdateCriticalOperationToken beginCriticalOperation() {
    if (_restartReserved) {
      throw ApiException(
        'La aplicación está reiniciando para actualizarse. Espera un momento.',
      );
    }
    _activeOperations++;
    return UpdateCriticalOperationToken._(this);
  }

  Future<T> run<T>(Future<T> Function() body) async {
    final token = beginCriticalOperation();
    try {
      return await body();
    } finally {
      token.end();
    }
  }

  bool reserveRestart() {
    if (_activeOperations != 0 || _restartReserved) return false;
    _restartReserved = true;
    return true;
  }

  void releaseRestart() {
    _restartReserved = false;
  }
}

class UpdateCriticalOperationToken {
  UpdateCriticalOperationToken._(this._gate);
  final UpdateCriticalOperationGate _gate;
  bool _ended = false;
  void end() {
    if (_ended) return;
    _ended = true;
    _gate._activeOperations--;
  }
}
