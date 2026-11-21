import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/retry_after.dart';
import '../auth/auth_repository.dart';
import '../auth/operation_scope.dart';
import '../config/uat_identity.dart';
import 'pending_sync_action.dart';
import 'recovery_review_repository.dart';
import 'sync_queue_service.dart';

final recoveryReviewPublisherProvider = Provider<RecoveryReviewPublisher>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final store = ref.watch(offlineStoreProvider);
  final repository = ref.watch(recoveryReviewRepositoryProvider);
  return RecoveryReviewPublisher(
    owner: () async {
      final user = await storage.getUserSnapshot();
      if (user == null || (user.companyId ?? '').isEmpty) return null;
      return OperationScope(user.companyId!, user.id);
    },
    list: (scope) => store.listPendingActions(
      companyId: scope.companyId, userId: scope.userId, limit: null,
    ),
    submit: repository.submit,
  );
});

/// Publishes summaries only, never money. Each user publishes their own outbox;
/// only the administrator may inspect company cases or make decisions.
class RecoveryReviewPublisher {
  RecoveryReviewPublisher({required this.owner, required this.list,
    required this.submit, DateTime Function()? clock})
      : clock = clock ?? (() => DateTime.now().toUtc());
  final Future<OperationScope?> Function() owner;
  final Future<List<PendingSyncAction>> Function(OperationScope) list;
  final Future<void> Function(PendingSyncAction) submit;
  final DateTime Function() clock;
  bool _running = false;

  Future<void> runOnce() async {
    if (_running) return;
    _running = true;
    try {
      final scope = await owner();
      if (scope == null) return;
      await scope.run(() async {
        final prefs = await SharedPreferences.getInstance();
        final key = UatIdentity.storageKey('reviewPublisher:${scope.companyId}:${scope.userId}');
        final raw = prefs.getString(key);
        var state = <String, dynamic>{};
        if (raw != null) {
          try { state = Map<String, dynamic>.from(jsonDecode(raw) as Map); }
          on FormatException { /* Only the polling checkpoint is rebuilt. */ }
          on TypeError { /* Original financial evidence is never changed. */ }
        }
        final now = clock().millisecondsSinceEpoch;
        if ((state['pauseUntil'] as num? ?? 0) > now) return;
        final records = Map<String, dynamic>.from(state['records'] as Map? ?? {});
        final actions = await list(scope);
        var submitted = 0;
        for (final action in actions) {
          if (action.companyId != scope.companyId || action.userId != scope.userId ||
              !RecoveryReviewRepository.types.contains(action.type) ||
              action.isAutomaticallyRetryable ||
              !{'requires_action', 'failed', 'conflict', 'obsolete'}.contains(action.status)) { continue; }
          // A malformed legacy incident must not starve valid new incidents.
          String signature;
          try {
            signature = sha256.convert(utf8.encode(jsonEncode(
              RecoveryReviewRepository.requestFor(action),
            ))).toString();
          } catch (_) { continue; }
          final saved = Map<String, dynamic>.from(records[action.id] as Map? ?? {});
          if (saved['signature'] == signature &&
              (saved['rejected'] == true || (saved['nextAt'] as num? ?? 0) > now)) { continue; }
          if (submitted >= 25) break;
          final current = await owner();
          if (current?.companyId != scope.companyId || current?.userId != scope.userId) break;
          submitted++;
          var failures = saved['signature'] == signature ? (saved['failures'] as num? ?? 0).toInt() : 0;
          final record = <String, dynamic>{'signature': signature};
          try {
            await submit(action);
            record['nextAt'] = now + const Duration(minutes: 5).inMilliseconds;
          } catch (error) {
            failures++;
            final status = error is DioException ? error.response?.statusCode : null;
            record['failures'] = failures;
            record['rejected'] = {400, 403, 409, 422}.contains(status);
            final delay = Duration(seconds: (30 * failures).clamp(30, 900));
            final retry = error is DioException
                ? parseRetryAfter(error.response?.headers.value('retry-after'), now: clock()) : null;
            final next = now + (retry ?? delay).inMilliseconds;
            record['nextAt'] = next;
            if (status == 429 || status == 401 || status == null || status >= 500) {
              state['pauseUntil'] = next;
            }
          }
          records[action.id] = record;
          state['records'] = records;
          if (!await prefs.setString(key, jsonEncode(state))) {
            throw StateError('No se pudo conservar el estado de publicación.');
          }
          if ((state['pauseUntil'] as num? ?? 0) > now) break;
        }
      });
    } finally { _running = false; }
  }
}
