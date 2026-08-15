class DepositBankAccountOption {
  const DepositBankAccountOption({
    required this.id,
    required this.bankId,
    required this.label,
    this.accountNumber,
  });

  final String id;
  final String bankId;
  final String label;
  final String? accountNumber;

  factory DepositBankAccountOption.fromJson(Map<String, dynamic> json) {
    return DepositBankAccountOption(
      id: (json['id'] ?? '').toString(),
      bankId: (json['bankId'] ?? json['bank_id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      accountNumber: _nullableString(json['accountNumber']),
    );
  }
}

class DepositBankOption {
  const DepositBankOption({
    required this.id,
    required this.label,
    required this.accounts,
  });

  final String id;
  final String label;
  final List<DepositBankAccountOption> accounts;

  factory DepositBankOption.fromJson(Map<String, dynamic> json) {
    final rawAccounts = json['accounts'] is List
        ? json['accounts'] as List
        : const [];
    return DepositBankOption(
      id: (json['id'] ?? '').toString(),
      label: (json['name'] ?? json['label'] ?? '').toString(),
      accounts: rawAccounts
          .whereType<Map>()
          .map(
            (item) =>
                DepositBankAccountOption.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }
}

const depositBankCatalog = <DepositBankOption>[];

String? _nullableString(dynamic value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}
