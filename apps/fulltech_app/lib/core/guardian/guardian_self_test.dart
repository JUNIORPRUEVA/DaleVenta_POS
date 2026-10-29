import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'guardian_client.dart';
import 'guardian_config.dart';

/// Excepción sintética de la sonda UAT.
///
/// Existe solo en builds compilados con `--dart-define=GUARDIAN_SELFTEST=true`.
/// Es un fallo técnico **real** desde el punto de vista del runtime: se lanza
/// como error asíncrono no controlado y recorre el mismo camino que cualquier
/// otro fallo (zona raíz → `AppErrorReporter` → `GuardianReporter` → cola).
class SyntheticGuardianProbeException implements Exception {
  const SyntheticGuardianProbeException(this.marker);

  final String marker;

  @override
  String toString() => 'SyntheticGuardianProbeException($marker)';
}

/// Sonda de extremo a extremo para UAT (Windows/Android).
///
/// Reglas:
/// - Solo se activa con `--dart-define=GUARDIAN_SELFTEST=true`.
/// - Se ejecuta **una sola vez por instalación** (marcador en
///   `shared_preferences`, nunca en la base de datos de ventas).
/// - No crea ventas, pagos ni movimientos: solo un error técnico controlado.
/// - Nunca lanza hacia el arranque.
class GuardianSelfTest {
  static const _markerKey = 'daleventas.guardian.selftest.done.v1';
  static const Duration _delay = Duration(seconds: 4);

  static Future<void> maybeRun({
    required GuardianConfig config,
    required GuardianClient client,
    required String installId,
  }) async {
    if (!config.selfTest) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      // Marcador único por perfil: la sonda no puede repetirse nunca, ni
      // siquiera si cambia el identificador de instalación.
      if (prefs.getBool(_markerKey) == true) return;
      await prefs.setBool(_markerKey, true);
    } catch (_) {
      // Sin marcador persistente no se ejecuta: nunca se repite en bucle.
      return;
    }

    Timer(_delay, () {
      // Error asíncrono no controlado en la zona raíz: mismo camino que un
      // fallo real de la aplicación.
      throw const SyntheticGuardianProbeException('guardian-uat-selftest');
    });
  }
}
