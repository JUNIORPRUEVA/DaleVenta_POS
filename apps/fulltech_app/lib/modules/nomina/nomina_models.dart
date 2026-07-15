enum PayrollPeriodStatus { open, closed }

enum PayrollEntryType {
  ausencia,
  tarde,
  feriadoTrabajado,
  comisionServicio,
  comisionVentas,
  bonificacion,
  pagoCombustible,
  adelanto,
  descuento,
  otro,
}

extension PayrollPeriodStatusX on PayrollPeriodStatus {
  String get dbValue => this == PayrollPeriodStatus.open ? 'OPEN' : 'CLOSED';

  String get label => this == PayrollPeriodStatus.open ? 'Abierta' : 'Cerrada';

  static PayrollPeriodStatus fromDb(String value) {
    return value.toUpperCase() == 'CLOSED'
        ? PayrollPeriodStatus.closed
        : PayrollPeriodStatus.open;
  }
}

extension PayrollEntryTypeX on PayrollEntryType {
  String get dbValue {
    switch (this) {
      case PayrollEntryType.ausencia:
        return 'AUSENCIA';
      case PayrollEntryType.tarde:
        return 'TARDE';
      case PayrollEntryType.feriadoTrabajado:
        return 'FERIADO_TRABAJADO';
      case PayrollEntryType.comisionServicio:
        return 'COMISION_SERVICIO';
      case PayrollEntryType.comisionVentas:
        return 'COMISION_VENTAS';
      case PayrollEntryType.bonificacion:
        return 'BONIFICACION';
      case PayrollEntryType.pagoCombustible:
        return 'PAGO_COMBUSTIBLE';
      case PayrollEntryType.adelanto:
        return 'ADELANTO';
      case PayrollEntryType.descuento:
        return 'DESCUENTO';
      case PayrollEntryType.otro:
        return 'OTRO';
    }
  }

  String get label {
    switch (this) {
      case PayrollEntryType.ausencia:
        return 'Ausencia';
      case PayrollEntryType.tarde:
        return 'Llegada tarde';
      case PayrollEntryType.feriadoTrabajado:
        return 'Feriado trabajado';
      case PayrollEntryType.comisionServicio:
        return 'Comisión por servicio';
      case PayrollEntryType.comisionVentas:
        return 'Comisión por ventas';
      case PayrollEntryType.bonificacion:
        return 'Bonificación';
      case PayrollEntryType.pagoCombustible:
        return 'Pago de combustible';
      case PayrollEntryType.adelanto:
        return 'Adelanto';
      case PayrollEntryType.descuento:
        return 'Descuento';
      case PayrollEntryType.otro:
        return 'Otro';
    }
  }

  bool get isDeduction {
    return this == PayrollEntryType.ausencia ||
        this == PayrollEntryType.tarde ||
        this == PayrollEntryType.adelanto ||
        this == PayrollEntryType.descuento;
  }

  static PayrollEntryType fromDb(String value) {
    switch (value.toUpperCase()) {
      case 'AUSENCIA':
      case 'FALTA_DIA':
        return PayrollEntryType.ausencia;
      case 'TARDE':
        return PayrollEntryType.tarde;
      case 'FERIADO_TRABAJADO':
        return PayrollEntryType.feriadoTrabajado;
      case 'COMISION_SERVICIO':
        return PayrollEntryType.comisionServicio;
      case 'COMISION_VENTAS':
      case 'COMISION':
        return PayrollEntryType.comisionVentas;
      case 'BONIFICACION':
      case 'BONO':
        return PayrollEntryType.bonificacion;
      case 'PAGO_COMBUSTIBLE':
        return PayrollEntryType.pagoCombustible;
      case 'ADELANTO':
        return PayrollEntryType.adelanto;
      case 'DESCUENTO':
        return PayrollEntryType.descuento;
      case 'OTRO':
      default:
        return PayrollEntryType.otro;
    }
  }
}

class PayrollEmployee {
  final String id;
  final String ownerId;
  final String? userId;
  final String nombre;
  final String? telefono;
  final String? puesto;
  final double salarioBaseQuincenal;
  final double cuotaMinima;
  final double seguroLeyMonto;
  final bool seguroLeyMontoLocked;
  final bool activo;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayrollEmployee({
    required this.id,
    required this.ownerId,
    this.userId,
    required this.nombre,
    this.telefono,
    this.puesto,
    this.salarioBaseQuincenal = 0,
    this.cuotaMinima = 0,
    this.seguroLeyMonto = 0,
    this.seguroLeyMontoLocked = false,
    this.activo = true,
    this.createdAt,
    this.updatedAt,
  });

  PayrollEmployee copyWith({
    String? id,
    String? ownerId,
    String? userId,
    String? nombre,
    String? telefono,
    String? puesto,
    double? salarioBaseQuincenal,
    double? cuotaMinima,
    double? seguroLeyMonto,
    bool? seguroLeyMontoLocked,
    bool? activo,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearTelefono = false,
    bool clearPuesto = false,
  }) {
    return PayrollEmployee(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      userId: userId ?? this.userId,
      nombre: nombre ?? this.nombre,
      telefono: clearTelefono ? null : (telefono ?? this.telefono),
      puesto: clearPuesto ? null : (puesto ?? this.puesto),
      salarioBaseQuincenal: salarioBaseQuincenal ?? this.salarioBaseQuincenal,
      cuotaMinima: cuotaMinima ?? this.cuotaMinima,
      seguroLeyMonto: seguroLeyMonto ?? this.seguroLeyMonto,
      seguroLeyMontoLocked: seguroLeyMontoLocked ?? this.seguroLeyMontoLocked,
      activo: activo ?? this.activo,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory PayrollEmployee.fromMap(Map<String, dynamic> map) {
    return PayrollEmployee(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      userId: map['user_id']?.toString(),
      nombre: (map['nombre'] ?? '').toString(),
      telefono: map['telefono'] as String?,
      puesto: map['puesto'] as String?,
      salarioBaseQuincenal:
          (map['salario_base_quincenal'] as num?)?.toDouble() ?? 0,
      cuotaMinima: (map['cuota_minima'] as num?)?.toDouble() ?? 0,
      seguroLeyMonto:
          (map['seguro_ley_monto'] as num?)?.toDouble() ??
          (map['seguro_ley_pct'] as num?)?.toDouble() ??
          0,
      seguroLeyMontoLocked:
          (map['seguro_ley_monto_locked'] ?? 0) == 1 ||
          map['seguro_ley_monto_locked'] == true,
      activo: (map['activo'] ?? 1) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'user_id': userId,
      'nombre': nombre,
      'telefono': telefono,
      'puesto': puesto,
      'salario_base_quincenal': salarioBaseQuincenal,
      'cuota_minima': cuotaMinima,
      'seguro_ley_monto': seguroLeyMonto,
      'seguro_ley_monto_locked': seguroLeyMontoLocked ? 1 : 0,
      'seguro_ley_pct': seguroLeyMonto,
      'activo': activo ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class PayrollPeriod {
  final String id;
  final String ownerId;
  final String title;
  final DateTime startDate;
  final DateTime endDate;
  final PayrollPeriodStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayrollPeriod({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  bool get isOpen => status == PayrollPeriodStatus.open;

  factory PayrollPeriod.fromMap(Map<String, dynamic> map) {
    return PayrollPeriod(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      startDate: DateTime.parse((map['start_date']).toString()),
      endDate: DateTime.parse((map['end_date']).toString()),
      status: PayrollPeriodStatusX.fromDb((map['status'] ?? 'OPEN').toString()),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'title': title,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'status': status.dbValue,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class PayrollEmployeeConfig {
  final String id;
  final String ownerId;
  final String periodId;
  final String employeeId;
  final double baseSalary;
  final bool includeCommissions;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayrollEmployeeConfig({
    required this.id,
    required this.ownerId,
    required this.periodId,
    required this.employeeId,
    required this.baseSalary,
    required this.includeCommissions,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory PayrollEmployeeConfig.fromMap(Map<String, dynamic> map) {
    return PayrollEmployeeConfig(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      periodId: (map['period_id'] ?? '').toString(),
      employeeId: (map['employee_id'] ?? '').toString(),
      baseSalary: (map['base_salary'] as num?)?.toDouble() ?? 0,
      includeCommissions: (map['include_commissions'] ?? 0) == 1,
      notes: map['notes'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'period_id': periodId,
      'employee_id': employeeId,
      'base_salary': baseSalary,
      'include_commissions': includeCommissions ? 1 : 0,
      'notes': notes,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}

class PayrollEntry {
  final String id;
  final String ownerId;
  final String periodId;
  final String employeeId;
  final String? pagoCombustibleTecnicoId;
  final DateTime date;
  final PayrollEntryType type;
  final String concept;
  final double amount;
  final double? cantidad;
  final bool notifyUser;
  final DateTime? createdAt;

  const PayrollEntry({
    required this.id,
    required this.ownerId,
    required this.periodId,
    required this.employeeId,
    this.pagoCombustibleTecnicoId,
    required this.date,
    required this.type,
    required this.concept,
    required this.amount,
    this.cantidad,
    this.notifyUser = false,
    this.createdAt,
  });

  factory PayrollEntry.fromMap(Map<String, dynamic> map) {
    return PayrollEntry(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['owner_id'] ?? '').toString(),
      periodId: (map['period_id'] ?? '').toString(),
      employeeId: (map['employee_id'] ?? '').toString(),
      pagoCombustibleTecnicoId: map['pago_combustible_tecnico_id']?.toString(),
      date: DateTime.parse((map['date']).toString()),
      type: PayrollEntryTypeX.fromDb((map['type'] ?? 'OTRO').toString()),
      concept: (map['concept'] ?? '').toString(),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      cantidad: (map['cantidad'] as num?)?.toDouble(),
      notifyUser: (map['notify_user'] ?? 0) == 1 || map['notify_user'] == true,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'owner_id': ownerId,
      'period_id': periodId,
      'employee_id': employeeId,
      'pago_combustible_tecnico_id': pagoCombustibleTecnicoId,
      'date': date.toIso8601String(),
      'type': type.dbValue,
      'concept': concept,
      'amount': amount,
      'cantidad': cantidad,
      'notify_user': notifyUser ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}

class PayrollTotals {
  final double baseSalary;
  final double commissions;
  final double serviceCommissions;
  final double salesCommissionAuto;
  final double salesAmountThisPeriod;
  final double salesGoal;
  final bool salesGoalReached;
  final String salesCommissionSource;
  final double bonuses;
  final double holidayWorked;
  final double otherAdditions;
  final double absences;
  final double late;
  final double advances;
  final double otherDeductions;
  final double seguroLey;
  final double additions;
  final double deductions;
  final double total;

  const PayrollTotals({
    required this.baseSalary,
    this.commissions = 0,
    this.serviceCommissions = 0,
    this.salesCommissionAuto = 0,
    this.salesAmountThisPeriod = 0,
    this.salesGoal = 0,
    this.salesGoalReached = false,
    this.salesCommissionSource = 'manual',
    this.bonuses = 0,
    this.holidayWorked = 0,
    this.otherAdditions = 0,
    this.absences = 0,
    this.late = 0,
    this.advances = 0,
    this.otherDeductions = 0,
    this.seguroLey = 0,
    required this.additions,
    required this.deductions,
    required this.total,
  });
}

class PayrollPaymentRecord {
  final String id;
  final String periodId;
  final String employeeId;
  final String status;
  final DateTime? paidAt;
  final String? paidById;

  const PayrollPaymentRecord({
    required this.id,
    required this.periodId,
    required this.employeeId,
    this.status = 'DRAFT',
    this.paidAt,
    this.paidById,
  });

  bool get isPaid => status.toUpperCase() == 'PAID';

  factory PayrollPaymentRecord.draft({
    required String periodId,
    required String employeeId,
  }) {
    return PayrollPaymentRecord(
      id: '',
      periodId: periodId,
      employeeId: employeeId,
    );
  }

  factory PayrollPaymentRecord.fromMap(Map<String, dynamic> map) {
    return PayrollPaymentRecord(
      id: (map['id'] ?? '').toString(),
      periodId: (map['period_id'] ?? '').toString(),
      employeeId: (map['employee_id'] ?? '').toString(),
      status: (map['status'] ?? 'DRAFT').toString(),
      paidAt: map['paid_at'] != null
          ? DateTime.tryParse(map['paid_at'].toString())
          : null,
      paidById: map['paid_by_id']?.toString(),
    );
  }
}

class PayrollServiceCommissionRequest {
  final String id;
  final String serviceOrderId;
  final String? quotationId;
  final String employeeId;
  final String employeeName;
  final String? employeeUserId;
  final String technicianUserId;
  final String technicianName;
  final String? customerId;
  final String? customerName;
  final String serviceType;
  final DateTime finalizedAt;
  final double profitAfterExpense;
  final double commissionRate;
  final double commissionAmount;
  final String concept;
  final String status;
  final String? reviewNote;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final String? periodId;
  final String? payrollEntryId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PayrollServiceCommissionRequest({
    required this.id,
    required this.serviceOrderId,
    this.quotationId,
    required this.employeeId,
    required this.employeeName,
    this.employeeUserId,
    required this.technicianUserId,
    required this.technicianName,
    this.customerId,
    this.customerName,
    required this.serviceType,
    required this.finalizedAt,
    required this.profitAfterExpense,
    required this.commissionRate,
    required this.commissionAmount,
    required this.concept,
    required this.status,
    this.reviewNote,
    this.approvedAt,
    this.rejectedAt,
    this.periodId,
    this.payrollEntryId,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPending => status.toUpperCase() == 'PENDING';

  factory PayrollServiceCommissionRequest.fromMap(Map<String, dynamic> map) {
    return PayrollServiceCommissionRequest(
      id: (map['id'] ?? '').toString(),
      serviceOrderId: (map['service_order_id'] ?? '').toString(),
      quotationId: map['quotation_id']?.toString(),
      employeeId: (map['employee_id'] ?? '').toString(),
      employeeName: (map['employee_name'] ?? '').toString(),
      employeeUserId: map['employee_user_id']?.toString(),
      technicianUserId: (map['technician_user_id'] ?? '').toString(),
      technicianName: (map['technician_name'] ?? '').toString(),
      customerId: map['customer_id']?.toString(),
      customerName: map['customer_name']?.toString(),
      serviceType: (map['service_type'] ?? '').toString(),
      finalizedAt: DateTime.parse((map['finalized_at']).toString()),
      profitAfterExpense:
          (map['profit_after_expense'] as num?)?.toDouble() ?? 0,
      commissionRate: (map['commission_rate'] as num?)?.toDouble() ?? 0,
      commissionAmount: (map['commission_amount'] as num?)?.toDouble() ?? 0,
      concept: (map['concept'] ?? '').toString(),
      status: (map['status'] ?? '').toString(),
      reviewNote: map['review_note']?.toString(),
      approvedAt: map['approved_at'] != null
          ? DateTime.tryParse(map['approved_at'].toString())
          : null,
      rejectedAt: map['rejected_at'] != null
          ? DateTime.tryParse(map['rejected_at'].toString())
          : null,
      periodId: map['period_id']?.toString(),
      payrollEntryId: map['payroll_entry_id']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
    );
  }
}

class PayrollHistoryItem {
  final String entryId;
  final String paymentId;
  final String employeeName;
  final String periodId;
  final String periodTitle;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String periodStatus;
  final String paymentStatus;
  final DateTime? paymentDate;
  final String? paymentMethod;
  final String? paymentReference;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final double baseSalary;
  final double commissions;
  final double bonuses;
  final double discounts;
  final double overtime;
  final double totalGross;
  final double totalDiscounted;
  final double totalNetPaid;
  final double commissionFromSales;
  final double overtimeAmount;
  final double bonusesAmount;
  final double deductionsAmount;
  final double benefitsAmount;
  final double grossTotal;
  final double netTotal;

  const PayrollHistoryItem({
    required this.entryId,
    this.paymentId = '',
    this.employeeName = '',
    required this.periodId,
    required this.periodTitle,
    required this.periodStart,
    required this.periodEnd,
    required this.periodStatus,
    this.paymentStatus = 'DRAFT',
    this.paymentDate,
    this.paymentMethod,
    this.paymentReference,
    this.notes,
    this.createdAt,
    this.updatedAt,
    required this.baseSalary,
    this.commissions = 0,
    this.bonuses = 0,
    this.discounts = 0,
    this.overtime = 0,
    this.totalGross = 0,
    this.totalDiscounted = 0,
    this.totalNetPaid = 0,
    required this.commissionFromSales,
    required this.overtimeAmount,
    required this.bonusesAmount,
    required this.deductionsAmount,
    required this.benefitsAmount,
    required this.grossTotal,
    required this.netTotal,
  });

  bool get isPaid {
    final status = paymentStatus.trim().toUpperCase();
    if (status == 'PAID') return true;
    return periodStatus.trim().toUpperCase() == 'PAID';
  }

  String get statusLabel {
    final status = paymentStatus.trim().toUpperCase();
    if (status == 'PAID') return 'Pagado';
    if (status == 'DRAFT') return 'Pendiente';
    return status.isEmpty ? 'Pendiente' : status;
  }

  factory PayrollHistoryItem.fromMap(Map<String, dynamic> map) {
    final baseSalary =
        (map['base_salary'] as num?)?.toDouble() ??
        (map['salary_base'] as num?)?.toDouble() ??
        0;
    final gross =
        (map['gross_total'] as num?)?.toDouble() ??
        (map['total_gross'] as num?)?.toDouble() ??
        0;
    final deducted =
        (map['deductions_amount'] as num?)?.toDouble() ??
        (map['total_discounted'] as num?)?.toDouble() ??
        (map['discounts'] as num?)?.toDouble() ??
        0;
    final net =
        (map['net_total'] as num?)?.toDouble() ??
        (map['total_net_paid'] as num?)?.toDouble() ??
        0;

    return PayrollHistoryItem(
      entryId: (map['entry_id'] ?? '').toString(),
      paymentId: (map['payment_id'] ?? '').toString(),
      employeeName: (map['employee_name'] ?? '').toString(),
      periodId: (map['period_id'] ?? '').toString(),
      periodTitle: (map['period_title'] ?? '').toString(),
      periodStart: DateTime.parse((map['period_start']).toString()),
      periodEnd: DateTime.parse((map['period_end']).toString()),
      periodStatus: (map['period_status'] ?? 'DRAFT').toString(),
      paymentStatus: (map['payment_status'] ?? map['period_status'] ?? 'DRAFT')
          .toString(),
      paymentDate: map['payment_date'] != null
          ? DateTime.tryParse(map['payment_date'].toString())
          : null,
      paymentMethod: map['payment_method']?.toString(),
      paymentReference: map['reference']?.toString(),
      notes: map['notes']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString())
          : null,
      baseSalary: baseSalary,
      commissions:
          (map['commissions'] as num?)?.toDouble() ??
          (map['commission_from_sales'] as num?)?.toDouble() ??
          0,
      bonuses:
          (map['bonuses'] as num?)?.toDouble() ??
          (map['bonuses_amount'] as num?)?.toDouble() ??
          0,
      discounts: (map['discounts'] as num?)?.toDouble() ?? deducted,
      overtime:
          (map['overtime'] as num?)?.toDouble() ??
          (map['overtime_amount'] as num?)?.toDouble() ??
          0,
      totalGross: (map['total_gross'] as num?)?.toDouble() ?? gross,
      totalDiscounted:
          (map['total_discounted'] as num?)?.toDouble() ?? deducted,
      totalNetPaid: (map['total_net_paid'] as num?)?.toDouble() ?? net,
      commissionFromSales:
          (map['commission_from_sales'] as num?)?.toDouble() ?? 0,
      overtimeAmount: (map['overtime_amount'] as num?)?.toDouble() ?? 0,
      bonusesAmount: (map['bonuses_amount'] as num?)?.toDouble() ?? 0,
      deductionsAmount: deducted,
      benefitsAmount: (map['benefits_amount'] as num?)?.toDouble() ?? 0,
      grossTotal: gross,
      netTotal: net,
    );
  }

  Map<String, dynamic> toMap({String? cacheUserId}) {
    return {
      'entry_id': entryId,
      'cache_user_id': cacheUserId,
      'employee_name': employeeName,
      'period_id': periodId,
      'period_title': periodTitle,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'period_status': periodStatus,
      'base_salary': baseSalary,
      'commission_from_sales': commissionFromSales,
      'overtime_amount': overtimeAmount,
      'bonuses_amount': bonusesAmount,
      'deductions_amount': deductionsAmount,
      'benefits_amount': benefitsAmount,
      'gross_total': grossTotal,
      'net_total': netTotal,
    };
  }
}
