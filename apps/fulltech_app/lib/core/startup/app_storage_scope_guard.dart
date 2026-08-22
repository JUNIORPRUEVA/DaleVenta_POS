import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/env.dart';
import '../auth/token_storage.dart';
import '../cache/cache_repair.dart';
import '../cache/fulltech_cache_manager.dart';
import '../debug/trace_log.dart';
import '../offline/offline_store.dart';
import '../utils/is_flutter_test.dart';

class AppStorageScopeGuard {
  AppStorageScopeGuard._();

  static const String _scopeKey = 'daleventas.storage.scope.v1';
  static const String _scopeVersion = 'daleventas-pos-local-scope-v2';

  static Future<void> ensureCurrentScope() async {
    if (isFlutterTest) return;

    try {
      // Recupera el índice JSON del DefaultCacheManager (avatares/facturas) si
      // quedó vacío/corrupto, ANTES de que cualquier imagen lo lea.
      await CacheInfoFileGuard.repairDefaultCacheManagerInfo();

      final prefs = await SharedPreferences.getInstance();
      final current = await _currentScope();
      final previous = prefs.getString(_scopeKey);

      if (previous == current) return;

      TraceLog.log(
        'storage_scope',
        previous == null
            ? 'initializing storage scope'
            : 'storage scope changed; clearing local session/cache',
      );

      await OfflineStore.instance.clearAll();
      await FulltechImageCacheManager.clear();
      await TokenStorage().clearTokens();
      await prefs.setString(_scopeKey, current);
    } catch (error, stackTrace) {
      TraceLog.log(
        'storage_scope',
        'scope guard failed; continuing startup',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<String> _currentScope() async {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    var packageName = 'web';

    if (!kIsWeb) {
      try {
        final info = await PackageInfo.fromPlatform();
        packageName = info.packageName.trim().isEmpty
            ? 'unknown'
            : info.packageName.trim();
      } catch (_) {
        packageName = 'unknown';
      }
    }

    return [_scopeVersion, platform, packageName, Env.apiBaseUrl].join('|');
  }
}
