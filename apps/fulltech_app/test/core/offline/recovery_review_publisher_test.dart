import 'dart:async';

import 'package:daleventa_pos/core/auth/operation_scope.dart';
import 'package:daleventa_pos/core/config/uat_identity.dart';
import 'package:daleventa_pos/core/offline/pending_sync_action.dart';
import 'package:daleventa_pos/core/offline/recovery_review_publisher.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  OperationScope? principal;
  late List<PendingSyncAction> rows;
  late List<String> sent;
  late Future<void> Function(PendingSyncAction) send;
  PendingSyncAction action(String id, {String user = 'cashier', String company = 'a',
    String status = 'requires_action', String type = 'sales.attempt'}) => PendingSyncAction(
    id: id, type: type, scope: 'sales', companyId: company, userId: user,
    idempotencyKey: id, status: status, attempts: 0, permanent: status != 'pending',
    payload: {'expectedTotalSold': 7, 'paymentMethod': 'cash'}, createdAt: now, updatedAt: now,
  );
  RecoveryReviewPublisher build() => RecoveryReviewPublisher(
    owner: () async => principal, list: (_) async => rows, clock: () => now,
    submit: (a) async {
      expect(OperationScope.current?.userId, principal?.userId);
      sent.add(a.id); await send(a);
    },
  );
  DioException http(int status, {String? retry}) => DioException(
    requestOptions: RequestOptions(path: '/recovery/reviews'),
    response: Response(requestOptions: RequestOptions(path: '/recovery/reviews'),
      statusCode: status, headers: Headers.fromMap({if (retry != null) 'retry-after': [retry]})),
    type: DioExceptionType.badResponse,
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 11, 20);
    principal = const OperationScope('a', 'cashier');
    rows = []; sent = []; send = (_) async {};
  });
  test('empty queue makes no requests; cashier publishes only owned blocked operations', () async {
    final publisher = build(); await publisher.runOnce(); expect(sent, isEmpty);
    rows = [action('own'), action('other-user', user: 'other'),
      action('foreign', company: 'b'), action('valid-sale', status: 'pending'),
      action('sending', status: 'syncing'), action('closed', status: 'review_resolved')];
    await publisher.runOnce(); expect(sent, ['own']);
  });
  test('damaged polling checkpoint is rebuilt without dropping the incident', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(UatIdentity.storageKey('reviewPublisher:a:cashier'), '{broken');
    rows = [action('one')]; await build().runOnce();
    expect(sent, ['one']); expect(rows.single.status, 'requires_action');
  });
  test('successful publication is idempotently polled after restart and five minutes', () async {
    rows = [action('one')]; await build().runOnce();
    await build().runOnce(); expect(sent, ['one']);
    now = now.add(const Duration(minutes: 5)); await build().runOnce();
    expect(sent, ['one', 'one']);
  });
  test('422 is permanent per snapshot and does not starve later incidents', () async {
    rows = [action('bad'), action('good')];
    send = (a) async {if (a.id == 'bad') throw http(422);};
    await build().runOnce(); now = now.add(const Duration(days: 2));
    await build().runOnce(); expect(sent, ['bad', 'good', 'good']);
    rows = [rows.first.copyWith(payload: {'expectedTotalSold': 8})];
    await build().runOnce(); expect(sent.last, 'bad');
  });
  for (final code in [400, 403, 409]) {
    test('$code preserves incident and does not automatically resubmit unchanged evidence', () async {
      rows = [action('bad'), action('good')];
      send = (a) async {if (a.id == 'bad') throw http(code);};
      await build().runOnce(); now = now.add(const Duration(hours: 1));
      await build().runOnce(); expect(sent, ['bad', 'good', 'good']);
      expect(rows.first.status, 'requires_action');
    });
  }
  test('429 Retry-After survives restart and does not block another tenant', () async {
    rows = [action('rate'), action('later')]; send = (_) async => throw http(429, retry: '120');
    await build().runOnce(); now = now.add(const Duration(seconds: 119));
    await build().runOnce(); expect(sent, ['rate']);
    principal = const OperationScope('b', 'cashier'); rows = [action('foreign-own', company: 'b')];
    send = (_) async {}; await build().runOnce(); expect(sent.last, 'foreign-own');
    principal = const OperationScope('a', 'cashier'); rows = [action('rate')];
    now = now.add(const Duration(seconds: 1)); await build().runOnce(); expect(sent.last, 'rate');
  });
  for (final code in [401, 503]) {
    test('$code pauses requests without resolving or deleting any incident', () async {
      rows = [action('one'), action('two')]; send = (_) async => throw http(code);
      await build().runOnce(); await build().runOnce(); expect(sent, ['one']);
      expect(rows.length, 2); now = now.add(const Duration(seconds: 31));
      send = (_) async {}; await build().runOnce(); expect(sent, ['one', 'one', 'two']);
    });
  }
  test('owner change during a request prevents the next old-owner request', () async {
    rows = [action('one'), action('two')];
    send = (_) async {principal = const OperationScope('b', 'new');};
    await build().runOnce(); expect(sent, ['one']);
  });
  test('single flight and bounded batches leave new incidents eligible on next pass', () async {
    rows = List.generate(27, (i) => action('row-$i'));
    final gate = Completer<void>(); send = (_) => gate.future;
    final publisher = build(); final first = publisher.runOnce();
    await Future<void>.delayed(Duration.zero); await publisher.runOnce();
    expect(sent.length, 1); gate.complete(); await first;
    expect(sent.length, 25); send = (_) async {}; await publisher.runOnce();
    expect(sent.length, 27);
  });
}
