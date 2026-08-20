import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../debug/trace_log.dart';
import 'auth_provider.dart';

enum AppBootstrapStatus {
  initializing,
  authenticatedLoadingCompany,
  ready,
  unauthenticated,
  error,
}

final appBootstrapStatusProvider = Provider<AppBootstrapStatus>((ref) {
  final auth = ref.watch(authStateProvider);
  if (!auth.initialized) return AppBootstrapStatus.initializing;
  if (!auth.isAuthenticated) return AppBootstrapStatus.unauthenticated;

  final user = auth.user;
  final userId = user?.id.trim() ?? '';
  final companyId = user?.companyId?.trim() ?? '';
  if (auth.restoringSession) {
    return AppBootstrapStatus.authenticatedLoadingCompany;
  }
  if (userId.isEmpty || companyId.isEmpty) return AppBootstrapStatus.error;
  TraceLog.log(
    'AppBootstrap',
    'APP_BOOTSTRAP_READY userId=$userId companyId=$companyId',
  );
  return AppBootstrapStatus.ready;
});
