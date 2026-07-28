import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/startup/initial_release_check.dart';

void main() {
  test('waits for startup readiness before checking updates', () async {
    final events = <String>[];
    final startupCompleter = Completer<void>();

    final future = runInitialReleaseCheck(
      ensureStartupReady: () async {
        events.add('startup:start');
        await startupCompleter.future;
        events.add('startup:done');
      },
      checkForUpdates: () async {
        events.add('updates:check');
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(events, <String>['startup:start']);

    startupCompleter.complete();
    await future;

    expect(events, <String>['startup:start', 'startup:done', 'updates:check']);
  });

  test('still checks updates when startup readiness throws', () async {
    var checked = false;

    await runInitialReleaseCheck(
      ensureStartupReady: () async {
        throw StateError('env missing');
      },
      checkForUpdates: () async {
        checked = true;
      },
    );

    expect(checked, isTrue);
  });
}
