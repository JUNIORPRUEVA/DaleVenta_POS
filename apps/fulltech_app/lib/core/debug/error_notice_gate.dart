import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Límite de frecuencia de los avisos de error **recuperables**.
///
/// Reglas que implementa:
/// - Como máximo **un aviso por categoría y día local**.
/// - Si el cliente lo cierra, no reaparece ese día, **aunque reinicie** la app.
/// - Persistencia **independiente** del almacenamiento del actualizador (que es
///   justamente el que puede estar roto y no debe arrastrar a la UI).
/// - Nunca lanza y nunca entra en bucle: si la preferencia no se puede guardar,
///   se sigue usando el estado en memoria de esta sesión.
///
/// No se aplica a errores `fatal`: esos exigen intervención inmediata y deben
/// mostrarse siempre.
class ErrorNoticeGate {
  ErrorNoticeGate._();

  static final ErrorNoticeGate instance = ErrorNoticeGate._();

  static const String _keyPrefix = 'error_notice_last_shown.';

  final Map<String, String> _lastShownDay = <String, String>{};
  SharedPreferences? _prefs;
  bool _loaded = false;

  /// Carga las marcas persistidas. Se invoca en el arranque, antes de `runApp`.
  ///
  /// Si falla, se opera sólo en memoria: se prefiere un aviso controlado a un
  /// arranque roto.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      for (final key in prefs.getKeys()) {
        if (!key.startsWith(_keyPrefix)) continue;
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) {
          _lastShownDay[key.substring(_keyPrefix.length)] = value;
        }
      }
    } catch (error) {
      debugPrint('[ErrorNoticeGate] load failed: $error');
    }
  }

  /// `true` si el aviso de [category] puede mostrarse hoy.
  ///
  /// Sin categoría se permite siempre: la clasificación es responsabilidad del
  /// llamador y no se debe silenciar nada por omisión.
  bool shouldShow(String category) {
    final key = category.trim();
    if (key.isEmpty) return true;
    return _lastShownDay[key] != _today();
  }

  /// Marca el aviso como mostrado (o cerrado) durante el resto del día.
  void markShown(String category) {
    final key = category.trim();
    if (key.isEmpty) return;
    final today = _today();
    _lastShownDay[key] = today;

    final prefs = _prefs;
    if (prefs == null) return;
    // Sin `await` y con captura: un fallo al guardar la preferencia no puede
    // producir un reintento ni un aviso adicional.
    try {
      prefs
          .setString('$_keyPrefix$key', today)
          .catchError((Object _) => false);
    } catch (_) {
      // Ignorado a propósito.
    }
  }

  /// Sólo para pruebas: descarta el estado en memoria y la caché de preferencias.
  @visibleForTesting
  void resetForTest() {
    _lastShownDay.clear();
    _loaded = false;
    _prefs = null;
  }

  static String _today() {
    final now = DateTime.now();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${now.year}-$month-$day';
  }
}
