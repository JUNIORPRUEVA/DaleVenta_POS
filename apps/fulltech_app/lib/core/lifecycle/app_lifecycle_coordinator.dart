import 'dart:async';

class AppLifecycleCoordinator {
  AppLifecycleCoordinator({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const sessionThrottle = Duration(minutes: 2);
  static const licenseThrottle = Duration(minutes: 2);
  static const updateThrottle = Duration(minutes: 30);

  final DateTime Function() _now;
  DateTime? _lastSessionValidationAt;
  DateTime? _lastLicenseValidationAt;
  DateTime? _lastUpdateCheckAt;
  Future<Object?>? _sessionValidationFuture;
  Future<bool>? _licenseValidationFuture;
  Future<void>? _syncFuture;

  Future<Object?> runSessionValidation(
    Future<Object?> Function() task,
  ) {
    final existing = _sessionValidationFuture;
    if (existing != null) return existing;

    final last = _lastSessionValidationAt;
    if (last != null && _now().difference(last) < sessionThrottle) {
      return Future<Object?>.value();
    }

    late final Future<Object?> future;
    future = task().then((result) {
      if (result != null) _lastSessionValidationAt = _now();
      return result;
    }).whenComplete(() {
      if (identical(_sessionValidationFuture, future)) {
        _sessionValidationFuture = null;
      }
    });
    _sessionValidationFuture = future;
    return future;
  }

  Future<bool> runLicenseValidation(Future<bool> Function() task) {
    final existing = _licenseValidationFuture;
    if (existing != null) return existing;

    final last = _lastLicenseValidationAt;
    if (last != null && _now().difference(last) < licenseThrottle) {
      return Future<bool>.value(false);
    }

    late final Future<bool> future;
    future = task().then((succeeded) {
      if (succeeded) _lastLicenseValidationAt = _now();
      return succeeded;
    }).whenComplete(() {
      if (identical(_licenseValidationFuture, future)) {
        _licenseValidationFuture = null;
      }
    });
    _licenseValidationFuture = future;
    return future;
  }

  Future<void> runPendingSync(Future<void> Function() task) {
    final existing = _syncFuture;
    if (existing != null) return existing;

    late final Future<void> future;
    future = task().whenComplete(() {
      if (identical(_syncFuture, future)) _syncFuture = null;
    });
    _syncFuture = future;
    return future;
  }

  Future<void> runUpdateCheck(Future<void> Function() task) {
    final last = _lastUpdateCheckAt;
    if (last != null && _now().difference(last) < updateThrottle) {
      return Future<void>.value();
    }

    _lastUpdateCheckAt = _now();
    return task();
  }
}
