import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClientTelemetryHeaders {
  ClientTelemetryHeaders._();

  static final ClientTelemetryHeaders instance = ClientTelemetryHeaders._();

  static const _deviceIdKey = 'daleventas.usage.device_id.v1';

  Future<Map<String, String>>? _pending;
  Map<String, String>? _cached;

  Future<Map<String, String>> headers() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    _pending ??= _build().then((value) {
      _cached = value;
      return value;
    }).whenComplete(() {
      _pending = null;
    });
    return _pending!;
  }

  Future<Map<String, String>> _build() async {
    final platform = _platformCode();
    final family = _deviceFamily(platform);
    final installId = await _installId();
    final packageInfo = await PackageInfo.fromPlatform();
    final details = await _deviceDetails(platform);

    return {
      'x-client-platform': platform,
      'x-client-device-family': family,
      'x-client-device-id': installId,
      'x-client-app-version':
          '${packageInfo.version}+${packageInfo.buildNumber}',
      if (details.osVersion.isNotEmpty) 'x-client-os-version': details.osVersion,
      if (details.model.isNotEmpty) 'x-client-device-model': details.model,
    };
  }

  Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final value = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await prefs.setString(_deviceIdKey, value);
    return value;
  }

  Future<_ClientDeviceDetails> _deviceDetails(String platform) async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        return _ClientDeviceDetails(
          model: info.browserName.name,
          osVersion: info.platform ?? '',
        );
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          return _ClientDeviceDetails(
            model: _compact('${info.manufacturer} ${info.model}'),
            osVersion: info.version.release,
          );
        case TargetPlatform.iOS:
          final info = await plugin.iosInfo;
          return _ClientDeviceDetails(
            model: info.utsname.machine,
            osVersion: info.systemVersion,
          );
        case TargetPlatform.windows:
          final info = await plugin.windowsInfo;
          return _ClientDeviceDetails(
            model: info.productName,
            osVersion: info.displayVersion,
          );
        case TargetPlatform.macOS:
          final info = await plugin.macOsInfo;
          return _ClientDeviceDetails(
            model: info.model,
            osVersion: info.osRelease,
          );
        case TargetPlatform.linux:
          final info = await plugin.linuxInfo;
          return _ClientDeviceDetails(
            model: info.prettyName,
            osVersion: info.version ?? '',
          );
        case TargetPlatform.fuchsia:
          return _ClientDeviceDetails(model: platform, osVersion: '');
      }
    } catch (_) {
      return _ClientDeviceDetails(model: platform, osVersion: '');
    }
  }

  String _platformCode() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'unknown';
    }
  }

  String _deviceFamily(String platform) {
    if (platform == 'android' || platform == 'ios') return 'mobile';
    if (platform == 'web') return 'web';
    if (platform == 'windows' || platform == 'macos' || platform == 'linux') {
      return 'desktop';
    }
    return 'unknown';
  }

  String _compact(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');
}

class _ClientDeviceDetails {
  final String model;
  final String osVersion;

  const _ClientDeviceDetails({required this.model, required this.osVersion});
}
