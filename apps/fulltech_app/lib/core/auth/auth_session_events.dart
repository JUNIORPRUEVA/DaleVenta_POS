import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthSessionEvents extends ChangeNotifier {
  bool _unauthorizedLogoutRequested = false;

  bool get unauthorizedLogoutRequested => _unauthorizedLogoutRequested;

  void requestUnauthorizedLogout() {
    if (_unauthorizedLogoutRequested) return;
    _unauthorizedLogoutRequested = true;
    notifyListeners();
  }

  void markSessionHealthy() {
    if (!_unauthorizedLogoutRequested) return;
    _unauthorizedLogoutRequested = false;
    notifyListeners();
  }
}

final authSessionEventsProvider = Provider<AuthSessionEvents>((ref) {
  final events = AuthSessionEvents();
  ref.onDispose(events.dispose);
  return events;
});
