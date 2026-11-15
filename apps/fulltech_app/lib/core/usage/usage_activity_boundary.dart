import 'dart:async';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../api/env.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';
import '../config/uat_network_guard.dart';
import 'foreground_activity_meter.dart';

const _enabled = bool.fromEnvironment(
  'ACTIVITY_REPORTING_ENABLED',
  defaultValue: false,
);

class UsageActivityBoundary extends ConsumerWidget {
  const UsageActivityBoundary({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_enabled) return child;
    final auth = ref.watch(authStateProvider), user = auth.user;
    final identity =
        auth.isAuthenticated &&
            user != null &&
            (user.companyId?.isNotEmpty ?? false)
        ? '${user.companyId}:${user.id}'
        : null;
    return _ActivityObserver(
      identity: identity,
      storage: ref.watch(tokenStorageProvider),
      child: child,
    );
  }
}

class _ActivityObserver extends StatefulWidget {
  const _ActivityObserver({
    required this.identity,
    required this.storage,
    required this.child,
  });
  final String? identity;
  final TokenStorage storage;
  final Widget child;
  @override
  State<_ActivityObserver> createState() => _ActivityObserverState();
}

class _ActivityObserverState extends State<_ActivityObserver>
    with WidgetsBindingObserver {
  final _clock = Stopwatch()..start();
  final _meter = ForegroundActivityMeter();
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      sendTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      followRedirects: false,
    ),
  );
  Timer? _timer;
  String _stream = '',
      _version = const String.fromEnvironment(
        'APP_VERSION',
        defaultValue: 'unknown',
      );
  int _sequence = 0, _generation = 0, _retryAt = 0;
  bool _busy = false, _lastActive = false;
  int get _now => _clock.elapsedMilliseconds;
  String get _platform => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS => 'ios',
          TargetPlatform.windows => 'windows',
          TargetPlatform.macOS => 'macos',
          TargetPlatform.linux => 'linux',
          _ => 'unknown',
        };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    _reset();
    unawaited(_loadVersion());
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_send()),
    );
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) _version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Optional reporting must never interrupt the POS when metadata is unavailable.
    }
  }

  @override
  void didUpdateWidget(covariant _ActivityObserver old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity) _reset();
  }

  void _reset() {
    _generation++;
    _sequence = 0;
    _lastActive = false;
    _retryAt = 0;
    final random = Random.secure(),
        b = List.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    _stream =
        '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
    _meter.reset(_now);
    _meter.foreground(
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      _now,
    );
    unawaited(_send());
  }

  bool _key(KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) _meter.interact(_now);
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _meter.foreground(state == AppLifecycleState.resumed, _now);
    unawaited(_send());
  }

  Future<void> _send() async {
    if (!mounted || widget.identity == null || _busy || _now < _retryAt) return;
    _busy = true;
    final generation = _generation;
    try {
      final token = await widget.storage.getAccessToken();
      if (!mounted ||
          generation != _generation ||
          token == null ||
          token.isEmpty) {
        return;
      }
      final sample = _meter.sample(_now);
      if (!sample.active && !_lastActive && sample.milliseconds == 0) return;
      _lastActive = sample.active;
      final uri = Uri.parse(
        '${Env.apiBaseUrl.replaceAll(RegExp(r'/+$'), '')}/activity/pulse',
      );
      UatNetworkGuard.assertAllowedUri(uri, key: 'ACTIVITY');
      await _dio.postUri<Object?>(
        uri,
        data: {
          'streamId': _stream,
          'sequence': ++_sequence,
          'active': sample.active,
          'activeMilliseconds': sample.milliseconds,
          'platform': _platform,
          'appVersion': _version,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      if (generation == _generation) {
        _retryAt =
            _now +
            ([404, 503].contains(e.response?.statusCode) ? 600000 : 60000);
      }
    } catch (_) {
      if (generation == _generation) _retryAt = _now + 60000;
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _dio.close(force: true);
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) => _meter.interact(_now),
    onPointerMove: (_) => _meter.interact(_now),
    onPointerHover: (_) => _meter.interact(_now),
    onPointerSignal: (_) => _meter.interact(_now),
    child: widget.child,
  );
}
