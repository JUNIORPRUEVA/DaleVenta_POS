import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_connectivity_interceptor.dart';
import '../api/api_diagnostics_interceptor.dart';
import '../api/api_error_mapper.dart';
import '../api/api_offline_cache_interceptor.dart';
import '../api/api_retry_interceptor.dart';
import '../api/api_routes.dart';
import '../errors/api_exception.dart';
import '../models/user_model.dart';
import '../network/network_reachability.dart';
import '../offline/sync_queue_service.dart';
import '../utils/is_flutter_test.dart';
import 'admin_authorization_session.dart';
import 'auth_interceptor.dart';
import 'auth_session_events.dart';
import 'token_storage.dart';
import '../loading/app_loading_controller.dart';
import '../loading/loading_interceptor.dart';

enum SessionVerificationStatus { authenticated, invalid, deferred }

class HydratedSession {
  final bool hasToken;
  final UserModel? user;

  const HydratedSession({required this.hasToken, this.user});

  const HydratedSession.empty() : this(hasToken: false);
}

class SessionVerificationResult {
  final SessionVerificationStatus status;
  final UserModel? user;

  const SessionVerificationResult({required this.status, this.user});

  const SessionVerificationResult.invalid()
    : this(status: SessionVerificationStatus.invalid);

  const SessionVerificationResult.deferred({UserModel? user})
    : this(status: SessionVerificationStatus.deferred, user: user);

  const SessionVerificationResult.authenticated(UserModel user)
    : this(status: SessionVerificationStatus.authenticated, user: user);
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final networkReachabilityProvider = Provider<NetworkReachability>((ref) {
  return NetworkReachability();
});

final dioProvider = Provider<Dio>((ref) {
  final api = ApiClient();
  final storage = ref.watch(tokenStorageProvider);
  final sessionEvents = ref.watch(authSessionEventsProvider);
  final reachability = ref.watch(networkReachabilityProvider);
  final offlineStore = ref.watch(offlineStoreProvider);
  api.dio.interceptors.add(AuthInterceptor(storage, sessionEvents, api.dio));
  api.dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final controller = ref.read(adminAuthorizationProvider.notifier);
        final token = controller.tokenForRequest(options.uri.toString());
        if (token != null && token.isNotEmpty) {
          options.headers['x-admin-authorization'] = token;
          options.extra['__admin_authorization_single_use'] = ref
              .read(adminAuthorizationProvider)
              .singleUse;
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (response.requestOptions.extra['__admin_authorization_single_use'] ==
            true) {
          ref
              .read(adminAuthorizationProvider.notifier)
              .consumeActionAuthorization();
        }
        handler.next(response);
      },
      onError: (error, handler) {
        if (error.requestOptions.extra['__admin_authorization_single_use'] ==
            true) {
          ref
              .read(adminAuthorizationProvider.notifier)
              .consumeActionAuthorization();
        }
        handler.next(error);
      },
    ),
  );
  api.dio.interceptors.add(
    ApiConnectivityInterceptor(dio: api.dio, reachability: reachability),
  );
  api.dio.interceptors.add(
    LoadingInterceptor(ref.read(appLoadingProvider.notifier)),
  );
  api.dio.interceptors.add(ApiDiagnosticsInterceptor());
  api.dio.interceptors.add(
    ApiOfflineCacheInterceptor(
      store: offlineStore,
      scopeResolver: () async {
        final user = await storage.getUserSnapshot();
        final companyId = user?.companyId?.trim();
        final userId = user?.id.trim();
        if ((companyId ?? '').isEmpty || (userId ?? '').isEmpty) {
          return 'public';
        }
        return 'company:$companyId:user:$userId';
      },
    ),
  );
  api.dio.interceptors.add(ApiRetryInterceptor(dio: api.dio));
  return api.dio;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    dio: ref.watch(dioProvider),
    storage: ref.watch(tokenStorageProvider),
  );
});

class AuthRepository {
  final Dio _dio;
  final TokenStorage _storage;
  static const Duration _loginTimeout = Duration(seconds: 25);
  static const Duration _bootstrapTimeout = Duration(seconds: 12);
  static const Duration _storageTimeout = Duration(seconds: 3);

  AuthRepository({required Dio dio, required TokenStorage storage})
    : _dio = dio,
      _storage = storage;

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
      final error = data['error'];
      if (error is String && error.trim().isNotEmpty) return error;
    }
    return fallback;
  }

  ApiException _mapDioError(DioException error, String fallback) {
    return ApiErrorMapper.fromDio(error, fallbackMessage: fallback, dio: _dio);
  }

  ApiException _mapLoginError(ApiException error) {
    final normalizedMessage = error.message.trim().toLowerCase();
    final normalizedResponse = (error.responseBody ?? '').toLowerCase();
    final licenseInactive =
        normalizedMessage.contains('licencia') ||
        normalizedResponse.contains('license_inactive') ||
        normalizedResponse.contains('license_blocked') ||
        normalizedResponse.contains('license_expired') ||
        normalizedResponse.contains('licencia');

    if (licenseInactive) {
      return ApiException.detailed(
        message:
            'Tu licencia no está activa. Puedes comprar o renovar tu acceso por WhatsApp al 829-534-4286.',
        code: error.code,
        type: error.type,
        displayCode: 'LICENSE_INACTIVE',
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: false,
      );
    }

    if (error.type == ApiErrorType.badRequest &&
        normalizedMessage.contains('email o identifier')) {
      return ApiException.detailed(
        message: 'Ingresa tu correo corporativo para iniciar sesión.',
        code: error.code,
        type: error.type,
        displayCode: error.displayCode,
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: false,
      );
    }

    if (error.type == ApiErrorType.unauthorized) {
      if (normalizedMessage.contains('invalid credentials')) {
        return ApiException.detailed(
          message:
              'Correo o contraseña incorrectos. Verifica tus datos e inténtalo de nuevo.',
          code: error.code,
          type: error.type,
          displayCode: error.displayCode,
          technicalDetails: error.technicalDetails,
          responseBody: error.responseBody,
          uri: error.uri,
          method: error.method,
          retryable: false,
        );
      }

      if (normalizedMessage.contains('user blocked')) {
        return ApiException.detailed(
          message:
              'Tu cuenta está bloqueada temporalmente. Contacta a un administrador para reactivarla.',
          code: error.code,
          type: error.type,
          displayCode: error.displayCode,
          technicalDetails: error.technicalDetails,
          responseBody: error.responseBody,
          uri: error.uri,
          method: error.method,
          retryable: false,
        );
      }

      return ApiException.detailed(
        message:
            'No fue posible validar tus credenciales. Revisa tu correo y tu contraseña.',
        code: error.code,
        type: error.type,
        displayCode: error.displayCode,
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: false,
      );
    }

    if (error.type == ApiErrorType.forbidden) {
      return ApiException.detailed(
        message:
            'Tu cuenta no tiene permisos para acceder en este momento. Si el problema continúa, contacta a administración.',
        code: error.code,
        type: error.type,
        displayCode: error.displayCode,
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: false,
      );
    }

    if (error.type == ApiErrorType.timeout) {
      return ApiException.detailed(
        message:
            'El servidor tardó demasiado en responder. Revisa tu conexión e inténtalo nuevamente.',
        code: error.code,
        type: error.type,
        displayCode: error.displayCode,
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: true,
      );
    }

    if (error.type == ApiErrorType.noInternet ||
        error.type == ApiErrorType.dns ||
        error.type == ApiErrorType.tls ||
        error.type == ApiErrorType.network) {
      return ApiException.detailed(
        message:
            'No pudimos conectar con el servidor. Verifica tu internet e intenta otra vez.',
        code: error.code,
        type: error.type,
        displayCode: error.displayCode,
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: true,
      );
    }

    if (error.type == ApiErrorType.config) {
      return ApiException.detailed(
        message:
            'La app no tiene una configuración válida para conectarse al backend. Revisa la configuración del sistema.',
        code: error.code,
        type: error.type,
        displayCode: error.displayCode,
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: false,
      );
    }

    if (error.type == ApiErrorType.server) {
      return ApiException.detailed(
        message:
            'El servidor presentó un problema al procesar el inicio de sesión. Intenta nuevamente en unos momentos.',
        code: error.code,
        type: error.type,
        displayCode: error.displayCode,
        technicalDetails: error.technicalDetails,
        responseBody: error.responseBody,
        uri: error.uri,
        method: error.method,
        retryable: true,
      );
    }

    return ApiException.detailed(
      message:
          'No fue posible iniciar sesión en este momento. Intenta nuevamente.',
      code: error.code,
      type: error.type,
      displayCode: error.displayCode,
      technicalDetails: error.technicalDetails,
      responseBody: error.responseBody,
      uri: error.uri,
      method: error.method,
      retryable: error.retryable,
    );
  }

  UserModel? _userFromLoginResponse(dynamic data) {
    if (data is! Map) return null;
    final user = data['user'];
    if (user is! Map) return null;

    final normalized = user.cast<String, dynamic>();
    final id = (normalized['id'] ?? '').toString().trim();
    final email = (normalized['email'] ?? '').toString().trim();
    if (id.isEmpty || email.isEmpty) return null;

    return UserModel.fromJson(normalized);
  }

  Future<void> _safeClearTokens() async {
    try {
      await _storage.clearTokens().timeout(_storageTimeout);
    } catch (_) {}
  }

  Future<HydratedSession> hydrateSession() async {
    try {
      final token = await _storage.getAccessToken().timeout(_storageTimeout);
      if (token == null || token.isEmpty) {
        return const HydratedSession.empty();
      }

      final user = await _storage.getUserSnapshot().timeout(_storageTimeout);
      return HydratedSession(hasToken: true, user: user);
    } catch (_) {
      return const HydratedSession.empty();
    }
  }

  Future<UserModel> login(String email, String password) async {
    try {
      final normalizedEmail = email.trim();
      Response<dynamic> res;

      try {
        res = await _dio
            .post(
              ApiRoutes.login,
              data: {'email': normalizedEmail, 'password': password},
            )
            .timeout(_loginTimeout);
      } on DioException catch (firstError) {
        final status = firstError.response?.statusCode;
        final message = _extractMessage(firstError.response?.data, '');
        final shouldRetryWithIdentifier =
            status == 400 ||
            status == 422 ||
            message.toLowerCase().contains('identifier') ||
            message.toLowerCase().contains('internal server error');

        if (!shouldRetryWithIdentifier) rethrow;

        res = await _dio
            .post(
              ApiRoutes.login,
              data: {'identifier': normalizedEmail, 'password': password},
            )
            .timeout(_loginTimeout);
      }

      final access = res.data['accessToken'] as String?;
      final refresh = res.data['refreshToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(access, refresh);
      }
      try {
        final me = await _dio
            .get(
              ApiRoutes.usersMe,
              options: Options(
                extra: const {'disableOfflineCache': true, 'skipLoader': true},
              ),
            )
            .timeout(_loginTimeout);
        final user = UserModel.fromJson(
          (me.data as Map).cast<String, dynamic>(),
        );
        await _storage.saveUserSnapshot(user);
        return user;
      } on DioException {
        final fallbackUser = _userFromLoginResponse(res.data);
        if (fallbackUser != null) {
          await _storage.saveUserSnapshot(fallbackUser);
          return fallbackUser;
        }
        rethrow;
      } on TimeoutException {
        final fallbackUser = _userFromLoginResponse(res.data);
        if (fallbackUser != null) {
          await _storage.saveUserSnapshot(fallbackUser);
          return fallbackUser;
        }
        rethrow;
      }
    } on TimeoutException {
      throw const ApiException.detailed(
        message:
            'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
        type: ApiErrorType.timeout,
        displayCode: 'NETWORK_TIMEOUT',
        retryable: true,
      );
    } on DioException catch (e) {
      throw _mapLoginError(_mapDioError(e, 'No se pudo iniciar sesión'));
    } on ApiException catch (e) {
      throw _mapLoginError(e);
    } catch (_) {
      rethrow;
    }
  }

  Future<UserModel> registerBusiness(Map<String, dynamic> payload) async {
    try {
      final res = await _dio
          .post(ApiRoutes.registerBusiness, data: payload)
          .timeout(_loginTimeout);
      final access = res.data['accessToken'] as String?;
      final refresh = res.data['refreshToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(access, refresh);
      }
      final fallbackUser = _userFromLoginResponse(res.data);
      if (fallbackUser == null) {
        throw ApiException('No se recibio la sesion creada');
      }
      await _storage.saveUserSnapshot(fallbackUser);
      return fallbackUser;
    } on TimeoutException {
      throw const ApiException.detailed(
        message:
            'El servidor tardó demasiado creando tu negocio. Inténtalo de nuevo.',
        type: ApiErrorType.timeout,
        displayCode: 'NETWORK_TIMEOUT',
        retryable: true,
      );
    } on DioException catch (e) {
      throw _mapDioError(e, 'No se pudo crear el negocio');
    }
  }

  Future<AccountDeletionPreview> getAccountDeletionPreview() async {
    try {
      final res = await _dio
          .get(ApiRoutes.accountDeletionPreview)
          .timeout(_bootstrapTimeout);
      return AccountDeletionPreview.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapDioError(e, 'No se pudo preparar la eliminacion de cuenta');
    } on TimeoutException {
      throw const ApiException.detailed(
        message: 'El servidor tardó demasiado preparando la eliminación.',
        type: ApiErrorType.timeout,
        displayCode: 'NETWORK_TIMEOUT',
        retryable: true,
      );
    }
  }

  Future<AccountDeletionResult> deleteAccount({
    required String password,
    String? confirmationPhrase,
  }) async {
    try {
      final res = await _dio
          .delete(
            ApiRoutes.accountDelete,
            data: {
              'password': password,
              if (confirmationPhrase != null)
                'confirmationPhrase': confirmationPhrase,
              'idempotencyKey': DateTime.now().microsecondsSinceEpoch
                  .toString(),
            },
          )
          .timeout(_loginTimeout);
      return AccountDeletionResult.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw _mapDioError(e, 'No se pudo eliminar la cuenta');
    } on TimeoutException {
      throw const ApiException.detailed(
        message:
            'El servidor tardó demasiado eliminando la cuenta. Verifica el estado antes de intentar de nuevo.',
        type: ApiErrorType.timeout,
        displayCode: 'NETWORK_TIMEOUT',
        retryable: true,
      );
    }
  }

  Future<UserModel?> getMeOrNull({
    bool silent = false,
    bool allowCachedFallback = true,
  }) async {
    // Widget tests (smoke test) should not block on secure storage/network.
    // Those calls can hang in tests and leave pending timeout timers.
    // Note: `bool.fromEnvironment('FLUTTER_TEST')` would require --dart-define;
    // `flutter test` doesn't set that by default.
    if (isFlutterTest) {
      return null;
    }

    try {
      final token = await _storage.getAccessToken().timeout(_storageTimeout);
      if (token == null) return null;
      try {
        final res = await _dio
            .get(
              ApiRoutes.usersMe,
              options: Options(
                extra: {
                  'silent': silent,
                  'disableOfflineCache': true,
                  'skipLoader': true,
                },
              ),
            )
            .timeout(_bootstrapTimeout);
        final user = UserModel.fromJson(
          (res.data as Map).cast<String, dynamic>(),
        );
        await _storage.saveUserSnapshot(user);
        return user;
      } on DioException catch (e) {
        // Si expira, intenta refresh y reintenta
        if (e.response?.statusCode == 401) {
          final refreshed = await _refreshAndSave(silent: silent);
          if (refreshed) {
            final res = await _dio
                .get(
                  ApiRoutes.usersMe,
                  options: Options(
                    extra: {
                      'silent': silent,
                      'disableOfflineCache': true,
                      'skipLoader': true,
                    },
                  ),
                )
                .timeout(_bootstrapTimeout);
            final user = UserModel.fromJson(
              (res.data as Map).cast<String, dynamic>(),
            );
            await _storage.saveUserSnapshot(user);
            return user;
          }

          await _safeClearTokens();
          return null;
        }

        if (!allowCachedFallback) return null;
        return await _storage.getUserSnapshot();
      } on TimeoutException {
        if (!allowCachedFallback) return null;
        return await _storage.getUserSnapshot();
      }
    } catch (_) {
      if (!allowCachedFallback) return null;
      return await _storage.getUserSnapshot();
    }
  }

  Future<SessionVerificationResult> verifySession({bool silent = false}) async {
    if (isFlutterTest) {
      return const SessionVerificationResult.invalid();
    }

    final hydrated = await hydrateSession();
    if (!hydrated.hasToken) {
      return const SessionVerificationResult.invalid();
    }

    try {
      final user = await getMeOrNull(silent: silent);
      if (user != null) {
        return SessionVerificationResult.authenticated(user);
      }

      final token = await _storage.getAccessToken().timeout(_storageTimeout);
      if (token == null || token.isEmpty) {
        return const SessionVerificationResult.invalid();
      }

      if (hydrated.user != null) {
        return SessionVerificationResult.deferred(user: hydrated.user);
      }

      return const SessionVerificationResult.deferred();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        await _safeClearTokens();
        return const SessionVerificationResult.invalid();
      }

      return SessionVerificationResult.deferred(user: hydrated.user);
    } on TimeoutException {
      return SessionVerificationResult.deferred(user: hydrated.user);
    } catch (_) {
      return SessionVerificationResult.deferred(user: hydrated.user);
    }
  }

  Future<bool> _refreshAndSave({bool silent = false}) async {
    final refresh = await _storage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    try {
      final res = await _dio.post(
        ApiRoutes.refresh,
        data: {'refreshToken': refresh},
        options: Options(extra: {'silent': silent}),
      );
      final access = res.data['accessToken'] as String?;
      final newRefresh = res.data['refreshToken'] as String?;
      if (access != null && access.isNotEmpty) {
        await _storage.saveTokens(
          access,
          (newRefresh != null && newRefresh.isNotEmpty) ? newRefresh : refresh,
        );
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }
}

class AccountDeletionPreview {
  const AccountDeletionPreview({
    required this.mode,
    required this.memberships,
    required this.activeCompanyRole,
    required this.isOnlyOwner,
    required this.companyWillBeDeleted,
    required this.requiresCompanyConfirmationPhrase,
    required this.blockingOwnedCompanies,
    required this.affectedDataCategories,
  });

  final String mode;
  final int memberships;
  final String? activeCompanyRole;
  final bool isOnlyOwner;
  final bool companyWillBeDeleted;
  final bool requiresCompanyConfirmationPhrase;
  final int blockingOwnedCompanies;
  final List<String> affectedDataCategories;

  factory AccountDeletionPreview.fromJson(Map<String, dynamic> json) {
    return AccountDeletionPreview(
      mode: (json['mode'] ?? 'personal_account').toString(),
      memberships: (json['memberships'] as num?)?.toInt() ?? 0,
      activeCompanyRole: json['activeCompanyRole']?.toString(),
      isOnlyOwner: json['isOnlyOwner'] == true,
      companyWillBeDeleted: json['companyWillBeDeleted'] == true,
      requiresCompanyConfirmationPhrase:
          json['requiresCompanyConfirmationPhrase'] == true,
      blockingOwnedCompanies:
          (json['blockingOwnedCompanies'] as num?)?.toInt() ?? 0,
      affectedDataCategories: (json['affectedDataCategories'] as List? ?? [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class AccountDeletionResult {
  const AccountDeletionResult({
    required this.ok,
    required this.deletionReceiptId,
    required this.companyDeleted,
  });

  final bool ok;
  final String deletionReceiptId;
  final bool companyDeleted;

  factory AccountDeletionResult.fromJson(Map<String, dynamic> json) {
    return AccountDeletionResult(
      ok: json['ok'] == true,
      deletionReceiptId: (json['deletionReceiptId'] ?? '').toString(),
      companyDeleted: json['companyDeleted'] == true,
    );
  }
}
