import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

enum AdminAuthorizationScope { action, route }

class AdminAuthorizationState {
  const AdminAuthorizationState({
    this.authorizedUntil,
    this.token,
    this.scope = AdminAuthorizationScope.action,
    this.routePath,
    this.singleUse = true,
  });

  final DateTime? authorizedUntil;
  final String? token;
  final AdminAuthorizationScope scope;
  final String? routePath;
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
      if (previous?.user?.id != next.user?.id || !next.isAuthenticated) {
        clear();
      }
    });
  }

  final Ref _ref;
  Timer? _expiryTimer;

  bool get isAuthorized => state.isAuthorized;
  bool get hasActionAuthorization => state.isActionAuthorization;

  void authorizeFor(Duration duration, String token) {
    authorizeAction(duration, token);
  }

  void authorizeAction(Duration duration, String token) {
    final capped = _capDuration(duration);
    state = AdminAuthorizationState(
      authorizedUntil: DateTime.now().add(capped),
      token: token,
      scope: AdminAuthorizationScope.action,
      singleUse: true,
    );
    _scheduleExpiry(capped);
  }

  void authorizeRoute(Duration duration, String token, String location) {
    final capped = _capDuration(duration);
    state = AdminAuthorizationState(
      authorizedUntil: DateTime.now().add(capped),
      token: token,
      scope: AdminAuthorizationScope.route,
      routePath: _normalizePath(location),
      singleUse: false,
    );
    _scheduleExpiry(capped);
  }

  bool isAuthorizedForRoute(String location) =>
      state.isAuthorizedForRoute(location);

  String? tokenForRequest(String location) {
    return state.canAttachToRequest(location) ? state.token : null;
  }

  void consumeActionAuthorization() {
    if (state.scope == AdminAuthorizationScope.action) {
      clear();
    }
  }

  void clearIfInvalidForLocation(String location) {
    if (!state.isAuthorized) {
      if (state.token != null || state.authorizedUntil != null) clear();
      return;
    }
    if (state.scope == AdminAuthorizationScope.route &&
        !state.isAuthorizedForRoute(location)) {
      clear();
    }
  }

  void clearIfExpired() {
    if (!state.isAuthorized &&
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
    const maxDuration = Duration(minutes: 10);
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
}

String _normalizePath(String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) return trimmed;
  return Uri.tryParse(trimmed)?.path ?? trimmed.split('?').first;
}
