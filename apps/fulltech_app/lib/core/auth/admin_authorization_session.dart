import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';

class AdminAuthorizationState {
  const AdminAuthorizationState({this.authorizedUntil, this.token});

  final DateTime? authorizedUntil;
  final String? token;

  bool get isAuthorized {
    final until = authorizedUntil;
    return token != null && until != null && until.isAfter(DateTime.now());
  }
}

final adminAuthorizationProvider =
    StateNotifierProvider<AdminAuthorizationController, AdminAuthorizationState>(
      (ref) => AdminAuthorizationController(ref),
    );

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

  bool get isAuthorized => state.isAuthorized;

  void authorizeFor(Duration duration, String token) {
    state = AdminAuthorizationState(
      authorizedUntil: DateTime.now().add(duration),
      token: token,
    );
  }

  void clear() {
    state = const AdminAuthorizationState();
  }
}
