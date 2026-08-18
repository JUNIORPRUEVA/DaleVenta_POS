class BankAccountEntry {
  final String name;
  final String type;
  final String accountNumber;
  final String bankName;

  const BankAccountEntry({
    this.name = '',
    this.type = '',
    this.accountNumber = '',
    this.bankName = '',
  });

  BankAccountEntry copyWith({
    String? name,
    String? type,
    String? accountNumber,
    String? bankName,
  }) {
    return BankAccountEntry(
      name: name ?? this.name,
      type: type ?? this.type,
      accountNumber: accountNumber ?? this.accountNumber,
      bankName: bankName ?? this.bankName,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'type': type,
    'accountNumber': accountNumber,
    'bankName': bankName,
  };

  factory BankAccountEntry.fromMap(Map<String, dynamic> map) {
    return BankAccountEntry(
      name: (map['name'] ?? '').toString(),
      type: (map['type'] ?? '').toString(),
      accountNumber: (map['accountNumber'] ?? '').toString(),
      bankName: (map['bankName'] ?? '').toString(),
    );
  }
}

class CompanySettings {
  final String companyName;
  final String rnc;
  final String phone;
  final String phonePreferential;
  final String address;
  final String description;
  final String instagramUrl;
  final String facebookUrl;
  final String websiteUrl;
  final String gpsLocationUrl;
  final String businessHours;
  final List<BankAccountEntry> bankAccounts;
  final String legalRepresentativeName;
  final String legalRepresentativeCedula;
  final String legalRepresentativeRole;
  final String legalRepresentativeNationality;
  final String legalRepresentativeCivilStatus;
  final String? logoBase64;
  final String openAiApiKey;
  final String openAiModel;
  final bool hasOpenAiApiKey;
  final String evolutionApiBaseUrl;
  final String evolutionApiInstanceName;
  final String evolutionApiApiKey;
  final bool hasEvolutionApiApiKey;
  final bool whatsappWebhookEnabled;
  final String productsSource;
  final bool productsReadOnly;
  final bool hasAdminAuthorizationPin;
  final bool taxEnabled;
  final String? defaultTaxId;
  final double defaultTaxRate;
  final bool pricesIncludeTax;
  final bool ncfEnabled;

  const CompanySettings({
    required this.companyName,
    required this.rnc,
    required this.phone,
    this.phonePreferential = '',
    required this.address,
    this.description = '',
    this.instagramUrl = '',
    this.facebookUrl = '',
    this.websiteUrl = '',
    this.gpsLocationUrl = '',
    this.businessHours = '',
    this.bankAccounts = const [],
    required this.legalRepresentativeName,
    required this.legalRepresentativeCedula,
    required this.legalRepresentativeRole,
    required this.legalRepresentativeNationality,
    required this.legalRepresentativeCivilStatus,
    this.logoBase64,
    required this.openAiApiKey,
    required this.openAiModel,
    required this.hasOpenAiApiKey,
    required this.evolutionApiBaseUrl,
    required this.evolutionApiInstanceName,
    required this.evolutionApiApiKey,
    required this.hasEvolutionApiApiKey,
    this.whatsappWebhookEnabled = false,
    this.productsSource = 'LOCAL',
    this.productsReadOnly = false,
    this.hasAdminAuthorizationPin = false,
    this.taxEnabled = false,
    this.defaultTaxId,
    this.defaultTaxRate = 0,
    this.pricesIncludeTax = false,
    this.ncfEnabled = false,
  });

  factory CompanySettings.empty() {
    return const CompanySettings(
      companyName: '',
      rnc: '',
      phone: '',
      phonePreferential: '',
      address: '',
      description: '',
      instagramUrl: '',
      facebookUrl: '',
      websiteUrl: '',
      gpsLocationUrl: '',
      businessHours: '',
      bankAccounts: [],
      legalRepresentativeName: '',
      legalRepresentativeCedula: '',
      legalRepresentativeRole: '',
      legalRepresentativeNationality: '',
      legalRepresentativeCivilStatus: '',
      logoBase64: null,
      openAiApiKey: '',
      openAiModel: 'gpt-4o-mini',
      hasOpenAiApiKey: false,
      evolutionApiBaseUrl: '',
      evolutionApiInstanceName: '',
      evolutionApiApiKey: '',
      hasEvolutionApiApiKey: false,
      whatsappWebhookEnabled: false,
      productsSource: 'LOCAL',
      productsReadOnly: false,
      hasAdminAuthorizationPin: false,
      taxEnabled: false,
      defaultTaxId: null,
      defaultTaxRate: 0,
      pricesIncludeTax: false,
      ncfEnabled: false,
    );
  }

  CompanySettings copyWith({
    String? companyName,
    String? rnc,
    String? phone,
    String? phonePreferential,
    String? address,
    String? description,
    String? instagramUrl,
    String? facebookUrl,
    String? websiteUrl,
    String? gpsLocationUrl,
    String? businessHours,
    List<BankAccountEntry>? bankAccounts,
    String? legalRepresentativeName,
    String? legalRepresentativeCedula,
    String? legalRepresentativeRole,
    String? legalRepresentativeNationality,
    String? legalRepresentativeCivilStatus,
    String? logoBase64,
    String? openAiApiKey,
    String? openAiModel,
    bool? hasOpenAiApiKey,
    String? evolutionApiBaseUrl,
    String? evolutionApiInstanceName,
    String? evolutionApiApiKey,
    bool? hasEvolutionApiApiKey,
    bool? whatsappWebhookEnabled,
    String? productsSource,
    bool? productsReadOnly,
    bool? hasAdminAuthorizationPin,
    bool? taxEnabled,
    String? defaultTaxId,
    double? defaultTaxRate,
    bool? pricesIncludeTax,
    bool? ncfEnabled,
    bool clearLogo = false,
  }) {
    return CompanySettings(
      companyName: companyName ?? this.companyName,
      rnc: rnc ?? this.rnc,
      phone: phone ?? this.phone,
      phonePreferential: phonePreferential ?? this.phonePreferential,
      address: address ?? this.address,
      description: description ?? this.description,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      facebookUrl: facebookUrl ?? this.facebookUrl,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      gpsLocationUrl: gpsLocationUrl ?? this.gpsLocationUrl,
      businessHours: businessHours ?? this.businessHours,
      bankAccounts: bankAccounts ?? this.bankAccounts,
      legalRepresentativeName:
          legalRepresentativeName ?? this.legalRepresentativeName,
      legalRepresentativeCedula:
          legalRepresentativeCedula ?? this.legalRepresentativeCedula,
      legalRepresentativeRole:
          legalRepresentativeRole ?? this.legalRepresentativeRole,
      legalRepresentativeNationality:
          legalRepresentativeNationality ?? this.legalRepresentativeNationality,
      legalRepresentativeCivilStatus:
          legalRepresentativeCivilStatus ?? this.legalRepresentativeCivilStatus,
      logoBase64: clearLogo ? null : (logoBase64 ?? this.logoBase64),
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      openAiModel: openAiModel ?? this.openAiModel,
      hasOpenAiApiKey: hasOpenAiApiKey ?? this.hasOpenAiApiKey,
      evolutionApiBaseUrl: evolutionApiBaseUrl ?? this.evolutionApiBaseUrl,
      evolutionApiInstanceName:
          evolutionApiInstanceName ?? this.evolutionApiInstanceName,
      evolutionApiApiKey: evolutionApiApiKey ?? this.evolutionApiApiKey,
      hasEvolutionApiApiKey:
          hasEvolutionApiApiKey ?? this.hasEvolutionApiApiKey,
      whatsappWebhookEnabled:
          whatsappWebhookEnabled ?? this.whatsappWebhookEnabled,
      productsSource: productsSource ?? this.productsSource,
      productsReadOnly: productsReadOnly ?? this.productsReadOnly,
      hasAdminAuthorizationPin:
          hasAdminAuthorizationPin ?? this.hasAdminAuthorizationPin,
      taxEnabled: taxEnabled ?? this.taxEnabled,
      defaultTaxId: defaultTaxId ?? this.defaultTaxId,
      defaultTaxRate: defaultTaxRate ?? this.defaultTaxRate,
      pricesIncludeTax: pricesIncludeTax ?? this.pricesIncludeTax,
      ncfEnabled: ncfEnabled ?? this.ncfEnabled,
    );
  }

  Map<String, dynamic> toMap() => {
    'companyName': companyName,
    'rnc': rnc,
    'phone': phone,
    'phonePreferential': phonePreferential,
    'address': address,
    'description': description,
    'instagramUrl': instagramUrl,
    'facebookUrl': facebookUrl,
    'websiteUrl': websiteUrl,
    'gpsLocationUrl': gpsLocationUrl,
    'businessHours': businessHours,
    'bankAccounts': bankAccounts.map((e) => e.toMap()).toList(),
    'legalRepresentativeName': legalRepresentativeName,
    'legalRepresentativeCedula': legalRepresentativeCedula,
    'legalRepresentativeRole': legalRepresentativeRole,
    'legalRepresentativeNationality': legalRepresentativeNationality,
    'legalRepresentativeCivilStatus': legalRepresentativeCivilStatus,
    'logoBase64': logoBase64,
    'openAiApiKey': openAiApiKey,
    'openAiModel': openAiModel,
    'hasOpenAiApiKey': hasOpenAiApiKey,
    'evolutionApiBaseUrl': evolutionApiBaseUrl,
    'evolutionApiInstanceName': evolutionApiInstanceName,
    'evolutionApiApiKey': evolutionApiApiKey,
    'hasEvolutionApiApiKey': hasEvolutionApiApiKey,
    'whatsappWebhookEnabled': whatsappWebhookEnabled,
    'productsSource': productsSource,
    'productsReadOnly': productsReadOnly,
    'hasAdminAuthorizationPin': hasAdminAuthorizationPin,
    'taxEnabled': taxEnabled,
    'defaultTaxId': defaultTaxId,
    'defaultTaxRate': defaultTaxRate,
    'pricesIncludeTax': pricesIncludeTax,
    'ncfEnabled': ncfEnabled,
  };

  factory CompanySettings.fromMap(Map<String, dynamic> map) {
    List<BankAccountEntry> parseBankAccounts(dynamic raw) {
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => BankAccountEntry.fromMap(e.cast<String, dynamic>()))
          .toList();
    }

    return CompanySettings(
      companyName: (map['companyName'] ?? '').toString(),
      rnc: (map['rnc'] ?? '').toString(),
      phone: (map['phone'] ?? '').toString(),
      phonePreferential: (map['phonePreferential'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      instagramUrl: (map['instagramUrl'] ?? '').toString(),
      facebookUrl: (map['facebookUrl'] ?? '').toString(),
      websiteUrl: (map['websiteUrl'] ?? '').toString(),
      gpsLocationUrl: (map['gpsLocationUrl'] ?? '').toString(),
      businessHours: (map['businessHours'] ?? '').toString(),
      bankAccounts: parseBankAccounts(map['bankAccounts']),
      legalRepresentativeName: (map['legalRepresentativeName'] ?? '')
          .toString(),
      legalRepresentativeCedula: (map['legalRepresentativeCedula'] ?? '')
          .toString(),
      legalRepresentativeRole: (map['legalRepresentativeRole'] ?? '')
          .toString(),
      legalRepresentativeNationality:
          (map['legalRepresentativeNationality'] ?? '').toString(),
      legalRepresentativeCivilStatus:
          (map['legalRepresentativeCivilStatus'] ?? '').toString(),
      logoBase64: map['logoBase64']?.toString(),
      openAiApiKey: (map['openAiApiKey'] ?? '').toString(),
      openAiModel: (map['openAiModel'] ?? 'gpt-4o-mini').toString(),
      hasOpenAiApiKey: map['hasOpenAiApiKey'] == true,
      evolutionApiBaseUrl: (map['evolutionApiBaseUrl'] ?? '').toString(),
      evolutionApiInstanceName: (map['evolutionApiInstanceName'] ?? '')
          .toString(),
      evolutionApiApiKey: (map['evolutionApiApiKey'] ?? '').toString(),
      hasEvolutionApiApiKey: map['hasEvolutionApiApiKey'] == true,
      whatsappWebhookEnabled: map['whatsappWebhookEnabled'] == true,
      productsSource: (map['productsSource'] ?? 'LOCAL').toString(),
      productsReadOnly: map['productsReadOnly'] == true,
      hasAdminAuthorizationPin: map['hasAdminAuthorizationPin'] == true,
      taxEnabled: map['taxEnabled'] == true,
      defaultTaxId: map['defaultTaxId']?.toString(),
      defaultTaxRate: _double(map['defaultTaxRate']),
      pricesIncludeTax: map['pricesIncludeTax'] == true,
      ncfEnabled: map['ncfEnabled'] == true,
    );
  }
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString()) ?? 0;
}
