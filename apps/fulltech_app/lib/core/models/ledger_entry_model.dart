class LedgerEntryModel {
  final String id;
  final String type; // income/expense
  final String description;
  final double amount;
  final DateTime date;

  LedgerEntryModel({
    required this.id,
    required this.type,
    required this.description,
    required this.amount,
    required this.date,
  });

  factory LedgerEntryModel.fromJson(Map<String, dynamic> json) {
    return LedgerEntryModel(
      id: json['id'] ?? '',
      type: json['type'] ?? 'income',
      description: json['description'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      date:
          DateTime.tryParse(json['date'] ?? json['createdAt'] ?? '') ??
          DateTime.now(),
    );
  }
}
