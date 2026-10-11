import 'dart:async';

import 'package:daleventa_pos/core/app_update/app_update_models.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence.dart';
import 'package:daleventa_pos/core/app_update/app_update_persistence_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('save serializes concurrent writes to the update state file', () async {
    final store = _SlowUpdateStateStore();
    final persistence = UpdatePersistence(store);
    final first = PersistedUpdateState.initial().copyWith(
      phase: AppUpdatePhase.downloading,
      targetBuild: 135,
      bytesDownloaded: 1,
    );
    final second = first.copyWith(bytesDownloaded: 2);

    final firstSave = persistence.save(first);
    final secondSave = persistence.save(second);

    await Future<void>.delayed(Duration.zero);
    expect(store.inFlight, 1);
    store.releaseOne();
    await firstSave;

    await Future<void>.delayed(Duration.zero);
    expect(store.maxInFlight, 1);
    expect(store.inFlight, 1);
    store.releaseOne();
    await secondSave;

    expect(store.maxInFlight, 1);
    expect(store.writes.map((json) => json['bytesDownloaded']), [1, 2]);
  });
}

class _SlowUpdateStateStore extends UpdateStateFileStore {
  final writes = <Map<String, dynamic>>[];
  final _pending = <Completer<void>>[];
  var inFlight = 0;
  var maxInFlight = 0;

  @override
  Future<void> writeJson(Map<String, dynamic> json) async {
    inFlight += 1;
    maxInFlight = maxInFlight < inFlight ? inFlight : maxInFlight;
    final completer = Completer<void>();
    _pending.add(completer);
    await completer.future;
    writes.add(Map<String, dynamic>.from(json));
    inFlight -= 1;
  }

  void releaseOne() {
    final pending = _pending.removeAt(0);
    pending.complete();
  }
}
