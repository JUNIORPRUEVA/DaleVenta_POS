import 'package:flutter/widgets.dart';

class UpdateGuardOverlay extends StatelessWidget {
  const UpdateGuardOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // Fase 4 deshabilita el overlay bloqueante anterior. La UI discreta de
    // READY_TO_INSTALL se implementa en una fase posterior.
    return const SizedBox.shrink();
  }
}
