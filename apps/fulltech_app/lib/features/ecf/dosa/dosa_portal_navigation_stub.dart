/// Implementación para plataformas sin navegador (Windows, Android, iOS).
///
/// No hay pestañas: el portal se abre con el navegador del sistema.
Future<bool> navigateSameTabImpl(String url) async => false;
