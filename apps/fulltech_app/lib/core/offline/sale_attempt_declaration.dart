import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../api/api_routes.dart';
import 'pending_sync_action.dart';
import 'sync_queue_service.dart';

/// Declaración administrativa de un cobro con resultado incierto.
///
/// Cuando el backend no confirma un cobro, el encargado puede declarar «sí
/// recibí el dinero». Esa declaración es una AFIRMACIÓN HUMANA:
///
///  - NO reenvía el cobro,
///  - NO crea una venta, un pago, un movimiento de caja ni inventario,
///  - solo abre una OBLIGACIÓN DE CONCILIACIÓN administrativa en el servidor.
///
/// La declaración se guarda primero en la cola local (`pending_actions`) con su
/// propia clave de idempotencia, de modo que:
///  - si el equipo se apaga o se queda sin red, no se pierde;
///  - el reenvío exacto no duplica nada (ni local ni servidor);
///  - una corrección (otro importe u otra nota) queda registrada como una
///    declaración NUEVA, no sobrescribe la anterior.
class SaleAttemptDeclaration {
  const SaleAttemptDeclaration({
    required this.clientRequestId,
    required this.totalDeclared,
    required this.declaredAtUtc,
    this.paymentMethod,
    this.declaredByUserId,
    this.declaredByRole,
    this.note,
    this.operationFingerprint,
    this.attemptPayload,
  });

  /// Tipo de acción en la cola offchain. No se confunde con `sales.attempt`,
  /// que sigue siendo el intento de cobro original (intacto).
  static const String actionType = 'sales.declaration';

  static const String _localPrefix = 'sales.declaration:';

  final String clientRequestId;
  final double totalDeclared;
  final DateTime declaredAtUtc;
  final String? paymentMethod;
  final String? declaredByUserId;
  final String? declaredByRole;
  final String? note;
  final String? operationFingerprint;
  final Map<String, dynamic>? attemptPayload;

  /// Importe normalizado a 2 decimales, tal como lo guarda la base de datos.
  String get normalizedTotal => totalDeclared.toStringAsFixed(2);

  String get declaredAtIso =>
      declaredAtUtc.toUtc().toIso8601String();

  /// Huella del contenido declarado. Misma declaración → misma huella.
  String get contentHash {
    final payload = [
      clientRequestId.trim(),
      normalizedTotal,
      declaredAtIso,
      (paymentMethod ?? '').trim().toLowerCase(),
      (declaredByUserId ?? '').trim().toLowerCase(),
      (declaredByRole ?? '').trim().toLowerCase(),
      (note ?? '').trim().toLowerCase(),
    ].join('|');
    return sha256.convert(utf8.encode(payload)).toString();
  }

  /// Identidad local de la declaración. Incluye la huella para que una
  /// corrección no se confunda con la declaración anterior.
  String get localId => '$_localPrefix$clientRequestId:${contentHash.substring(0, 12)}';

  /// `válida` exige identidad, importe positivo y hora.
  bool get isValid =>
      clientRequestId.trim().isNotEmpty &&
      totalDeclared.isFinite &&
      totalDeclared >= 0.01;

  /// Cuerpo exacto del endpoint `POST /sales/attempts/:id/declaration`.
  Map<String, dynamic> toRequestBody() {
    final body = <String, dynamic>{
      'totalDeclared': double.parse(normalizedTotal),
      'declaredAtUtc': declaredAtIso,
      'paymentMethod': paymentMethod ?? 'cash',
    };
    if ((declaredByUserId ?? '').trim().isNotEmpty) {
      body['declaredByUserId'] = declaredByUserId!.trim();
    }
    if ((declaredByRole ?? '').trim().isNotEmpty) {
      body['declaredByRole'] = declaredByRole!.trim();
    }
    if ((note ?? '').trim().isNotEmpty) body['note'] = note!.trim();
    if ((operationFingerprint ?? '').trim().isNotEmpty) {
      body['operationFingerprint'] = operationFingerprint!.trim();
    }
    final attempt = attemptPayload;
    if (attempt != null && attempt.isNotEmpty) {
      body['attemptPayload'] = attempt;
    }
    return body;
  }

  /// Cuerpo persistido en la cola local. Lleva la identidad aparte para poder
  /// reconstruir la declaración sin adivinar nada.
  Map<String, dynamic> toQueuePayload({String? companyId, String? userId}) {
    return <String, dynamic>{
      ...toRequestBody(),
      'clientRequestId': clientRequestId.trim(),
      'declarationId': localId,
      'contentHash': contentHash,
      if ((companyId ?? '').trim().isNotEmpty) 'companyId': companyId!.trim(),
      if ((userId ?? '').trim().isNotEmpty) 'userId': userId!.trim(),
    };
  }

  static SaleAttemptDeclaration? fromQueuePayload(Map<String, dynamic> payload) {
    final requestId =
        (payload['clientRequestId'] ?? '').toString().trim();
    if (requestId.isEmpty) return null;
    final total = _toDouble(payload['totalDeclared']);
    final declaredAt = DateTime.tryParse(
      (payload['declaredAtUtc'] ?? '').toString(),
    );
    if (total == null || declaredAt == null) return null;
    final attempt = payload['attemptPayload'];
    return SaleAttemptDeclaration(
      clientRequestId: requestId,
      totalDeclared: total,
      declaredAtUtc: declaredAt.toUtc(),
      paymentMethod: payload['paymentMethod']?.toString(),
      declaredByUserId: payload['declaredByUserId']?.toString(),
      declaredByRole: payload['declaredByRole']?.toString(),
      note: payload['note']?.toString(),
      operationFingerprint: payload['operationFingerprint']?.toString(),
      attemptPayload: attempt is Map
          ? attempt.cast<String, dynamic>()
          : null,
    );
  }

  /// Convierte la declaración en la acción que se apila en `pending_actions`.
  PendingSyncAction toPendingAction({
    required String? companyId,
    required String? userId,
    DateTime? now,
  }) {
    final stamp = (now ?? DateTime.now()).toUtc();
    return PendingSyncAction(
      id: localId,
      type: actionType,
      scope: 'sales',
      companyId: companyId,
      userId: userId,
      entityType: 'sale_attempt',
      entityId: clientRequestId.trim(),
      idempotencyKey: localId,
      operationFingerprint: operationFingerprint,
      payload: toQueuePayload(companyId: companyId, userId: userId),
      status: 'pending',
      attempts: 0,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// Registra declaraciones en la cola local.
///
/// Se inyecta la función de encolado para poder probar el comportamiento sin
/// base de datos ni red.
class SaleAttemptDeclarationOutbox {
  SaleAttemptDeclarationOutbox({
    required this.enqueueAction,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<void> Function(PendingSyncAction action) enqueueAction;
  final DateTime Function() _clock;

  /// Encola la declaración. Devuelve `null` si la declaración no es válida.
  ///
  /// La cola es la fuente de verdad local: si esto lanza, la incidencia NO debe
  /// cerrarse (el llamador recibe el error y el intento sigue intacto).
  Future<SaleAttemptDeclaration?> declare({
    required PendingSyncAction action,
    required double totalDeclared,
    String? actorUserId,
    String? actorRole,
    String? note,
    DateTime? declaredAt,
  }) async {
    final declaration = SaleAttemptDeclaration(
      clientRequestId:
          (action.idempotencyKey ?? '').startsWith('sales.attempt:')
          ? action.idempotencyKey!.substring('sales.attempt:'.length).trim()
          : (action.idempotencyKey ?? action.entityId ?? '').trim(),
      totalDeclared: totalDeclared,
      declaredAtUtc: (declaredAt ?? _clock()).toUtc(),
      paymentMethod:
          (action.payload['paymentMethod'] ?? '').toString().trim().isEmpty
          ? 'cash'
          : action.payload['paymentMethod'].toString().trim(),
      declaredByUserId: actorUserId ?? action.userId,
      declaredByRole: actorRole,
      note: note,
      operationFingerprint: action.operationFingerprint,
      attemptPayload: action.payload,
    );
    if (!declaration.isValid) return null;
    await enqueueAction(
      declaration.toPendingAction(
        companyId: action.companyId,
        userId: action.userId,
        now: _clock(),
      ),
    );
    return declaration;
  }
}

/// Envía las declaraciones encoladas al servidor.
///
/// El endpoint es idempotente por huella: reintentar el mismo cuerpo devuelve la
/// obligación existente en lugar de duplicarla.
class SaleAttemptDeclarationSyncHandlers {
  SaleAttemptDeclarationSyncHandlers(this._queue, this._dio);

  final SyncQueueService _queue;
  final Dio _dio;

  void register() {
    _queue.registerHandler(SaleAttemptDeclaration.actionType, (payload) async {
      final declaration = SaleAttemptDeclaration.fromQueuePayload(payload);
      if (declaration == null) {
        // No es reintentable: el cuerpo guardado no permite reconstruir nada.
        throw const ObsoleteSyncOperationException(
          'declaración de conciliación incompleta en la cola local',
        );
      }
      await _dio.post(
        '${ApiRoutes.sales}/attempts/${declaration.clientRequestId}/declaration',
        data: declaration.toRequestBody(),
        options: Options(extra: const {'skipLoader': true}),
      );
    });
  }
}
