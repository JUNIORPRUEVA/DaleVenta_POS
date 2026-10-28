/// Modelo de auditoría de los intentos de cobro (`sales.attempt`).
///
/// Un intento de cobro es un **hecho**, no un error temporal. Cuando el backend
/// no confirma el resultado, el intento se conserva y la decisión que se tome
/// después (automática o autorizada por el encargado) queda registrada aquí.
///
/// Reglas que este modelo ayuda a sostener:
///  - Se registra una fila por CADA comprobación; nunca se sobrescribe historia.
///  - Ninguna fila autoriza por sí sola a repetir el cobro.
///  - Una fila de venta registrada NO demuestra que el dinero entró.
library;

/// Qué se decidió sobre el intento.
enum SaleAttemptDecision {
  /// El backend confirmó que la operación está registrada.
  autoConfirmed,

  /// El backend confirmó el registro y después se anuló/devolvió.
  autoRegisteredThenVoided,

  /// No se pudo concluir: el intento se conserva intacto.
  keptInconclusive,

  /// El encargado declara que la venta NO se realizó. No borra hechos en el
  /// servidor; solo cierra la incidencia local con rastro.
  manualNotPerformed,

  /// El encargado declara que SÍ se recibió dinero. Abre conciliación; no
  /// crea una venta retroactiva por sí sola.
  manualMoneyReceived,

  /// Se solicitó revisión técnica/soporte.
  manualEscalated;

  static SaleAttemptDecision? parse(String? raw) {
    switch ((raw ?? '').trim().toUpperCase()) {
      case 'AUTO_CONFIRMED':
        return SaleAttemptDecision.autoConfirmed;
      case 'AUTO_REGISTERED_THEN_VOIDED':
        return SaleAttemptDecision.autoRegisteredThenVoided;
      case 'KEPT_INCONCLUSIVE':
        return SaleAttemptDecision.keptInconclusive;
      case 'MANUAL_NOT_PERFORMED':
        return SaleAttemptDecision.manualNotPerformed;
      case 'MANUAL_MONEY_RECEIVED':
        return SaleAttemptDecision.manualMoneyReceived;
      case 'MANUAL_ESCALATED':
        return SaleAttemptDecision.manualEscalated;
      default:
        return null;
    }
  }
}

extension SaleAttemptDecisionLabel on SaleAttemptDecision {
  String get code => switch (this) {
    SaleAttemptDecision.autoConfirmed => 'AUTO_CONFIRMED',
    SaleAttemptDecision.autoRegisteredThenVoided =>
      'AUTO_REGISTERED_THEN_VOIDED',
    SaleAttemptDecision.keptInconclusive => 'KEPT_INCONCLUSIVE',
    SaleAttemptDecision.manualNotPerformed => 'MANUAL_NOT_PERFORMED',
    SaleAttemptDecision.manualMoneyReceived => 'MANUAL_MONEY_RECEIVED',
    SaleAttemptDecision.manualEscalated => 'MANUAL_ESCALATED',
  };

  bool get isManual =>
      this == SaleAttemptDecision.manualNotPerformed ||
      this == SaleAttemptDecision.manualMoneyReceived ||
      this == SaleAttemptDecision.manualEscalated;

  /// Solo estas decisiones retiran el aviso del intento.
  bool get resolvesIncident =>
      this == SaleAttemptDecision.autoConfirmed ||
      this == SaleAttemptDecision.autoRegisteredThenVoided ||
      this == SaleAttemptDecision.manualNotPerformed ||
      this == SaleAttemptDecision.manualMoneyReceived;
}

/// Una fila de auditoría. Inmutable una vez escrita.
class SaleAttemptAuditEntry {
  const SaleAttemptAuditEntry({
    required this.id,
    required this.pendingActionId,
    required this.clientRequestId,
    required this.decision,
    required this.checkedAt,
    this.companyId,
    this.userId,
    this.serverStatus,
    this.guidance,
    this.voided = false,
    this.saleId,
    this.totalSold,
    this.paymentMethod,
    this.movementId,
    this.actorUserId,
    this.actorRole,
    this.note,
    this.operationFingerprint,
    this.mechanism = 'sale-attempt-reconciliation-v1',
  });

  final String id;
  final String pendingActionId;
  final String clientRequestId;
  final SaleAttemptDecision decision;
  final DateTime checkedAt;
  final String? companyId;
  final String? userId;

  /// Estado que devolvió el servidor (`CONFIRMED`, `NOT_FOUND`, `UNKNOWN`, ...).
  final String? serverStatus;
  final String? guidance;
  final bool voided;
  final String? saleId;
  final double? totalSold;
  final String? paymentMethod;
  final String? movementId;

  /// Quién tomó una decisión manual (null en las automáticas).
  final String? actorUserId;
  final String? actorRole;
  final String? note;

  final String? operationFingerprint;
  final String mechanism;

  Map<String, Object?> toRow() => {
    'id': id,
    'pending_action_id': pendingActionId,
    'client_request_id': clientRequestId,
    'company_id': companyId,
    'user_id': userId,
    'decision': decision.code,
    'server_status': serverStatus,
    'guidance': guidance,
    'voided': voided ? 1 : 0,
    'sale_id': saleId,
    'total_sold': totalSold,
    'payment_method': paymentMethod,
    'movement_id': movementId,
    'actor_user_id': actorUserId,
    'actor_role': actorRole,
    'note': note,
    'operation_fingerprint': operationFingerprint,
    'mechanism': mechanism,
    'checked_at': checkedAt.toUtc().millisecondsSinceEpoch,
  };

  static SaleAttemptAuditEntry fromRow(Map<String, Object?> row) {
    final millis = (row['checked_at'] as num?)?.toInt() ?? 0;
    return SaleAttemptAuditEntry(
      id: (row['id'] ?? '').toString(),
      pendingActionId: (row['pending_action_id'] ?? '').toString(),
      clientRequestId: (row['client_request_id'] ?? '').toString(),
      decision:
          SaleAttemptDecision.parse(row['decision']?.toString()) ??
          SaleAttemptDecision.keptInconclusive,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(millis).toUtc(),
      companyId: row['company_id']?.toString(),
      userId: row['user_id']?.toString(),
      serverStatus: row['server_status']?.toString(),
      guidance: row['guidance']?.toString(),
      voided: (row['voided'] as num?)?.toInt() == 1,
      saleId: row['sale_id']?.toString(),
      totalSold: (row['total_sold'] as num?)?.toDouble(),
      paymentMethod: row['payment_method']?.toString(),
      movementId: row['movement_id']?.toString(),
      actorUserId: row['actor_user_id']?.toString(),
      actorRole: row['actor_role']?.toString(),
      note: row['note']?.toString(),
      operationFingerprint: row['operation_fingerprint']?.toString(),
      mechanism: (row['mechanism'] ?? '').toString(),
    );
  }
}

/// Huella del *contenido* de una operación de cobro.
///
/// Sirve para distinguir «el cajero volvió a intentar el mismo carrito» de «es
/// otra venta». No identifica a la persona ni el momento: dos carritos iguales
/// producen la misma huella, y por eso solo se usa como bloqueo mientras exista
/// un intento SIN resolver de esa misma huella.
class SaleOperationFingerprint {
  SaleOperationFingerprint._();

  /// Digest determinista de 64 bits en hexadecimal. NO es criptográfico: solo
  /// detecta igualdad de texto, es estable entre plataformas y no añade
  /// dependencias.
  static String compute({
    required String companyId,
    required String originCashSessionId,
    required String paymentMethod,
    String? customerId,
    String? priceListId,
    required String total,
    required List<({String productId, double qty, double price})> items,
  }) {
    final sorted = [...items]
      ..sort((a, b) {
        final byProduct = a.productId.compareTo(b.productId);
        if (byProduct != 0) return byProduct;
        final byPrice = a.price.compareTo(b.price);
        if (byPrice != 0) return byPrice;
        return a.qty.compareTo(b.qty);
      });

    final buffer = StringBuffer()
      ..write(companyId.trim().toLowerCase())
      ..write('|')
      ..write(originCashSessionId.trim())
      ..write('|')
      ..write(paymentMethod.trim().toLowerCase())
      ..write('|')
      ..write((customerId ?? '').trim())
      ..write('|')
      ..write((priceListId ?? '').trim())
      ..write('|')
      ..write(total)
      ..write('|');
    for (final item in sorted) {
      buffer
        ..write(item.productId.trim())
        ..write(':')
        ..write(item.qty.toStringAsFixed(4))
        ..write(':')
        ..write(item.price.toStringAsFixed(2))
        ..write(';');
    }
    return _digest64(buffer.toString());
  }

  /// Digest determinista sobre dos enteros de 32 bits: evita depender de la
  /// aritmética sin signo de 64 bits de la VM.
  static String _digest64(String input) {
    const offsetHigh = 0xcbf29ce4;
    const offsetLow = 0x84222325;
    const primeHigh = 0x00000100;
    const primeLow = 0x000001b3;

    var high = offsetHigh;
    var low = offsetLow;

    for (final unit in input.codeUnits) {
      low ^= unit & 0xff;
      high ^= (unit >> 8) & 0xff;

      final lowProduct = low * primeLow;
      final carry = lowProduct ~/ 0x100000000;
      low = lowProduct & 0xffffffff;
      high = (high * primeLow + low * primeHigh + carry) & 0xffffffff;
    }

    final highHex = high.toRadixString(16).padLeft(8, '0');
    final lowHex = low.toRadixString(16).padLeft(8, '0');
    return '$highHex$lowHex';
  }
}
