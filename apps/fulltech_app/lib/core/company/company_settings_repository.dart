import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_repository.dart';
import '../cache/local_json_cache.dart';
import '../debug/trace_log.dart';
import '../errors/api_exception.dart';
import '../offline/sync_queue_service.dart';
import 'company_settings_model.dart';

final companySettingsRepositoryProvider = Provider<CompanySettingsRepository>((
  ref,
) {
  final repository = CompanySettingsRepository(
    ref.watch(dioProvider),
    ref.read(syncQueueServiceProvider.notifier),
  );
  repository.registerSyncHandlers();
  return repository;
});

final companySettingsProvider = FutureProvider<CompanySettings>((ref) async {
  return ref.watch(companySettingsRepositoryProvider).getSettings();
});

class AdminAuthorizationVerification {
  const AdminAuthorizationVerification({
    required this.duration,
    required this.token,
  });

  final Duration duration;
  final String token;
}

class CompanySettingsRepository {
  final Dio _dio;
  static const Duration _settingsTimeout = Duration(seconds: 20);
  static const String _cacheKey = 'company_settings_cache_v1';
  static const String _saveSyncType = 'settings.save';

  final LocalJsonCache _cache = LocalJsonCache();
  final SyncQueueService _syncQueue;

  bool _handlersRegistered = false;

  CompanySettingsRepository(this._dio, this._syncQueue);

  void registerSyncHandlers() {
    if (_handlersRegistered) return;
    _handlersRegistered = true;
    _syncQueue.registerHandler(_saveSyncType, (payload) async {
      final settings = CompanySettings.fromMap(
        ((payload['settings'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      );
      await _saveSettingsRemote(settings);
    });
  }

  bool _shouldQueueSync(ApiException error) {
    final code = error.code;
    return code == null || code >= 500;
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final normalized = message
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (normalized.isNotEmpty) return normalized.join(' | ');
      }
    }
    return fallback;
  }

  Map<String, dynamic> _normalizeMap(dynamic data, String fallbackMessage) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    throw ApiException(fallbackMessage);
  }

  CompanySettings _settingsFromData(dynamic data) {
    return CompanySettings.fromMap(
      _normalizeMap(
        data,
        'La API devolvió una configuración inválida. Inténtalo de nuevo.',
      ),
    );
  }

  void _traceProtectedError(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    TraceLog.log(
      'company_settings',
      message,
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<CompanySettings?> getCachedSettings() async {
    try {
      final cached = await _cache.readMap(
        _cacheKey,
        maxAge: const Duration(days: 14),
      );
      if (cached == null) return null;
      return CompanySettings.fromMap(cached);
    } catch (error, stackTrace) {
      _traceProtectedError(
        'cached settings could not be parsed',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Future<CompanySettings> getSettingsRemoteAndCache() async {
    try {
      final res = await _dio
          .get(
            ApiRoutes.settings,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_settingsTimeout);
      final settings = _settingsFromData(res.data);
      await _cache.writeMap(_cacheKey, settings.toMap());
      return settings;
    } on TimeoutException {
      throw ApiException(
        'La configuración tardó demasiado en cargar. Inténtalo de nuevo.',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return CompanySettings.empty();
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo cargar configuración'),
        e.response?.statusCode,
      );
    } on ApiException {
      rethrow;
    } catch (error, stackTrace) {
      _traceProtectedError(
        'remote settings response could not be parsed',
        error,
        stackTrace,
      );
      return CompanySettings.empty();
    }
  }

  Future<CompanySettings> getSettings() async {
    final cached = await getCachedSettings();
    if (cached != null) {
      unawaited(
        getSettingsRemoteAndCache().catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          _traceProtectedError(
            'background settings refresh failed',
            error,
            stackTrace,
          );
          return cached;
        }),
      );
      return cached;
    }
    try {
      return await getSettingsRemoteAndCache();
    } catch (error, stackTrace) {
      _traceProtectedError('settings load failed', error, stackTrace);
      return CompanySettings.empty();
    }
  }

  Future<void> _saveSettingsRemote(CompanySettings settings) async {
    try {
      final payload = <String, dynamic>{
        'companyName': settings.companyName,
        'rnc': settings.rnc,
        'phone': settings.phone,
        'phonePreferential': settings.phonePreferential,
        'address': settings.address,
        'description': settings.description,
        'instagramUrl': settings.instagramUrl,
        'facebookUrl': settings.facebookUrl,
        'websiteUrl': settings.websiteUrl,
        'gpsLocationUrl': settings.gpsLocationUrl,
        'businessHours': settings.businessHours,
        'bankAccounts': settings.bankAccounts
            .map((entry) => entry.toMap())
            .toList(),
        'legalRepresentativeName': settings.legalRepresentativeName,
        'legalRepresentativeCedula': settings.legalRepresentativeCedula,
        'legalRepresentativeRole': settings.legalRepresentativeRole,
        'legalRepresentativeNationality':
            settings.legalRepresentativeNationality,
        'legalRepresentativeCivilStatus':
            settings.legalRepresentativeCivilStatus,
        'logoBase64': settings.logoBase64,
        'evolutionApiBaseUrl': settings.evolutionApiBaseUrl,
        'evolutionApiInstanceName': settings.evolutionApiInstanceName,
        'whatsappWebhookEnabled': settings.whatsappWebhookEnabled,
      };
      if (settings.openAiApiKey.trim().isNotEmpty) {
        payload['openAiApiKey'] = settings.openAiApiKey.trim();
      }
      if (settings.evolutionApiApiKey.trim().isNotEmpty) {
        payload['evolutionApiApiKey'] = settings.evolutionApiApiKey.trim();
      }

      await _dio
          .patch(
            ApiRoutes.settings,
            options: Options(extra: const {'skipLoader': true}),
            data: payload,
          )
          .timeout(_settingsTimeout);
    } on TimeoutException {
      throw ApiException(
        'Guardar la configuración tardó demasiado. El backend no respondió a tiempo.',
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw ApiException(
          'La API en nube aún no tiene /settings desplegado. Actualiza el backend para guardar configuración global.',
          e.response?.statusCode,
        );
      }
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar configuración'),
        e.response?.statusCode,
      );
    }
  }

  Future<bool> saveSettingsOrQueue(CompanySettings settings) async {
    await _cache.writeMap(_cacheKey, settings.toMap());
    try {
      await _saveSettingsRemote(settings);
      return false;
    } on ApiException catch (e) {
      if (!_shouldQueueSync(e)) rethrow;
      await _syncQueue.enqueue(
        id: _saveSyncType,
        type: _saveSyncType,
        scope: 'global',
        payload: {'settings': settings.toMap()},
      );
      return true;
    }
  }

  Future<void> setAdminAuthorizationPin(String pin) async {
    try {
      await _dio
          .post(
            ApiRoutes.settingsAdminPin,
            options: Options(extra: const {'skipLoader': true}),
            data: {'pin': pin},
          )
          .timeout(_settingsTimeout);
      final cached = await getCachedSettings();
      if (cached != null) {
        await _cache.writeMap(
          _cacheKey,
          cached.copyWith(hasAdminAuthorizationPin: true).toMap(),
        );
      }
    } on TimeoutException {
      throw ApiException('Guardar el PIN tardó demasiado. Inténtalo de nuevo.');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo guardar el PIN'),
        e.response?.statusCode,
      );
    }
  }

  Future<AdminAuthorizationVerification> verifyAdminAuthorizationPin(
    String pin,
  ) async {
    try {
      final res = await _dio
          .post(
            ApiRoutes.settingsAdminPinVerify,
            options: Options(extra: const {'skipLoader': true}),
            data: {'pin': pin},
          )
          .timeout(_settingsTimeout);
      final data = _normalizeMap(
        res.data,
        'La API devolvió una autorización inválida',
      );
      final seconds = data['expiresInSeconds'];
      final token = data['adminAuthorizationToken'];
      if (token is! String || token.trim().isEmpty) {
        throw ApiException('La API no devolvió autorización administrativa');
      }
      return AdminAuthorizationVerification(
        duration: Duration(seconds: seconds is num ? seconds.toInt() : 600),
        token: token,
      );
    } on TimeoutException {
      throw ApiException(
        'La autorización tardó demasiado. Inténtalo de nuevo.',
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo autorizar la acción'),
        e.response?.statusCode,
      );
    }
  }

  /// POST /whatsapp/admin/sync-webhooks — reconfigures webhooks for all user instances.
  Future<void> syncWhatsappWebhooks({required bool enabled}) async {
    try {
      await _dio
          .post(
            '/whatsapp/admin/sync-webhooks',
            data: {'enabled': enabled},
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_settingsTimeout);
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo sincronizar los webhooks',
        ),
        e.response?.statusCode,
      );
    }
  }
}
