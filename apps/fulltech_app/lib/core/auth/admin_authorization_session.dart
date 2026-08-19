import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

enum AdminAuthorizationScope { action, route }

class AdminAuthorizationState {
  const AdminAuthorizationState({
    this.authorizedUntil,
    this.token,
    this.delegationScope,
    this.scope = AdminAuthorizationScope.action,
    this.routePath,
    this.singleUse = true,
    this.userId,
    this.companyId,
    this.routeEntered = false,
  });

  final DateTime? authorizedUntil;
  final String? token;
  final String? delegationScope;
  final AdminAuthorizationScope scope;
  final String? routePath;
  final bool singleUse;
  final String? userId;
  final String? companyId;
  final bool routeEntered;

  bool get isAuthorized {
    final until = authorizedUntil;
    return token != null && until != null && until.isAfter(DateTime.now());
  }

  bool get isActionAuthorization =>
      isAuthorized && scope == AdminAuthorizationScope.action;

  bool belongsTo(String? currentUserId, String? currentCompanyId) {
    final expectedUserId = userId?.trim();
    final expectedCompanyId = companyId?.trim();
    if (expectedUserId == null || expectedUserId.isEmpty) return false;
    if (expectedCompanyId == null || expectedCompanyId.isEmpty) return false;
    return expectedUserId == (currentUserId ?? '').trim() &&
        expectedCompanyId == (currentCompanyId ?? '').trim();
  }

  bool isAuthorizedForRoute(String location) {
    if (!isAuthorized) return false;
    if (scope != AdminAuthorizationScope.route) return false;
    final expected = routePath;
    if (expected == null || expected.isEmpty) return false;
    return _normalizePath(location) == expected;
  }

  bool canAttachToRequest(String location) {
    if (!isAuthorized) return false;
    final apiPath = _normalizePath(location);
    final delegated = delegationScope;
    if (delegated == null || delegated.isEmpty) {
      if (scope == AdminAuthorizationScope.action) return true;
      return isAuthorizedForRoute(location);
    }
    if (!_scopeAllowsApiPath(delegated, apiPath)) return false;
    if (scope == AdminAuthorizationScope.action) return true;
    return true;
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

  bool get isAuthorized => _belongsToCurrentSession() && state.isAuthorized;
  bool get hasActionAuthorization =>
      _belongsToCurrentSession() && state.isActionAuthorization;

  void authorizeFor(
    Duration duration,
    String token, {
    String? delegationScope,
  }) {
    authorizeAction(duration, token, delegationScope: delegationScope);
  }

  void authorizeAction(
    Duration duration,
    String token, {
    String? delegationScope,
  }) {
    final capped = _capDuration(duration);
    final user = _ref.read(authStateProvider).user;
    state = AdminAuthorizationState(
      authorizedUntil: DateTime.now().add(capped),
      token: token,
      delegationScope: delegationScope,
      scope: AdminAuthorizationScope.action,
      singleUse: true,
      userId: user?.id,
      companyId: user?.companyId,
    );
    _scheduleExpiry(capped);
  }

  void authorizeRoute(
    Duration duration,
    String token,
    String location, {
    String? delegationScope,
  }) {
    final capped = _capDuration(duration);
    final user = _ref.read(authStateProvider).user;
    state = AdminAuthorizationState(
      authorizedUntil: DateTime.now().add(capped),
      token: token,
      delegationScope: delegationScope,
      scope: AdminAuthorizationScope.route,
      routePath: _normalizePath(location),
      singleUse: false,
      userId: user?.id,
      companyId: user?.companyId,
    );
    _scheduleExpiry(capped);
  }

  bool isAuthorizedForRoute(String location) =>
      _belongsToCurrentSession() && state.isAuthorizedForRoute(location);

  String? tokenForRequest(String location) {
    return _belongsToCurrentSession() && state.canAttachToRequest(location)
        ? state.token
        : null;
  }

  void consumeActionAuthorization() {
    if (state.scope == AdminAuthorizationScope.action) {
      clear();
    }
  }

  void clearIfInvalidForLocation(String location) {
    if (!state.isAuthorized || !_belongsToCurrentSession()) {
      if (state.token != null || state.authorizedUntil != null) clear();
      return;
    }
    if (state.scope == AdminAuthorizationScope.route &&
        !state.isAuthorizedForRoute(location)) {
      clear();
    }
  }

  void clearIfExpired() {
    if ((!state.isAuthorized || !_belongsToCurrentSession()) &&
        (state.token != null || state.authorizedUntil != null)) {
      clear();
    }
  }

  void markRouteEntered(String location) {
    if (state.scope != AdminAuthorizationScope.route) return;
    if (!state.isAuthorizedForRoute(location)) return;
    if (state.routeEntered) return;
    state = AdminAuthorizationState(
      authorizedUntil: state.authorizedUntil,
      token: state.token,
      delegationScope: state.delegationScope,
      scope: state.scope,
      routePath: state.routePath,
      singleUse: state.singleUse,
      userId: state.userId,
      companyId: state.companyId,
      routeEntered: true,
    );
  }

  void clearIfRouteScopeExited(String location) {
    if (!state.isAuthorized || !_belongsToCurrentSession()) {
      if (state.token != null || state.authorizedUntil != null) clear();
      return;
    }
    if (state.scope != AdminAuthorizationScope.route) return;
    if (!state.routeEntered) return;
    if (!state.isAuthorizedForRoute(location)) clear();
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

  bool _belongsToCurrentSession() {
    final user = _ref.read(authStateProvider).user;
    return state.belongsTo(user?.id, user?.companyId);
  }
}

String _normalizePath(String location) {
  final trimmed = location.trim();
  if (trimmed.isEmpty) return trimmed;
  return Uri.tryParse(trimmed)?.path ?? trimmed.split('?').first;
}

bool _scopeAllowsApiPath(String scope, String path) {
  switch (scope) {
    case 'company.settings':
      return path == '/settings' ||
          path == '/company/fiscal-settings' ||
          path == '/taxes' ||
          path.startsWith('/taxes/') ||
          path == '/ncf/sequences' ||
          path.startsWith('/ncf/sequences/');
    default:
      return false;
  }
}
