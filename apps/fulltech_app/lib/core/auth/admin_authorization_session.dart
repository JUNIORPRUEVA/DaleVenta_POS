import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

enum AdminAuthorizationScope { action, route }

final adminAuthorizationNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

class AdminAuthorizationState {
  const AdminAuthorizationState({
    this.authorizedUntil,
    this.token,
    this.scope = AdminAuthorizationScope.action,
    this.routePath,
    this.userId,
    this.companyId,
    this.singleUse = true,
  });

  final DateTime? authorizedUntil;
  final String? token;
  final AdminAuthorizationScope scope;
  final String? routePath;
  final String? userId;
  final String? companyId;
  final bool singleUse;

  bool get isAuthorized {
    final until = authorizedUntil;
    return token != null && until != null && until.isAfter(DateTime.now());
  }

  bool get isActionAuthorization =>
      isAuthorized && scope == AdminAuthorizationScope.action;

  bool isAuthorizedForRoute(String location) {
    if (!isAuthorized) return false;
    if (scope != AdminAuthorizationScope.route) return false;
    final expected = routePath;
    if (expected == null || expected.isEmpty) return false;
    return _normalizePath(location) == expected;
  }

  bool canAttachToRequest(String location) {
    if (!isAuthorized) return false;
    if (scope == AdminAuthorizationScope.action) return true;
    return isAuthorizedForRoute(location);
  }
}

final adminAuthorizationProvider =
    StateNotifierProvider<
      AdminAuthorizationController,
      AdminAuthorizationState
    >((ref) => AdminAuthorizationController(ref));

class AdminAuthorizationController
    extends StateNotifier<AdminAuthorizationState> {
  AdminAuthorizationController(this._ref)
    : super(const AdminAuthorizationState()) {
    _ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (previous?.user?.id != next.user?.id ||
          previous?.user?.companyId != next.user?.companyId ||
          !next.isAuthenticated) {
        clear();
      }
    });
  }

  final Ref _ref;
  Timer? _expiryTimer;

  bool get isAuthorized =>
      _matchesCurrentPrincipal() && _isStateAuthorizedAt(_now());
  bool get hasActionAuthorization =>
      isAuthorized && state.scope == AdminAuthorizationScope.action;

  void authorizeFor(Duration duration, String token) {
    authorizeAction(duration, token);
  }

  void authorizeAction(Duration duration, String token) {
    final capped = _capDuration(duration);
    final user = _ref.read(authStateProvider).user;
    state = AdminAuthorizationState(
      authorizedUntil: _now().add(capped),
      token: token,
      scope: AdminAuthorizationScope.action,
      userId: user?.id,
      companyId: user?.companyId,
      singleUse: true,
    );
    _scheduleExpiry(capped);
  }

  void authorizeRoute(Duration duration, String token, String location) {
    final capped = _capDuration(duration);
    final user = _ref.read(authStateProvider).user;
    state = AdminAuthorizationState(
      authorizedUntil: _now().add(capped),
      token: token,
      scope: AdminAuthorizationScope.route,
      routePath: _normalizePath(location),
      userId: user?.id,
      companyId: user?.companyId,
      singleUse: false,
    );
    _scheduleExpiry(capped);
  }

  bool isAuthorizedForRoute(String location) =>
      _matchesCurrentPrincipal() &&
      _isStateAuthorizedAt(_now()) &&
      state.scope == AdminAuthorizationScope.route &&
      _stateMatchesRoute(location);

  String? tokenForRequest(String location) {
    if (!_matchesCurrentPrincipal() || !_isStateAuthorizedAt(_now())) {
      return null;
    }
    if (state.scope == AdminAuthorizationScope.action) return state.token;
    return _stateMatchesRoute(location) ? state.token : null;
  }

  void consumeActionAuthorization() {
    if (state.scope == AdminAuthorizationScope.action) {
      clear();
    }
  }

  void clearIfInvalidForLocation(String location) {
    if (!_matchesCurrentPrincipal()) {
      clear();
      return;
    }
    if (!_isStateAuthorizedAt(_now())) {
      if (state.token != null || state.authorizedUntil != null) clear();
      return;
    }
    if (state.scope == AdminAuthorizationScope.route &&
        !_stateMatchesRoute(location)) {
      clear();
    }
  }

  void clearIfExpired() {
    if (!_matchesCurrentPrincipal()) {
      clear();
      return;
    }
    if (!_isStateAuthorizedAt(_now()) &&
        (state.token != null || state.authorizedUntil != null)) {
      clear();
    }
  }

  void clear() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    state = const AdminAuthorizationState();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  Duration _capDuration(Duration duration) {
    const maxDuration = Duration(minutes: 20);
    if (duration <= Duration.zero) return Duration.zero;
    return duration > maxDuration ? maxDuration : duration;
  }

  void _scheduleExpiry(Duration duration) {
    _expiryTimer?.cancel();
    if (duration <= Duration.zero) {
      clear();
      return;
    }
    _expiryTimer = Timer(duration, clear);
  }

  DateTime _now() => _ref.read(adminAuthorizationNowProvider)();

  bool _isStateAuthorizedAt(DateTime now) {
    final until = state.authorizedUntil;
    return state.token != null && until != null && until.isAfter(now);
  }

  bool _stateMatchesRoute(String location) {
    final expected = state.routePath;
    return expected != null &&
        expected.isNotEmpty &&
        _normalizePath(location) == expected;
  }

  bool _matchesCurrentPrincipal() {
    if (state.token == null && state.authorizedUntil == null) return true;
    final user = _ref.read(authStateProvider).user;
    return user != null &&
        user.id == state.userId &&
        user.companyId == state.companyId;
  }
}

String _normalizePath(String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) return trimmed;
  return Uri.tryParse(trimmed)?.path ?? trimmed.split('?').first;
}
