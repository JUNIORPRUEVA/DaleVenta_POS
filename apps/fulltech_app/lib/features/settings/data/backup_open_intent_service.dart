import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackupOpenIntentService {
  BackupOpenIntentService({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const _channelName = 'com.daleventa.pos/backup_open';
  static const _defaultChannel = MethodChannel(_channelName);
  static final _openedController = StreamController<String>.broadcast();
  static List<String> _startupArguments = const [];
  static String? _pendingRuntimePath;
  static bool _listenerInitialized = false;

  final MethodChannel _channel;

  static void setStartupArguments(List<String> arguments) {
    _startupArguments = List.unmodifiable(arguments);
  }

  static bool get hasStartupBackupPath =>
      _firstBackupPathFrom(_startupArguments) != null ||
      _pendingRuntimePath != null;

  static Stream<String> get openedBackups => _openedController.stream;

  static void initializeListener() {
    if (_listenerInitialized || kIsWeb) return;
    _listenerInitialized = true;
    _defaultChannel.setMethodCallHandler((call) async {
      if (call.method != 'backupOpened') return null;
      final path = call.arguments?.toString().trim();
      if (path == null || path.isEmpty) return null;
      _pendingRuntimePath = path;
      _openedController.add(path);
      return null;
    });
  }

  static Future<void> primeInitialBackupPath() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final value = await _defaultChannel.invokeMethod<String>(
      'takeInitialBackupPath',
    );
    final path = value?.trim();
    if (path == null || path.isEmpty || path == _pendingRuntimePath) return;
    _pendingRuntimePath = path;
    _openedController.add(path);
  }

  Future<String?> takeInitialBackupPath() async {
    final fromArgs = _firstBackupPathFrom(_startupArguments);
    if (fromArgs != null) {
      _startupArguments = const [];
      return fromArgs;
    }
    final pending = _pendingRuntimePath;
    if (pending != null && pending.isNotEmpty) {
      _pendingRuntimePath = null;
      return pending;
    }
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return null;
    final value = await _channel.invokeMethod<String>('takeInitialBackupPath');
    final path = value?.trim();
    if (path == null || path.isEmpty) return null;
    return path;
  }

  static bool isAppOwnedTemporaryBackupPath(String? path) {
    final value = path?.trim();
    if (value == null || value.isEmpty) return false;
    final normalized = value.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/cache/backup-open/');
  }

  static Future<bool> cleanupTemporaryBackupCopy(String? path) async {
    final value = path?.trim();
    if (kIsWeb || value == null || value.isEmpty) return false;
    if (!isAppOwnedTemporaryBackupPath(value)) return false;
    try {
      final file = File(value);
      if (await file.exists()) {
        await file.delete();
      }
      if (_pendingRuntimePath == value) {
        _pendingRuntimePath = null;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static String? _firstBackupPathFrom(List<String> arguments) {
    for (final argument in arguments) {
      final value = argument.trim();
      if (value.toLowerCase().endsWith('.dvbackup') ||
          value.toLowerCase().endsWith('.zip')) {
        return value;
      }
    }
    return null;
  }
}
