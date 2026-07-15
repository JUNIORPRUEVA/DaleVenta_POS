enum DepositOrderStatus { pending, executed, cancelled }

extension DepositOrderStatusX on DepositOrderStatus {
  String get apiValue {
    switch (this) {
      case DepositOrderStatus.pending:
        return 'PENDING';
      case DepositOrderStatus.executed:
        return 'EXECUTED';
      case DepositOrderStatus.cancelled:
        return 'CANCELLED';
    }
  }

  String get label {
    switch (this) {
      case DepositOrderStatus.pending:
        return 'Pendiente';
      case DepositOrderStatus.executed:
        return 'Ejecutado';
      case DepositOrderStatus.cancelled:
        return 'Anulado';
    }
  }

  static DepositOrderStatus fromApi(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'EXECUTED':
        return DepositOrderStatus.executed;
      case 'CANCELLED':
        return DepositOrderStatus.cancelled;
      case 'PENDING':
      default:
        return DepositOrderStatus.pending;
    }
  }
}

class DepositOrderModel {
  const DepositOrderModel({
    required this.id,
    required this.windowFrom,
    required this.windowTo,
    required this.bankName,
    this.bankAccount,
    this.collaboratorName,
    this.note,
    required this.reserveAmount,
    required this.totalAvailableCash,
    required this.depositTotal,
    required this.closesCountByType,
    required this.depositByType,
    required this.accountByType,
    required this.status,
    this.voucherUrl,
    this.voucherFileName,
    this.voucherMimeType,
    this.createdById,
    this.createdByName,
    this.executedById,
    this.executedByName,
    this.executedAt,
    required this.createdAt,
    required this.updatedAt,
    this.correctionOfDepositOrderId,
    this.correctionReason,
    this.deletedAt,
    this.deletedById,
    this.deletedByName,
    this.deletedReason,
  });

  final String id;
  final DateTime windowFrom;
  final DateTime windowTo;
  final String bankName;
  final String? bankAccount;
  final String? collaboratorName;
  final String? note;
  final double reserveAmount;
  final double totalAvailableCash;
  final double depositTotal;
  final Map<String, int> closesCountByType;
  final Map<String, double> depositByType;
  final Map<String, String> accountByType;
  final DepositOrderStatus status;
  final String? voucherUrl;
  final String? voucherFileName;
  final String? voucherMimeType;
  final String? createdById;
  final String? createdByName;
  final String? executedById;
  final String? executedByName;
  final DateTime? executedAt;
  final String? correctionOfDepositOrderId;
  final String? correctionReason;
  final DateTime? deletedAt;
  final String? deletedById;
  final String? deletedByName;
  final String? deletedReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasVoucher => (voucherUrl ?? '').trim().isNotEmpty;
  bool get isPending => status == DepositOrderStatus.pending;
  bool get isExecuted => status == DepositOrderStatus.executed;
  bool get isCancelled => status == DepositOrderStatus.cancelled;
  bool get isCorrection => (correctionOfDepositOrderId ?? '').trim().isNotEmpty;

  factory DepositOrderModel.fromJson(Map<String, dynamic> json) {
    return DepositOrderModel(
      id: (json['id'] ?? '').toString(),
      windowFrom: DateTime.parse(json['windowFrom'].toString()),
      windowTo: DateTime.parse(json['windowTo'].toString()),
      bankName: (json['bankName'] ?? '').toString(),
      bankAccount: _nullableString(json['bankAccount']),
      collaboratorName: _nullableString(json['collaboratorName']),
      note: _nullableString(json['note']),
      reserveAmount: _toDouble(json['reserveAmount']),
      totalAvailableCash: _toDouble(json['totalAvailableCash']),
      depositTotal: _toDouble(json['depositTotal']),
      closesCountByType: _toIntMap(json['closesCountByType']),
      depositByType: _toDoubleMap(json['depositByType']),
      accountByType: _toStringMap(json['accountByType']),
      status: DepositOrderStatusX.fromApi((json['status'] ?? '').toString()),
      voucherUrl: _nullableString(json['voucherUrl']),
      voucherFileName: _nullableString(json['voucherFileName']),
      voucherMimeType: _nullableString(json['voucherMimeType']),
      createdById: _nullableString(json['createdById']),
      createdByName: _nullableString(json['createdByName']),
      executedById: _nullableString(json['executedById']),
      executedByName: _nullableString(json['executedByName']),
      executedAt: json['executedAt'] == null
          ? null
          : DateTime.parse(json['executedAt'].toString()),
      correctionOfDepositOrderId: _nullableString(
        json['correctionOfDepositOrderId'],
      ),
      correctionReason: _nullableString(json['correctionReason']),
      deletedAt: json['deletedAt'] == null
          ? null
          : DateTime.parse(json['deletedAt'].toString()),
      deletedById: _nullableString(json['deletedById']),
      deletedByName: _nullableString(json['deletedByName']),
      deletedReason: _nullableString(json['deletedReason']),
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
    );
  }

  static String? _nullableString(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '0').toString()) ?? 0;
  }

  static Map<String, int> _toIntMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, int>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      final raw = entry.value;
      if (raw is num) {
        result[key] = raw.toInt();
      } else {
        result[key] = int.tryParse(raw.toString()) ?? 0;
      }
    }
    return result;
  }

  static Map<String, double> _toDoubleMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, double>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      result[key] = _toDouble(entry.value);
    }
    return result;
  }

  static Map<String, String> _toStringMap(dynamic value) {
    if (value is! Map) return const {};
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      final item = entry.value.toString().trim();
      if (key.isEmpty || item.isEmpty) continue;
      result[key] = item;
    }
    return result;
  }
}
