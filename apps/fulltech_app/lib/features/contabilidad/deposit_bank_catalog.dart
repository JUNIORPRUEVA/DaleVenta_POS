class DepositBankAccountOption {
  const DepositBankAccountOption({
    required this.id,
    required this.label,
    this.accountNumber,
  });

  final String id;
  final String label;
  final String? accountNumber;
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
}

const depositBankCatalog = <DepositBankOption>[
  DepositBankOption(
    id: 'popular',
    label: 'Banco Popular',
    accounts: [
      DepositBankAccountOption(
        id: 'popular_yunior_0820297174',
        label: 'Yunior Lopez de la Rosa · 0820297174',
        accountNumber: '0820297174',
      ),
      DepositBankAccountOption(
        id: 'popular_fulltech_0841088008',
        label: 'FULLTECH SRL · 0841088008',
        accountNumber: '0841088008',
      ),
    ],
  ),
  DepositBankOption(
    id: 'banreservas',
    label: 'Banreservas',
    accounts: [
      DepositBankAccountOption(
        id: 'banreservas_yunior_9600921403',
        label: 'Yunior Lopez de la Rosa · 9600921403',
        accountNumber: '9600921403',
      ),
    ],
  ),
  DepositBankOption(
    id: 'bhd',
    label: 'BHD',
    accounts: [
      DepositBankAccountOption(
        id: 'bhd_yunior_28726660019',
        label: 'Yunior Lopez de la Rosa · 28726660019',
        accountNumber: '28726660019',
      ),
    ],
  ),
];
