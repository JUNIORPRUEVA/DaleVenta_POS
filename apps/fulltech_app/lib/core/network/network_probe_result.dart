enum NetworkProbeStatus {
  connected,
  noInternet,
  dnsFailure,
  timeout,
  unsupported,
}

class NetworkProbeResult {
  final NetworkProbeStatus status;
  final bool isReachable;
  final String detail;

  const NetworkProbeResult({
    required this.status,
    required this.isReachable,
    required this.detail,
  });
}
