import 'network_probe_result.dart';

class NetworkReachability {
  Future<NetworkProbeResult> probe(Uri uri) async {
    return NetworkProbeResult(
      status: NetworkProbeStatus.unsupported,
      isReachable: true,
      detail: 'Connectivity precheck is not supported on this platform.',
    );
  }
}
