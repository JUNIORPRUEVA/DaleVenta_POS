import 'dart:async';

import 'guardian_enrollment.dart';
import 'guardian_event.dart';
import 'guardian_install_credential_store.dart';
import 'guardian_transport.dart';

/// Transporte con **auto-enrolamiento diferido**.
///
/// Problema que resuelve: una instalación que arranca sin red (o antes de que la
/// empresa forme parte del despliegue) no puede obtener su credencial de
/// instalación en el arranque. Antes eso dejaba el equipo sin monitoreo hasta el
/// siguiente inicio de la app.
///
/// Comportamiento:
/// 1. Al primer envío intenta obtener la credencial (enrolamiento diferido). Si
///    no hay sesión, no hay red o la empresa aún no está habilitada, cae al
///    transporte de sesión: **el POS nunca se bloquea**.
/// 2. Con credencial, envía por el canal de máquina.
/// 3. Si el servidor rechaza la credencial (revocada o caducada), se limpia y el
///    siguiente envío vuelve a intentar enrolarse, usando la sesión mientras
///    tanto.
class AutoEnrollingGuardianTransport implements GuardianTransport {
  AutoEnrollingGuardianTransport({
    required this.enrollment,
    required this.credentialStore,
    required this.sessionTransport,
    required this.machineTransportFactory,
    this.installId = '',
    this.platform,
    this.appVersion,
    this.minIntervalBetweenEnrollmentAttempts = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GuardianEnrollmentService enrollment;
  final GuardianInstallCredentialStore credentialStore;
  final GuardianTransport sessionTransport;

  /// Construye el transporte de máquina para una credencial concreta.
  final GuardianTransport Function(String credential) machineTransportFactory;

  final String installId;
  final String? platform;
  final String? appVersion;
  final Duration minIntervalBetweenEnrollmentAttempts;

  final DateTime Function() _clock;

  GuardianInstallCredential? _cached;
  DateTime? _lastEnrollmentAttemptAt;
  String? _lastMachineCredential;
  GuardianTransport? _machineTransport;

  /// Solo para pruebas.
  int get debugEnrollmentAttempts => _enrollmentAttempts;
  int _enrollmentAttempts = 0;

  Future<GuardianInstallCredential?> _ensureCredential() async {
    final cached = _cached;
    if (cached != null && cached.isValid()) return cached;

    final now = _clock();
    final last = _lastEnrollmentAttemptAt;
    if (last != null && now.difference(last) < minIntervalBetweenEnrollmentAttempts) {
      return null;
    }
    _lastEnrollmentAttemptAt = now;
    _enrollmentAttempts += 1;

    try {
      final credential = await enrollment.ensureCredential(
        installId: installId,
        platform: platform,
        appVersion: appVersion,
      );
      if (credential != null && credential.isValid()) {
        _cached = credential;
        return credential;
      }
    } catch (_) {
      // Silencioso a propósito: el fallback de sesión mantiene la telemetría.
    }
    return null;
  }

  GuardianTransport _machineFor(String credential) {
    if (_machineTransport != null && _lastMachineCredential == credential) {
      return _machineTransport!;
    }
    _lastMachineCredential = credential;
    _machineTransport = machineTransportFactory(credential);
    return _machineTransport!;
  }

  /// Invalida la credencial en memoria (rechazo del servidor o revocación).
  void invalidateCredential() {
    _cached = null;
    _lastMachineCredential = null;
    _machineTransport = null;
  }

  @override
  Future<GuardianSendResult> send(List<GuardianEvent> events) async {
    if (events.isEmpty) return const GuardianSendResult(acked: <String>[]);

    final credential = await _ensureCredential();
    if (credential == null) {
      return sessionTransport.send(events);
    }

    final result = await _machineFor(credential.credential).send(events);
    if (result.reason == 'HTTP_401' || result.reason == 'HTTP_403') {
      // Credencial revocada/caducada: se descarta y se usa la sesión.
      invalidateCredential();
      unawaited(credentialStore.clear());
      return sessionTransport.send(events);
    }
    return result;
  }
}
