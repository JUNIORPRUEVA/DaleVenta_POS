import '../auth/token_storage.dart';
import '../debug/trace_log.dart';
import '../offline/offline_store.dart';
import '../utils/is_flutter_test.dart';

class LocalJsonCache {
  static const String _prefix = 'ft_cache:';

  final OfflineStore _store = OfflineStore.instance;
  final TokenStorage _tokenStorage = TokenStorage();

  Future<String> _key(String key) async {
    if (isFlutterTest) return '${_prefix}default:$key';

    var companyId = 'default';
    try {
      final user = await _tokenStorage.getUserSnapshot();
      final value = user?.companyId?.trim() ?? '';
      if (value.isNotEmpty) companyId = value;
    } catch (_) {
      companyId = 'default';
    }
    return '$_prefix$companyId:$key';
  }

  Future<Map<String, dynamic>?> readMap(String key, {Duration? maxAge}) async {
    try {
      final value = await _store.readCacheEntry(
        await _key(key),
        maxAge: maxAge,
      );
      TraceLog.log(
        'cache',
        value == null ? 'cache miss key=$key' : 'cache hit key=$key',
      );
      return value;
    } catch (error, stackTrace) {
      TraceLog.log(
        'cache',
        'cache read error key=$key',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) async {
    TraceLog.log('cache', 'cache write key=$key');
    await _store.writeCacheEntry(await _key(key), value);
  }

  Future<void> remove(String key) async {
    TraceLog.log('cache', 'cache remove key=$key');
    await _store.removeCacheEntry(await _key(key));
  }
}
