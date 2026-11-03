import 'package:flutter/widgets.dart';

import 'dosa_assistant_config.dart';
import 'dosa_assistant_events.dart';

/// Windows, Android e iOS: no hay contenedor nativo en esta fase.
///
/// No se añaden WebViews: el asistente se abre en el navegador externo
/// (`dosa_assistant_launcher.dart`) y al volver se recupera el progreso del
/// backend.
bool get dosaWizardSupported => false;

Widget buildDosaWizardView({
  required DosaAssistantConfig config,
  required void Function(DosaAssistantEvent) onEvent,
  required double height,
  Key? key,
}) {
  // No se monta nada: nunca se simula un asistente que no existe.
  return SizedBox.shrink(key: key);
}
