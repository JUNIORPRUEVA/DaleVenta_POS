import 'dart:convert';

import '../../core/offline/sale_attempt_audit.dart';

/// Plantilla de importación de declaraciones históricas.
///
/// Las versiones 145–148 cerraban la incidencia con una declaración
/// `MANUAL_MONEY_RECEIVED` guardada SOLO en el equipo. Este export convierte esa
/// auditoría en el archivo que consume
/// `scripts/import-sale-declarations.ts` del backend.
///
/// Regla de oro: **el importe nunca se inventa**. Si la auditoría no lo tiene, el
/// campo se deja en `null` y la fila queda marcada para que una persona lo
/// complete con evidencia (por ejemplo, el comprobante del cobro). El importador
/// rechaza cualquier fila sin importe, así que nada entra a ciegas.
String buildDeclarationImportTemplate({
  required String companyId,
  required List<SaleAttemptAuditEntry> audit,
  String? deviceLabel,
}) {
  final seen = <String>{};
  final declarations = <Map<String, dynamic>>[];
  for (final entry in audit) {
    if (entry.decision != SaleAttemptDecision.manualMoneyReceived) continue;
    final requestId = entry.clientRequestId.trim();
    if (requestId.isEmpty || !seen.add(requestId)) continue;
    declarations.add({
      'clientRequestId': requestId,
      // Pendiente de completar con evidencia. El importador lo exige.
      'totalDeclared': null,
      'declaredAtUtc': entry.checkedAt.toUtc().toIso8601String(),
      'paymentMethod': 'cash',
      if ((entry.actorUserId ?? '').trim().isNotEmpty)
        'declaredByUserId': entry.actorUserId!.trim(),
      if ((entry.actorRole ?? '').trim().isNotEmpty)
        'declaredByRole': entry.actorRole!.trim(),
      if ((entry.note ?? '').trim().isNotEmpty) 'note': entry.note!.trim(),
      if ((entry.operationFingerprint ?? '').trim().isNotEmpty)
        'operationFingerprint': entry.operationFingerprint!.trim(),
      'evidence':
          'auditoría local ${entry.mechanism} · acción ${entry.pendingActionId}',
    });
  }

  return const JsonEncoder.withIndent('  ').convert({
    'companyId': companyId,
    if ((deviceLabel ?? '').trim().isNotEmpty) 'device': deviceLabel!.trim(),
    'note':
        'Completa "totalDeclared" con el importe real de cada declaración antes '
        'de importar. Las filas sin importe son rechazadas por el importador.',
    'declarations': declarations,
  });
}
