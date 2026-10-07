import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_update_models.dart';
import 'app_update_persistence_store.dart';

final updatePersistenceProvider = Provider<UpdatePersistence>((ref) {
  return UpdatePersistence(const UpdateStateFileStore());
});

class UpdatePersistence {
  const UpdatePersistence(this._store);

  final UpdateStateFileStore _store;

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
    return _store.writeJson(state.toJson());
  }
}
