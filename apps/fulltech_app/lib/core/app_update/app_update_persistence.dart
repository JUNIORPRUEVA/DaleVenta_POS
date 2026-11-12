import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/trace_log.dart';
import 'app_update_models.dart';
import 'app_update_persistence_store.dart';

final updatePersistenceProvider = Provider<UpdatePersistence>((ref) {
  return UpdatePersistence(const UpdateStateFileStore());
});

class UpdatePersistence {
  UpdatePersistence(this._store);

  final UpdateStateFileStore _store;
  Future<void> _lastSave = Future<void>.value();

  Future<PersistedUpdateState> load() async {
    try {
      final json = await _store.readJson();
      if (json == null) return PersistedUpdateState.initial();
      return PersistedUpdateState.fromJson(json).normalizeForStartup();
    } catch (_) {
      return PersistedUpdateState.initial().copyWith(
        lastErrorCode: 'STATE_READ_FAILED',
      );
    }
  }

  Future<void> save(PersistedUpdateState state) {
    final nextSave = _lastSave
        .catchError((_) {
          return null;
        })
        .then((_) => _store.writeJson(state.toJson()))
        // La persistencia del actualizador NUNCA propaga.
        //
        // Si el almacenamiento no se puede resolver (por ejemplo una build UAT
        // sin `DALEVENTAS_POS_ROOT`, que falla cerrada a propósito), el fallo
        // ocurría **dentro del propio `catch`** que intenta guardar el estado y
        // escapaba hasta el manejador global de errores: la comprobación de
        // actualizaciones terminaba mostrando un aviso técnico al cliente.
        // Guardar el estado es diagnóstico, no una operación de negocio.
        .catchError((Object error, StackTrace stackTrace) {
          try {
            TraceLog.log(
              'AppUpdate',
              'persist failed (aislado, sin propagar)',
              error: error,
              stackTrace: stackTrace,
            );
          } catch (_) {
            // Ignorado a propósito: ni el log puede romper el flujo.
          }
        });
    _lastSave = nextSave;
    return nextSave;
  }
}
