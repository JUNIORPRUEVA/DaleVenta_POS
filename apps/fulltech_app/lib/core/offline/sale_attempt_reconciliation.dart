import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug/trace_log.dart';
import 'pending_sync_action.dart';

/// Conciliación de intentos de cobro (`sales.attempt`) con resultado incierto.
///
/// El intento se guarda ANTES de enviar la venta para no cobrar dos veces. Si la
/// respuesta se pierde, queda en `requires_action` y hasta ahora solo se
/// resolvía con soporte presencial.
///
/// Este reconciliador pregunta al backend (endpoint de solo lectura) qué sabe de
/// ese `clientRequestId` y actúa así:
///
///  - CONFIRMED            → el cobro YA está registrado: se guarda evidencia y
///                           se retira el aviso. No se reenvía nada.
///  - DEFINITIVELY_REJECTED→ la operación existe pero fue anulada/borrada: se
///                           guarda evidencia y se retira el aviso.
///  - NOT_FOUND / UNKNOWN  → se conserva el intento INTACTO (payload, id y
///                           fecha). Nunca se reintenta ni se descarta solo.
///
/// Reglas de seguridad:
///  - Jamás reenvía el cobro ni crea ventas.
///  - Nunca limpia `pending_actions` en bloque.
///  - Una sola verificación en vuelo por intento (evita carreras).
///  - La evidencia se conserva incluso cuando el aviso se retira.
enum SaleAttemptReconciliationStatus {
  confirmed,
  definitivelyRejected,
  notFound,
  unknown;

  static SaleAttemptReconciliationStatus? parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'CONFIRMED':
        return SaleAttemptReconciliationStatus.confirmed;
      case 'DEFINITIVELY_REJECTED':
        return SaleAttemptReconciliationStatus.definitivelyRejected;
      case 'NOT_FOUND':
        return SaleAttemptReconciliationStatus.notFound;
      case 'UNKNOWN':
        return SaleAttemptReconciliationStatus.unknown;
      default:
        return null;
    }
  }

  /// Solo estos dos estados permiten retirar el aviso del intento.
  bool get resolvesAttempt =>
      this == SaleAttemptReconciliationStatus.confirmed ||
      this == SaleAttemptReconciliationStatus.definitivelyRejected;
}

/// Respuesta del backend, ya normalizada.
class SaleAttemptReconciliationResult {
  const SaleAttemptReconciliationResult({
    required this.status,
    required this.clientRequestId,
    this.saleId,
    this.totalSold,
    this.paymentMethod,
    this.matchesExpected,
    this.movementId,
    this.guidance,
    this.voided = false,
  });

  final SaleAttemptReconciliationStatus status;
  final String clientRequestId;
  final String? saleId;
  final double? totalSold;
  final String? paymentMethod;
  final bool? matchesExpected;
  final String? movementId;

  /// Motivo que da el servidor (`ALREADY_REGISTERED`, `REGISTERED_THEN_VOIDED`,
  /// `NOT_REGISTERED`, `INCONCLUSIVE`). Se guarda como evidencia.
  final String? guidance;

  /// La venta se registró pero después fue anulada o borrada. Sigue siendo un
  /// registro confirmado: NO es un cobro rechazado.
  final bool voided;

  static SaleAttemptReconciliationResult? fromJson(Map<String, dynamic> json) {
    final status = SaleAttemptReconciliationStatus.parse(
      json['status']?.toString(),
    );
    if (status == null) return null;
    final sale = json['sale'];
    final saleMap = sale is Map ? sale.cast<String, dynamic>() : null;
    final movement = json['movement'];
    final movementMap = movement is Map
        ? movement.cast<String, dynamic>()
        : null;
    return SaleAttemptReconciliationResult(
      status: status,
      clientRequestId: (json['clientRequestId'] ?? '').toString(),
      saleId: saleMap?['id']?.toString(),
      totalSold: _toDouble(saleMap?['totalSold']),
      paymentMethod: saleMap?['paymentMethod']?.toString(),
      matchesExpected: json['matchesExpected'] is bool
          ? json['matchesExpected'] as bool
          : null,
      movementId: movementMap?['id']?.toString(),
      guidance: json['guidance']?.toString(),
      voided: json['voided'] == true,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// Consulta al backend. Devuelve `null` cuando no se pudo consultar
/// (sin red, 5xx, respuesta inválida): eso NUNCA resuelve el intento.
typedef SaleAttemptLookup =
    Future<Map<String, dynamic>?> Function(
      String clientRequestId,
      double? expectedTotalSold,
    );

class SaleAttemptReconciliationSummary {
  const SaleAttemptReconciliationSummary({
    this.confirmed = 0,
    this.rejected = 0,
    this.inconclusive = 0,
    this.unreachable = 0,
  });

  final int confirmed;
  final int rejected;
  final int inconclusive;
  final int unreachable;

  int get resolved => confirmed + rejected;
  bool get hasChanges => resolved > 0;
}

class SaleAttemptReconciler {
  SaleAttemptReconciler({
    required this.lookup,
    required this.listAttempts,
    required this.removeAttempt,
  });

  final SaleAttemptLookup lookup;

  /// Intentos pendientes del ámbito actual (normalmente la cola local).
  final Future<List<PendingSyncAction>> Function({
    String? companyId,
    String? userId,
  })
  listAttempts;

  /// Retira un intento CONCILIADO. Nunca se usa para limpiar en bloque.
  final Future<void> Function(String id) removeAttempt;

  /// Mecanismo y versión, para dejar rastro de qué concilió cada intento.
  static const String mechanism = 'sale-attempt-reconciliation-v1';
  static const String attemptType = 'sales.attempt';
  static const String _evidenceKey = 'sales.reconciliation.evidence.v1';
  static const int _maxEvidenceEntries = 50;

  /// Verificaciones en curso: evita que dos pasadas simultáneas toquen el mismo
  /// intento (doble toque del botón, arranque + reconexión, etc.).
  static final Set<String> _inFlight = <String>{};

  @visibleForTesting
  static void resetInFlightForTests() => _inFlight.clear();

  /// Verifica un intento concreto. Devuelve `null` si no se pudo consultar.
  Future<SaleAttemptReconciliationResult?> verify(
    PendingSyncAction action,
  ) async {
    if (action.type != attemptType) return null;

    final requestId = _requestIdOf(action);
    if (requestId.isEmpty) {
      TraceLog.log('reconcile', 'attempt.sin.identificador id=${action.id}');
      return null;
    }
    if (!_inFlight.add(action.id)) {
      TraceLog.log('reconcile', 'attempt.ya.en.curso id=${action.id}');
      return null;
    }

    try {
      final expected = _expectedTotalOf(action);
      Map<String, dynamic>? raw;
      try {
        raw = await lookup(requestId, expected);
      } catch (error, stack) {
        TraceLog.log('reconcile', 'attempt.consulta.fallida id=${action.id}');
        debugPrint('[reconcile] consulta fallida: $error\n$stack');
        return null;
      }
      if (raw == null) {
        TraceLog.log('reconcile', 'attempt.sin.respuesta id=${action.id}');
        return null;
      }

      final result = SaleAttemptReconciliationResult.fromJson(raw);
      if (result == null) {
        TraceLog.log('reconcile', 'attempt.respuesta.invalida id=${action.id}');
        return null;
      }

      await _recordEvidence(action, requestId, result);

      if (result.status.resolvesAttempt) {
        // Evidencia guardada ANTES de retirar el aviso: nunca se pierde el rastro.
        await removeAttempt(action.id);
        TraceLog.log(
          'reconcile',
          'attempt.resuelto id=${action.id} status=${result.status.name}',
        );
      } else {
        TraceLog.log(
          'reconcile',
          'attempt.conservado id=${action.id} status=${result.status.name}',
        );
      }
      return result;
    } finally {
      _inFlight.remove(action.id);
    }
  }

  /// Verifica todos los intentos pendientes del ámbito indicado.
  Future<SaleAttemptReconciliationSummary> syncPendingAttempts({
    String? companyId,
    String? userId,
  }) async {
    final actions = await listAttempts(companyId: companyId, userId: userId);
    var confirmed = 0;
    var rejected = 0;
    var inconclusive = 0;
    var unreachable = 0;

    for (final action in actions) {
      if (action.type != attemptType) continue;
      final result = await verify(action);
      if (result == null) {
        unreachable++;
        continue;
      }
      switch (result.status) {
        case SaleAttemptReconciliationStatus.confirmed:
          confirmed++;
        case SaleAttemptReconciliationStatus.definitivelyRejected:
          rejected++;
        case SaleAttemptReconciliationStatus.notFound:
        case SaleAttemptReconciliationStatus.unknown:
          inconclusive++;
      }
    }

    return SaleAttemptReconciliationSummary(
      confirmed: confirmed,
      rejected: rejected,
      inconclusive: inconclusive,
      unreachable: unreachable,
    );
  }

  String _requestIdOf(PendingSyncAction action) {
    final fromKey = (action.idempotencyKey ?? '').trim();
    if (fromKey.isNotEmpty) {
      // El id local puede venir como `sales.attempt:<requestId>`.
      const prefix = '$attemptType:';
      if (fromKey.startsWith(prefix)) {
        return fromKey.substring(prefix.length).trim();
      }
      return fromKey;
    }
    return (action.entityId ?? '').trim();
  }

  double? _expectedTotalOf(PendingSyncAction action) {
    final raw = action.payload['expectedTotalSold'];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }

  Future<void> _recordEvidence(
    PendingSyncAction action,
    String requestId,
    SaleAttemptReconciliationResult result,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_evidenceKey);
      final decoded = raw == null || raw.trim().isEmpty
          ? const <dynamic>[]
          : jsonDecode(raw);
      final rows = decoded is List ? decoded : const <dynamic>[];
      final entry = <String, dynamic>{
        'actionId': action.id,
        'clientRequestId': requestId,
        'status': result.status.name,
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
        'createdAt': action.createdAt.toUtc().toIso8601String(),
        'saleId': result.saleId,
        'totalSold': result.totalSold,
        'paymentMethod': result.paymentMethod,
        'movementId': result.movementId,
        'guidance': result.guidance,
        'voided': result.voided,
        'mechanism': mechanism,
      };
      final next = <dynamic>[entry, ...rows];
      if (next.length > _maxEvidenceEntries) {
        next.removeRange(_maxEvidenceEntries, next.length);
      }
      await prefs.setString(_evidenceKey, jsonEncode(next));
    } catch (error, stack) {
      // La evidencia es importante, pero no debe impedir resolver el aviso.
      debugPrint('[reconcile] no se pudo guardar evidencia: $error\n$stack');
    }
  }
}
