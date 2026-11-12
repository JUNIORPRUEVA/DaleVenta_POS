/// Configuración del onboarding de activación «Activa tu FullPOS».
///
/// La bienvenida y el panel usan el progreso real de activación. El asistente
/// antiguo ya no forma parte de las rutas de entrada.
class ActivationConfig {
  ActivationConfig._();

  /// El panel de activación está habilitado y es el recorrido de primera vez.
  static const bool useActivationPanel = true;
}
