import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import 'session_notice_storage.dart';

final webSessionActionsEnabledProvider = Provider<bool>((ref) => kIsWeb);

/// UI dismissal only. Never writes onboarding progress or account settings.
class SessionNotices extends StateNotifier<Set<String>> {
  SessionNotices(this.scope)
    : super({
        for (final name in ['activation', 'apps'])
          if (readSessionNotice('fullpos:notices:$scope:$name')) name,
      });

  final String scope;

  void dismiss(String name) {
    writeSessionNotice('fullpos:notices:$scope:$name');
    state = {...state, name};
  }
}

final sessionNoticesProvider =
    StateNotifierProvider<SessionNotices, Set<String>>((ref) {
      final scope = ref.watch(
        authStateProvider.select(
          (auth) => '${auth.user?.companyId}:${auth.user?.id}',
        ),
      );
      return SessionNotices(scope);
    });
