/// Configuración del soporte oficial de FullPOS Cloud.
///
/// El número **no se inventa aquí**: es el que ya usa la app en
/// `features/auth/presentation/landing_screen.dart`
/// (`_supportPhoneDisplay` / `_supportWhatsappIntl`), en `main.dart`
/// (`LicensePurchaseOverlay._phone`), en `core/auth/auth_repository.dart`
/// y en `modules/cotizaciones/cotizaciones_screen.dart`.
///
/// Esta clase es la fuente única para el Asistente. Los demás usos existentes
/// se mantienen intactos (fuera del alcance de esta fase) y podrán migrarse a
/// esta constante en una tarea posterior.
class SupportConfig {
  const SupportConfig._();

  /// Número en formato internacional, sin `+` ni separadores (lo exige wa.me).
  static const String whatsappNumber = '18295319442';

  /// Número tal como se muestra al usuario.
  static const String phoneDisplay = '829-531-9442';

  /// Mensaje inicial del botón «Contactar por WhatsApp».
  static const String defaultGreeting =
      'Hola, necesito asistencia con FullPOS Cloud.';

  /// Construye la URI oficial de WhatsApp con el mensaje ya codificado.
  ///
  /// `Uri.https` codifica el query de forma segura (acentos, saltos de línea y
  /// símbolos), por lo que no se concatena texto a mano.
  static Uri whatsappUri(String message) {
    final text = message.trim().isEmpty ? defaultGreeting : message.trim();
    return Uri.https('wa.me', '/$whatsappNumber', {'text': text});
  }
}
