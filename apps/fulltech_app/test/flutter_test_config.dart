import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/storage/serialized_secure_storage.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Each widget test owns a separate fake-async zone. Native storage jobs from
  // a disposed fixture must not carry its scheduler into the next fixture.
  setUp(SerializedSecureStorage.resetForTesting);
  await testMain();
}
