import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../company/company_settings_repository.dart';
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

  final company = ref.watch(companySettingsProvider);
  return company.when(
    data: (settings) {
      final companyName = settings.companyName.trim();
      TraceLog.log(
        'AppBootstrap',
        'ACTIVE_COMPANY_RESOLVED userId=$userId companyId=$companyId hasName=${companyName.isNotEmpty}',
      );
      TraceLog.log(
        'AppBootstrap',
        'APP_BOOTSTRAP_READY userId=$userId companyId=$companyId',
      );
      return AppBootstrapStatus.ready;
    },
    loading: () {
      TraceLog.log(
        'AppBootstrap',
        'MEMBERSHIP_RESOLVED userId=$userId companyId=$companyId; loading active company',
      );
      return AppBootstrapStatus.authenticatedLoadingCompany;
    },
    error: (error, stackTrace) {
      TraceLog.log(
        'AppBootstrap',
        'ACTIVE_COMPANY_RESOLUTION_ERROR userId=$userId companyId=$companyId',
        error: error,
        stackTrace: stackTrace,
      );
      final snapshotCompanyName = user?.companyName?.trim() ?? '';
      return snapshotCompanyName.isNotEmpty
          ? AppBootstrapStatus.ready
          : AppBootstrapStatus.error;
    },
  );
});
