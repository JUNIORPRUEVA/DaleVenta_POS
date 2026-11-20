import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/storage/serialized_secure_storage.dart';

void main() {
  test('concurrent encrypted-map read/write cycles retain every caller key', () async {
    var persisted = <String, String>{};
    await Future.wait(List.generate(30, (index) => SerializedSecureStorage.serialize(() async {
      final loaded = Map<String, String>.from(persisted);
      await Future<void>.delayed(Duration.zero);
      loaded['key-$index'] = 'synthetic-$index';
      persisted = loaded;
    })));
    expect(persisted.length, 30);
    for (var index = 0; index < 30; index++) {
      expect(persisted['key-$index'], 'synthetic-$index');
    }
  });
  test('a native failure does not block subsequent storage access', () async {
    await expectLater(SerializedSecureStorage.serialize(() async => throw StateError('synthetic failure')),
      throwsStateError);
    expect(await SerializedSecureStorage.serialize(() async => 'later-key'), 'later-key');
  });
  test('caller timeout cannot overlap unfinished native I/O', () async {
    final release = Completer<void>();
    var secondStarted = false;
    final first = SerializedSecureStorage.serialize(() => release.future);
    await expectLater(first.timeout(Duration.zero), throwsA(isA<TimeoutException>()));
    final second = SerializedSecureStorage.serialize(() async { secondStarted = true; });
    await Future<void>.delayed(Duration.zero);
    expect(secondStarted, isFalse);
    release.complete();
    await second;
    expect(secondStarted, isTrue);
  });
}
