import 'dart:convert';

import 'package:daleventa_pos/core/offline/sale_attempt_audit.dart';
import 'package:daleventa_pos/core/offline/sale_attempt_reconciliation.dart';
import 'package:daleventa_pos/features/offline/declaration_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// La exportación histórica nunca puede inventar un importe ni mezclar
/// decisiones que no son «dinero recibido».
void main() {
  SaleAttemptAuditEntry entry({
    required String requestId,
    required SaleAttemptDecision decision,
    String? note,
    String? actorRole = 'OWNER',
    String? fingerprint = 'fp-1',
    DateTime? checkedAt,
  }) {
    return SaleAttemptAuditEntry(
      id: '$requestId#1',
      pendingActionId: 'sales.attempt:$requestId',
      clientRequestId: requestId,
      decision: decision,
      checkedAt: checkedAt ?? DateTime.utc(2026, 10, 27, 20, 39),
      companyId: 'company-a',
      userId: 'user-1',
      actorUserId: 'user-1',
      actorRole: actorRole,
      note: note,
      operationFingerprint: fingerprint,
      mechanism: SaleAttemptReconciler.mechanism,
    );
  }

  test('solo exporta «dinero recibido» y deja el importe sin inventar', () {
    final json = buildDeclarationImportTemplate(
      companyId: 'company-a',
      audit: [
        entry(requestId: 'req-1', decision: SaleAttemptDecision.manualMoneyReceived),
        entry(requestId: 'req-2', decision: SaleAttemptDecision.manualNotPerformed),
        entry(requestId: 'req-3', decision: SaleAttemptDecision.autoConfirmed),
        entry(requestId: 'req-4', decision: SaleAttemptDecision.keptInconclusive),
      ],
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final declarations = (decoded['declarations'] as List).cast<Map<String, dynamic>>();

    expect(declarations, hasLength(1));
    expect(declarations.single['clientRequestId'], 'req-1');
    expect(declarations.single['totalDeclared'], isNull);
    expect(declarations.single['declaredAtUtc'], '2026-10-27T20:39:00.000Z');
    expect(declarations.single['declaredByRole'], 'OWNER');
    expect(declarations.single['evidence'], contains('auditoría local'));
    expect(decoded['companyId'], 'company-a');
  });

  test('no repite la misma operación dos veces', () {
    final json = buildDeclarationImportTemplate(
      companyId: 'company-a',
      audit: [
        entry(requestId: 'req-1', decision: SaleAttemptDecision.manualMoneyReceived),
        entry(requestId: 'req-1', decision: SaleAttemptDecision.manualMoneyReceived),
      ],
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect((decoded['declarations'] as List), hasLength(1));
  });

  test('sin declaraciones produce una plantilla válida y vacía', () {
    final json = buildDeclarationImportTemplate(
      companyId: 'company-a',
      audit: const [],
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['declarations'], isEmpty);
    expect(decoded['note'], contains('totalDeclared'));
  });
}
