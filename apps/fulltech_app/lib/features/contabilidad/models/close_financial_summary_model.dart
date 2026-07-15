import '../../../core/models/close_model.dart';

class CloseFinancialSummaryModel {
  final DateTime fromDate;
  final DateTime toDate;
  final CloseType? businessType;
  final String? companyId;
  final int count;
  final CloseFinancialTotals totals;
  final List<CloseTransferBankTotal> transfersByBank;
  final CloseAvailableForDeposit availableForDeposit;
  final CloseDepositStatus depositStatus;

  const CloseFinancialSummaryModel({
    required this.fromDate,
    required this.toDate,
    required this.businessType,
    required this.companyId,
    required this.count,
    required this.totals,
    required this.transfersByBank,
    required this.availableForDeposit,
    required this.depositStatus,
  });

  static double _asDouble(dynamic value, {double fallback = 0}) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  static DateTime _asDate(dynamic value, {DateTime? fallback}) {
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory CloseFinancialSummaryModel.fromJson(Map<String, dynamic> json) {
    final range = (json['range'] as Map? ?? const {}).cast<String, dynamic>();
    final totals = (json['totals'] as Map? ?? const {}).cast<String, dynamic>();
    final available = (json['availableForDeposit'] as Map? ?? const {})
        .cast<String, dynamic>();
    final depositStatus = (json['depositStatus'] as Map? ?? const {})
        .cast<String, dynamic>();

    return CloseFinancialSummaryModel(
      fromDate: _asDate(range['fromDate']),
      toDate: _asDate(range['toDate']),
      businessType: range['businessType'] == null
          ? null
          : CloseTypeX.fromKey(range['businessType'].toString()),
      companyId: (range['companyId'] as String?)?.trim().isEmpty == true
          ? null
          : range['companyId'] as String?,
      count: _asInt(json['count']),
      totals: CloseFinancialTotals(
        cashDeclared: _asDouble(totals['cashDeclared']),
        cashDelivered: _asDouble(totals['cashDelivered']),
        cashAvailable: _asDouble(totals['cashAvailable']),
        transfers: _asDouble(totals['transfers']),
        cardPayments: _asDouble(totals['cardPayments']),
        otherIncome: _asDouble(totals['otherIncome']),
        expenses: _asDouble(totals['expenses']),
        netTotal: _asDouble(totals['netTotal']),
        deposited: _asDouble(totals['deposited']),
        pendingDeposit: _asDouble(totals['pendingDeposit']),
        difference: _asDouble(totals['difference']),
      ),
      transfersByBank: (json['transfersByBank'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .map(
            (row) => CloseTransferBankTotal(
              bank: (row['bank'] as String? ?? 'Sin banco especificado').trim(),
              amount: _asDouble(row['amount']),
            ),
          )
          .toList(),
      availableForDeposit: CloseAvailableForDeposit(
        cash: _asDouble(available['cash']),
        transfers: _asDouble(available['transfers']),
        total: _asDouble(available['total']),
      ),
      depositStatus: CloseDepositStatus(
        status: (depositStatus['status'] as String? ?? 'pending').trim(),
        lastDepositDate: depositStatus['lastDepositDate'] == null
            ? null
            : _asDate(depositStatus['lastDepositDate']),
        destinationBank:
            (depositStatus['destinationBank'] as String?)?.trim().isEmpty ==
                true
            ? null
            : depositStatus['destinationBank'] as String?,
      ),
    );
  }
}

class CloseFinancialTotals {
  final double cashDeclared;
  final double cashDelivered;
  final double cashAvailable;
  final double transfers;
  final double cardPayments;
  final double otherIncome;
  final double expenses;
  final double netTotal;
  final double deposited;
  final double pendingDeposit;
  final double difference;

  const CloseFinancialTotals({
    required this.cashDeclared,
    required this.cashDelivered,
    required this.cashAvailable,
    required this.transfers,
    required this.cardPayments,
    required this.otherIncome,
    required this.expenses,
    required this.netTotal,
    required this.deposited,
    required this.pendingDeposit,
    required this.difference,
  });
}

class CloseTransferBankTotal {
  final String bank;
  final double amount;

  const CloseTransferBankTotal({required this.bank, required this.amount});
}

class CloseAvailableForDeposit {
  final double cash;
  final double transfers;
  final double total;

  const CloseAvailableForDeposit({
    required this.cash,
    required this.transfers,
    required this.total,
  });
}

class CloseDepositStatus {
  final String status;
  final DateTime? lastDepositDate;
  final String? destinationBank;

  const CloseDepositStatus({
    required this.status,
    required this.lastDepositDate,
    required this.destinationBank,
  });
}
