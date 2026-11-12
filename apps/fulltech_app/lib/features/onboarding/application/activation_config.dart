/// Configuración del onboarding de activación «Activa tu FullPOS».
///
/// Existe para poder revertir el cambio de comportamiento de entrada al POS con
/// una sola constante, sin cirugía en el router ni en el backend.
class ActivationConfig {
  ActivationConfig._();

  /// El panel de activación está habilitado y es el recorrido de primera vez.
  static const bool useActivationPanel = true;

  /// Cuando es `true`, el asistente legacy de 4 pasos deja de **bloquear** la
  /// entrada al POS. Las empresas nuevas entrarían directo a vender y el panel
  /// de activación guiaría el resto sin cortar la operación.
  ///
  /// DESACTIVADO a propósito (validación pendiente). Motivos verificados:
  ///  - El asistente legacy es el único que captura datos de empresa
  ///    (nombre, RNC, teléfono, dirección) y la decisión fiscal inicial
  ///    (`taxEnabled`, `ncfEnabled`) antes de operar.
  ///  - Solo él lleva `onboardingStatus` a `COMPLETED`. Con el gate retirado, la
  ///    empresa quedaría en `WELCOME_PENDING` de forma indefinida y
  ///    `account_menu_screens.dart` seguiría mostrando el acceso al asistente.
  ///  - El nuevo panel no bloquea: deja vender sin RNC ni comprobantes.
  /// Se habilitará solo tras aprobación de producto y con esas garantías
  /// cubiertas por el panel.
  static const bool retireLegacyOnboardingGate = false;
}
