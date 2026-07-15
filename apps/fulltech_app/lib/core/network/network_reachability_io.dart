import 'dart:async';
import 'dart:io';

import 'network_probe_result.dart';

class _CachedProbe {
  final NetworkProbeResult result;
  final DateTime expiresAt;

  const _CachedProbe({required this.result, required this.expiresAt});
}

class NetworkReachability {
  static const Duration _lookupTimeout = Duration(seconds: 3);
  static const Duration _cacheTtl = Duration(seconds: 8);

  final Map<String, _CachedProbe> _cache = <String, _CachedProbe>{};

  Future<NetworkProbeResult> probe(Uri uri) async {
    final host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return const NetworkProbeResult(
        status: NetworkProbeStatus.dnsFailure,
        isReachable: false,
        detail: 'The configured API host is empty.',
      );
    }

    final cached = _cache[host];
    final now = DateTime.now();
    if (cached != null && now.isBefore(cached.expiresAt)) {
      return cached.result;
    }

    final result = await _probeHost(host);
    _cache[host] = _CachedProbe(result: result, expiresAt: now.add(_cacheTtl));
    return result;
  }

  Future<NetworkProbeResult> _probeHost(String host) async {
    try {
      final records = await InternetAddress.lookup(
        host,
      ).timeout(_lookupTimeout);
      if (records.isEmpty) {
        return NetworkProbeResult(
          status: NetworkProbeStatus.dnsFailure,
          isReachable: false,
          detail: 'DNS lookup returned no records for $host.',
        );
      }

      return NetworkProbeResult(
        status: NetworkProbeStatus.connected,
        isReachable: true,
        detail: 'Host $host resolved successfully.',
      );
    } on TimeoutException {
      return NetworkProbeResult(
        status: NetworkProbeStatus.timeout,
        isReachable: false,
        detail: 'DNS lookup timed out for $host.',
      );
    } on SocketException catch (error) {
      final internetAvailable = await _resolvePublicHost();
      return NetworkProbeResult(
        status: internetAvailable
            ? NetworkProbeStatus.dnsFailure
            : NetworkProbeStatus.noInternet,
        isReachable: false,
        detail: error.message,
      );
    }
  }

  Future<bool> _resolvePublicHost() async {
    try {
      final records = await InternetAddress.lookup(
        'cloudflare.com',
      ).timeout(_lookupTimeout);
      return records.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
