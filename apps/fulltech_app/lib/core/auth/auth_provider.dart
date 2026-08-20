import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';
import 'auth_session_events.dart';
import 'token_storage.dart';
import '../cache/fulltech_cache_manager.dart';
import '../debug/trace_log.dart';
import '../models/user_model.dart';
import '../offline/sync_queue_service.dart';
import '../utils/is_flutter_test.dart';

class AuthState {
  final bool initialized;
  final bool isAuthenticated;
  final UserModel? user;
  final bool loading;
  final bool restoringSession;
  final bool hasSessionHint;

  AuthState({
    required this.initialized,
    required this.isAuthenticated,
    this.user,
    this.loading = false,
    this.restoringSession = false,
    this.hasSessionHint = false,
  });

  AuthState copyWith({
    bool? initialized,
    bool? isAuthenticated,
    UserModel? user,
    bool? loading,
    bool? restoringSession,
    bool? hasSessionHint,
    bool clearUser = false,
  }) {
    return AuthState(
      initialized: initialized ?? this.initialized,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      user: clearUser ? null : (user ?? this.user),
      loading: loading ?? this.loading,
      restoringSession: restoringSession ?? this.restoringSession,
      hasSessionHint: hasSessionHint ?? this.hasSessionHint,
    );
  }
}

final authStateProvider = StateNotifierProvider<AuthController, AuthState>((
  ref,
) {
  return AuthController(ref);
});

final authLaunchSnapshotProvider = Provider<TokenStorageLaunchSnapshot>((ref) {
  return const TokenStorageLaunchSnapshot.empty();
});

Future<TokenStorageLaunchSnapshot> loadAuthLaunchSnapshot() {
  // Usa la MISMA instancia canónica que tokenStorageProvider para que el mutex
  // interno serialice TODAS las operaciones sobre flutter_secure_storage.dat.
  // Crear una instancia nueva aquí competiría por el mismo archivo con el
  // bootstrap de AuthController (CryptUnprotectData / file being used).
  return TokenStorage.instance.readFastLaunchSnapshot();
}

class AuthController extends StateNotifier<AuthState> {
  final Ref ref;
  late final AuthSessionEvents _sessionEvents;
  Future<void>? _verifySessionFuture;

  AuthController(this.ref)
    : super(_buildInitialAuthState(ref.read(authLaunchSnapshotProvider))) {
    _sessionEvents = ref.read(authSessionEventsProvider);
    _sessionEvents.addListener(_onSessionEventsChanged);
    ref.onDispose(() {
      _sessionEvents.removeListener(_onSessionEventsChanged);
    });
    _bootstrap();
  }

  void _onSessionEventsChanged() {
    if (!_sessionEvents.unauthorizedLogoutRequested) return;
    unawaited(_logoutForUnauthorized());
  }

  void _markSessionHealthy() {
    _sessionEvents.markSessionHealthy();
  }

  bool _hasResolvedTenantIdentity(UserModel? user) {
    if (user == null) return false;
    return user.id.trim().isNotEmpty &&
        (user.companyId?.trim().isNotEmpty ?? false);
  }

  Future<void> _logoutForUnauthorized() async {
    _sessionEvents.markLogoutHandled();
    TraceLog.log(
      'AUTH_CHANGE',
      'from=authenticated to=unauthenticated reason=unauthorized_logout caller=_logoutForUnauthorized lifecycle=session_event',
    );
    final storage = ref.read(tokenStorageProvider);
    await ref.read(offlineStoreProvider).clearAll(includePendingActions: false);
    await FulltechImageCacheManager.clear();
    await storage.clearTokens();
    if (!mounted) return;
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      user: null,
      loading: false,
      restoringSession: false,
      hasSessionHint: false,
    );
  }

  Future<void> _bootstrap() async {
    final seq = TraceLog.nextSeq();
    final sw = Stopwatch()..start();
    TraceLog.log('Auth', '_bootstrap() start', seq: seq);

    if (isFlutterTest) {
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
      );
      return;
    }

    try {
      final repo = ref.read(authRepositoryProvider);
      final hydrated = await repo.hydrateSession();

      if (!mounted) return;

      if (!hydrated.hasToken) {
        state = AuthState(
          initialized: true,
          isAuthenticated: false,
          user: null,
          loading: false,
          restoringSession: false,
          hasSessionHint: false,
        );
        sw.stop();
        TraceLog.log(
          'Auth',
          '_bootstrap() no local session (${sw.elapsedMilliseconds}ms)',
          seq: seq,
        );
        return;
      }

      state = AuthState(
        initialized: true,
        isAuthenticated: true,
        user: hydrated.user,
        loading: false,
        restoringSession: true,
        hasSessionHint: true,
      );
      _markSessionHealthy();
      TraceLog.log(
        'Auth',
        'AUTH_SESSION_RESTORED userId=${hydrated.user?.id ?? ''} companyId=${hydrated.user?.companyId ?? ''}',
        seq: seq,
      );
      sw.stop();
      TraceLog.log(
        'Auth',
        '_bootstrap() local session restored (${sw.elapsedMilliseconds}ms)',
        seq: seq,
      );

      unawaited(verifySessionInBackground());
    } catch (_) {
      if (!mounted) return;
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
      );
    }
  }

  Future<void> _verifySession() async {
    final seq = TraceLog.nextSeq();
    final sw = Stopwatch()..start();
    TraceLog.log('Auth', '_verifySession() start', seq: seq);

    try {
      final result = await ref
          .read(authRepositoryProvider)
          .verifySession(silent: true);
      if (!mounted) return;

      switch (result.status) {
        case SessionVerificationStatus.authenticated:
          _markSessionHealthy();
          TraceLog.log(
            'Auth',
            'USER_RESOLVED userId=${result.user?.id ?? ''} companyId=${result.user?.companyId ?? ''}',
            seq: seq,
          );
          state = AuthState(
            initialized: true,
            isAuthenticated: true,
            user: result.user,
            loading: false,
            restoringSession: false,
            hasSessionHint: true,
          );
          break;
        case SessionVerificationStatus.invalid:
          TraceLog.log(
            'AUTH_CHANGE',
            'from=authenticated to=unauthenticated reason=verifySession_invalid caller=_verifySession lifecycle=resumed',
          );
          state = AuthState(
            initialized: true,
            isAuthenticated: false,
            user: null,
            loading: false,
            restoringSession: false,
            hasSessionHint: false,
          );
          break;
        case SessionVerificationStatus.deferred:
          final user = result.user ?? state.user;
          final canKeepSession = user != null || state.hasSessionHint;
          if (canKeepSession) {
            final tenantIdentityResolved = _hasResolvedTenantIdentity(user);
            _markSessionHealthy();
            TraceLog.log(
              'AUTH_CHANGE',
              'verifySession deferred authenticated=true tenantIdentityResolved=$tenantIdentityResolved restoringSession=${!tenantIdentityResolved}',
              seq: seq,
            );
            state = state.copyWith(
              initialized: true,
              isAuthenticated: true,
              user: user,
              loading: false,
              restoringSession: !tenantIdentityResolved,
              hasSessionHint: true,
            );
            break;
          }
          state = AuthState(
            initialized: true,
            isAuthenticated: false,
            user: null,
            loading: false,
            restoringSession: false,
            hasSessionHint: false,
          );
          break;
      }
    } catch (_) {
      if (!mounted) return;
      final canKeepSession = state.hasSessionHint;
      final tenantIdentityResolved = _hasResolvedTenantIdentity(state.user);
      state = state.copyWith(
        initialized: true,
        isAuthenticated: canKeepSession,
        loading: false,
        restoringSession: canKeepSession && !tenantIdentityResolved,
      );
    } finally {
      sw.stop();
      TraceLog.log(
        'Auth',
        '_verifySession() end (${sw.elapsedMilliseconds}ms)',
        seq: seq,
      );
    }
  }

  Future<bool> login(String email, String password) async {
    if (state.loading) return false;
    state = state.copyWith(loading: true);
    final repo = ref.read(authRepositoryProvider);
    try {
      final user = await repo.login(email, password);
      _markSessionHealthy();
      TraceLog.log(
        'Auth',
        'USER_RESOLVED userId=${user.id} companyId=${user.companyId ?? ''}',
      );
      state = AuthState(
        initialized: true,
        isAuthenticated: true,
        user: user,
        loading: false,
        restoringSession: false,
        hasSessionHint: true,
      );
      return true;
    } catch (_) {
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
      );
      rethrow;
    }
  }

  Future<bool> registerBusiness(Map<String, dynamic> payload) async {
    if (state.loading) return false;
    state = state.copyWith(loading: true);
    final repo = ref.read(authRepositoryProvider);
    try {
      final user = await repo.registerBusiness(payload);
      _markSessionHealthy();
      state = AuthState(
        initialized: true,
        isAuthenticated: true,
        user: user,
        loading: false,
        restoringSession: false,
        hasSessionHint: true,
      );
      return true;
    } catch (_) {
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
      );
      rethrow;
    }
  }

  Future<void> logout() async {
    _markSessionHealthy();
    final storage = ref.read(tokenStorageProvider);
    await ref.read(offlineStoreProvider).clearAll(includePendingActions: false);
    await FulltechImageCacheManager.clear();
    await storage.clearTokens();
    state = AuthState(
      initialized: true,
      isAuthenticated: false,
      user: null,
      loading: false,
      restoringSession: false,
      hasSessionHint: false,
    );
  }

  Future<UserModel?> refreshCurrentUser({bool silent = true}) async {
    if (!state.isAuthenticated) return null;
    final user = await ref
        .read(authRepositoryProvider)
        .getMeOrNull(silent: silent, allowCachedFallback: true);
    if (user == null || !mounted) return null;
    setUser(user);
    return user;
  }

  Future<void> verifySessionInBackground() {
    _verifySessionFuture ??= _verifySession().whenComplete(() {
      _verifySessionFuture = null;
    });
    return _verifySessionFuture!;
  }

  Future<AccountDeletionResult> deleteAccount({
    required String password,
    String? confirmationPhrase,
  }) async {
    if (state.loading) {
      throw StateError('Ya hay una operacion de autenticacion en curso');
    }

    state = state.copyWith(loading: true);
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .deleteAccount(
            password: password,
            confirmationPhrase: confirmationPhrase,
          );
      await ref.read(offlineStoreProvider).clearAll();
      await FulltechImageCacheManager.clear();
      await ref.read(tokenStorageProvider).clearTokens();
      _markSessionHealthy();
      state = AuthState(
        initialized: true,
        isAuthenticated: false,
        user: null,
        loading: false,
        restoringSession: false,
        hasSessionHint: false,
      );
      return result;
    } catch (_) {
      if (mounted) {
        state = state.copyWith(loading: false);
      }
      rethrow;
    }
  }

  void setUser(
    UserModel user, {
    bool persistSnapshot = true,
    UserModel? snapshotUser,
  }) {
    if (persistSnapshot) {
      unawaited(
        ref.read(tokenStorageProvider).saveUserSnapshot(snapshotUser ?? user),
      );
    }
    _markSessionHealthy();
    state = state.copyWith(
      user: user,
      isAuthenticated: true,
      restoringSession: false,
      hasSessionHint: true,
    );
  }
}

AuthState _buildInitialAuthState(TokenStorageLaunchSnapshot snapshot) {
  return AuthState(
    initialized: false,
    isAuthenticated: snapshot.hasSessionHint,
    user: snapshot.user,
    loading: false,
    restoringSession: snapshot.hasSessionHint,
    hasSessionHint: snapshot.hasSessionHint,
  );
}
