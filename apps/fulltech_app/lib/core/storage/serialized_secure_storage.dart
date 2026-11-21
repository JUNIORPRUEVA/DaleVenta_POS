import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

/// The Windows plugin reads and rewrites one encrypted map per operation.
/// Concurrent callers can otherwise read a partially written file or replace
/// another caller's keys. Keep encryption and existing plugin options intact.
class SerializedSecureStorage {
  const SerializedSecureStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static Future<void> _tail = Future<void>.value();

  /// Widget tests replace the entire mock storage backend between fake-async
  /// zones. Futures from a disposed test zone must not enter the next fixture.
  @visibleForTesting
  static void resetForTesting() {
    assert(() {
      _tail = Future<void>.value();
      return true;
    }());
  }

  static Future<T> serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    // A caller's timeout does not release the queue while native I/O is active.
    // A failed operation must not permanently poison later access.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String?> read({required String key}) =>
      serialize(() => _storage.read(key: key));
  Future<void> write({required String key, required String? value}) =>
      serialize(() => _storage.write(key: key, value: value));
  Future<void> delete({required String key}) =>
      serialize(() => _storage.delete(key: key));
}
