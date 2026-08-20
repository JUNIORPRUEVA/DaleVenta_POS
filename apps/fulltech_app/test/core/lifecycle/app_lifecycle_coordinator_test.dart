import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:daleventa_pos/core/lifecycle/app_lifecycle_coordinator.dart';

void main() {
  test('session validation is single-flight and throttled after success', () async {
    var now = DateTime(2026, 8, 19, 12);
    final coordinator = AppLifecycleCoordinator(now: () => now);
    final completer = Completer<Object?>();
    var calls = 0;

    final first = coordinator.runSessionValidation(() {
      calls++;
      return completer.future;
    });
    final second = coordinator.runSessionValidation(() async {
      calls++;
      return 'unexpected';
    });

    expect(identical(first, second), isTrue);
    expect(calls, 1);

    completer.complete('user');
    await first;
    now = now.add(const Duration(minutes: 1));
    await coordinator.runSessionValidation(() async {
      calls++;
      return 'throttled';
    });
    expect(calls, 1);

    now = now.add(const Duration(minutes: 1));
    await coordinator.runSessionValidation(() async {
      calls++;
      return 'after-throttle';
    });
    expect(calls, 2);
  });

  test('license validation is single-flight and throttled independently', () async {
    var now = DateTime(2026, 8, 19, 12);
    final coordinator = AppLifecycleCoordinator(now: () => now);
    final completer = Completer<bool>();
    var calls = 0;

    final first = coordinator.runLicenseValidation(() {
      calls++;
      return completer.future;
    });
    final second = coordinator.runLicenseValidation(() async {
      calls++;
      return true;
    });

    expect(identical(first, second), isTrue);
    expect(calls, 1);
    completer.complete(true);
    await first;

    now = now.add(const Duration(minutes: 1));
    await coordinator.runLicenseValidation(() async {
      calls++;
      return true;
    });
    expect(calls, 1);

    now = now.add(const Duration(minutes: 1));
    await coordinator.runLicenseValidation(() async {
      calls++;
      return true;
    });
    expect(calls, 2);
  });

  test('pending sync is single-flight', () async {
    final coordinator = AppLifecycleCoordinator();
    final completer = Completer<void>();
    var calls = 0;

    final first = coordinator.runPendingSync(() {
      calls++;
      return completer.future;
    });
    final second = coordinator.runPendingSync(() async {
      calls++;
    });

    expect(identical(first, second), isTrue);
    expect(calls, 1);
    completer.complete();
    await first;
  });

  test('update checks are limited to the lifecycle throttle window', () async {
    var now = DateTime(2026, 8, 19, 12);
    final coordinator = AppLifecycleCoordinator(now: () => now);
    var calls = 0;

    await coordinator.runUpdateCheck(() async => calls++);
    await coordinator.runUpdateCheck(() async => calls++);
    expect(calls, 1);

    now = now.add(const Duration(minutes: 29));
    await coordinator.runUpdateCheck(() async => calls++);
    expect(calls, 1);

    now = now.add(const Duration(minutes: 1));
    await coordinator.runUpdateCheck(() async => calls++);
    expect(calls, 2);
  });
}
