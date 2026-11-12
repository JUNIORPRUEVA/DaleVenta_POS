/// Implementación para plataformas sin DOM (Android, iOS, Windows, tests).
///
/// El handoff de sesión solo aplica a Flutter Web, así que aquí no hay nada
/// que reescribir en el historial del navegador.
void replaceHistoryState(String path) {
  // Sin navegador: no-op intencional.
}
