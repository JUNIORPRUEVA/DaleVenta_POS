import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthSessionEvents extends ChangeNotifier {
  bool _unauthorizedLogoutRequested = false;
  String? _logoutReason;

  bool get unauthorizedLogoutRequested => _unauthorizedLogoutRequested;
  String? get logoutReason => _logoutReason;
  bool get isLicenseLogout => _logoutReason == 'license_expired';

  void requestUnauthorizedLogout({String? reason}) {
    debugPrint(
      '[AUTH_CHANGE] requestUnauthorizedLogout reason=$reason '
      'caller=${StackTrace.current.toString().split('\n').skip(1).take(3).join(' | ')}',
    );
    if (_unauthorizedLogoutRequested && _logoutReason == reason) return;
    _unauthorizedLogoutRequested = true;
    _logoutReason = reason;
    notifyListeners();
  }

  void markLogoutHandled() {
    if (!_unauthorizedLogoutRequested) return;
    _unauthorizedLogoutRequested = false;
    notifyListeners();
  }

  void markSessionHealthy() {
    if (!_unauthorizedLogoutRequested && _logoutReason == null) return;
    _unauthorizedLogoutRequested = false;
    _logoutReason = null;
    notifyListeners();
  }

  void dismissReason() {
    if (_logoutReason == null) return;
    _logoutReason = null;
    notifyListeners();
  }
}

final authSessionEventsProvider = ChangeNotifierProvider<AuthSessionEvents>((
  ref,
) {
  final events = AuthSessionEvents();
  return events;
});
