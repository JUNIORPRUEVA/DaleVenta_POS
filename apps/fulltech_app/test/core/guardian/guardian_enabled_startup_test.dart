import 'package:daleventa_pos/core/guardian/guardian_config.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with --dart-define=GUARDIAN_ENABLED=true: debug defaults otherwise skip
// the exact configuration branch used by real release startup.
void main() {
  test('enabled Guardian configuration is safe before preferences and runApp', () {
    const enabled = bool.fromEnvironment('GUARDIAN_ENABLED');
    final config = GuardianConfig.fromEnvironment();
    expect(config.enabled, enabled);
    expect(config.endpointPath, '/guardian/incidents');
    expect(config.maxEvents, 200);
    expect(config.maxBytes, 5242880);
    expect(config.batchSize, 20);
    expect(config.minSeverityToPersist, 'SEV3');
  });
}
