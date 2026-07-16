double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse((value ?? '').toString()) ?? 0;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

class ActiveCashSession {
  const ActiveCashSession({
    required this.userId,
    required this.shiftId,
    required this.openedAt,
    required this.status,
    required this.userName,
    required this.businessDate,
    this.cashId,
  });

  final String userId;
  final String? cashId;
  final String shiftId;
  final DateTime openedAt;
  final String status;
  final String userName;
  final String businessDate;

  bool get isOpen => status == 'OPEN';

  factory ActiveCashSession.fromJson(Map<String, dynamic> json) {
    return ActiveCashSession(
      userId: (json['userId'] ?? '').toString(),
      cashId: json['cashId']?.toString(),
      shiftId: (json['shiftId'] ?? '').toString(),
      openedAt: _asDate(json['openedAt']) ?? DateTime.now(),
      status: (json['status'] ?? '').toString(),
      userName: (json['userName'] ?? 'Usuario').toString(),
      businessDate: (json['businessDate'] ?? '').toString(),
    );
  }
}

class CashGateState {
  const CashGateState({
    required this.businessDate,
    required this.canOperate,
    this.activeSession,
  });

  final String businessDate;
  final bool canOperate;
  final ActiveCashSession? activeSession;

  factory CashGateState.fromJson(Map<String, dynamic> json) {
    final active = json['activeSession'];
    return CashGateState(
      businessDate: (json['businessDate'] ?? '').toString(),
      canOperate: json['canOperate'] == true,
      activeSession: active is Map
          ? ActiveCashSession.fromJson(active.cast<String, dynamic>())
          : null,
    );
  }
}

class CashSummaryModel {
  const CashSummaryModel({
    required this.openingAmount,
    required this.totalSales,
    required this.totalExpenses,
    required this.totalWithdrawals,
    required this.cashInManual,
    required this.cashOutManual,
    required this.creditAbonos,
    required this.creditSalesTotal,
    required this.creditInitialCash,
    required this.creditInitialTransfer,
    required this.creditBalanceTotal,
    required this.creditPaymentCash,
    required this.creditPaymentTransfer,
    required this.salesCashTotal,
    required this.salesTransferTotal,
    required this.refundsCash,
    required this.expectedCash,
    required this.totalTickets,
    required this.totalRefunds,
    required this.categorySummary,
  });

  final double openingAmount;
  final double totalSales;
  final double totalExpenses;
  final double totalWithdrawals;
  final double cashInManual;
  final double cashOutManual;
  final double creditAbonos;
  final double creditSalesTotal;
  final double creditInitialCash;
  final double creditInitialTransfer;
  final double creditBalanceTotal;
  final double creditPaymentCash;
  final double creditPaymentTransfer;
  final double salesCashTotal;
  final double salesTransferTotal;
  final double refundsCash;
  final double expectedCash;
  final int totalTickets;
  final int totalRefunds;
  final List<CashCategorySummaryModel> categorySummary;

  double difference(double closingAmount) => closingAmount - expectedCash;

  factory CashSummaryModel.fromJson(Map<String, dynamic> json) {
    return CashSummaryModel(
      openingAmount: _asDouble(json['openingAmount']),
      totalSales: _asDouble(json['totalSales']),
      totalExpenses: _asDouble(json['totalExpenses']),
      totalWithdrawals: _asDouble(json['totalWithdrawals']),
      cashInManual: _asDouble(json['cashInManual']),
      cashOutManual: _asDouble(json['cashOutManual']),
      creditAbonos: _asDouble(json['creditAbonos']),
      creditSalesTotal: _asDouble(json['creditSalesTotal']),
      creditInitialCash: _asDouble(json['creditInitialCash']),
      creditInitialTransfer: _asDouble(json['creditInitialTransfer']),
      creditBalanceTotal: _asDouble(json['creditBalanceTotal']),
      creditPaymentCash: _asDouble(json['creditPaymentCash']),
      creditPaymentTransfer: _asDouble(json['creditPaymentTransfer']),
      salesCashTotal: _asDouble(json['salesCashTotal']),
      salesTransferTotal: _asDouble(json['salesTransferTotal']),
      refundsCash: _asDouble(json['refundsCash']),
      expectedCash: _asDouble(json['expectedCash']),
      totalTickets: (json['totalTickets'] as num?)?.toInt() ?? 0,
      totalRefunds: (json['totalRefunds'] as num?)?.toInt() ?? 0,
      categorySummary: ((json['categorySummary'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                CashCategorySummaryModel.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }
}

class CashCategorySummaryModel {
  const CashCategorySummaryModel({
    required this.category,
    required this.totalSold,
    required this.totalProfit,
    required this.items,
  });

  final String category;
  final double totalSold;
  final double totalProfit;
  final int items;

  factory CashCategorySummaryModel.fromJson(Map<String, dynamic> json) {
    return CashCategorySummaryModel(
      category: (json['category'] ?? 'Sin categoria').toString(),
      totalSold: _asDouble(json['totalSold']),
      totalProfit: _asDouble(json['totalProfit']),
      items: (json['items'] as num?)?.toInt() ?? 0,
    );
  }
}

class CashMovementModel {
  const CashMovementModel({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.amount,
    required this.reason,
    required this.movementType,
    required this.affectsProfit,
    required this.createdAt,
    this.userName,
    this.businessDate,
    this.sessionStatus,
  });

  final String id;
  final String sessionId;
  final String type;
  final double amount;
  final String reason;
  final String movementType;
  final bool affectsProfit;
  final DateTime createdAt;
  final String? userName;
  final String? businessDate;
  final String? sessionStatus;

  bool get isIn => type == 'IN';

  factory CashMovementModel.fromJson(Map<String, dynamic> json) {
    return CashMovementModel(
      id: (json['id'] ?? '').toString(),
      sessionId: (json['sessionId'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      amount: _asDouble(json['amount']),
      reason: (json['reason'] ?? '').toString(),
      movementType: (json['movementType'] ?? 'expense').toString(),
      affectsProfit: json['affectsProfit'] != false,
      createdAt: _asDate(json['createdAt']) ?? DateTime.now(),
      userName: json['userName']?.toString(),
      businessDate: json['businessDate']?.toString(),
      sessionStatus: json['sessionStatus']?.toString(),
    );
  }
}

class CashSessionHistoryModel {
  const CashSessionHistoryModel({
    required this.id,
    required this.userName,
    required this.businessDate,
    required this.openedAt,
    this.closedAt,
    required this.initialAmount,
    required this.closingAmount,
    required this.expectedAmount,
    required this.difference,
    required this.status,
  });

  final String id;
  final String userName;
  final String businessDate;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double initialAmount;
  final double closingAmount;
  final double expectedAmount;
  final double difference;
  final String status;

  factory CashSessionHistoryModel.fromJson(Map<String, dynamic> json) {
    return CashSessionHistoryModel(
      id: (json['id'] ?? '').toString(),
      userName: (json['userName'] ?? 'Usuario').toString(),
      businessDate: (json['businessDate'] ?? '').toString(),
      openedAt: _asDate(json['openedAt']) ?? DateTime.now(),
      closedAt: _asDate(json['closedAt']),
      initialAmount: _asDouble(json['initialAmount']),
      closingAmount: _asDouble(json['closingAmount']),
      expectedAmount: _asDouble(json['expectedAmount']),
      difference: _asDouble(json['difference']),
      status: (json['status'] ?? '').toString(),
    );
  }
}
