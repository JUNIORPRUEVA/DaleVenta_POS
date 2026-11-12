import 'package:daleventa_pos/features/onboarding/application/activation_controller.dart';
import 'package:daleventa_pos/features/onboarding/data/activation_models.dart';

/// Non-onboarding tests must not start real activation HTTP requests/timers.
/// Activation behavior has its own fixtures in activation_entry_flow_test.
class InactiveActivationController extends ActivationController {
  @override
  Future<ActivationState?> build() async => null;
}
