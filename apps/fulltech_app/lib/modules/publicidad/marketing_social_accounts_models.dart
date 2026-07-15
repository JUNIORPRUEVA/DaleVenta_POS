enum MarketingSocialAccountType { facebook, instagram, whatsapp }

MarketingSocialAccountType parseMarketingSocialAccountType(String? raw) {
  switch ((raw ?? '').trim().toUpperCase()) {
    case 'INSTAGRAM':
      return MarketingSocialAccountType.instagram;
    case 'WHATSAPP':
      return MarketingSocialAccountType.whatsapp;
    case 'FACEBOOK':
    default:
      return MarketingSocialAccountType.facebook;
  }
}

String marketingSocialAccountTypeApiValue(MarketingSocialAccountType value) {
  switch (value) {
    case MarketingSocialAccountType.facebook:
      return 'FACEBOOK';
    case MarketingSocialAccountType.instagram:
      return 'INSTAGRAM';
    case MarketingSocialAccountType.whatsapp:
      return 'WHATSAPP';
  }
}

class MarketingSocialAccount {
  const MarketingSocialAccount({
    required this.id,
    required this.type,
    required this.accountName,
    required this.username,
    required this.password,
    required this.profileLink,
    required this.whatsappNumber,
    required this.whatsappWaLink,
    required this.observations,
    required this.avatarUrl,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final MarketingSocialAccountType type;
  final String accountName;
  final String? username;
  final String? password;
  final String? profileLink;
  final String? whatsappNumber;
  final String? whatsappWaLink;
  final String? observations;
  final String? avatarUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory MarketingSocialAccount.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic raw) {
      final text = '${raw ?? ''}'.trim();
      if (text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    String? asNullable(dynamic raw) {
      final text = '${raw ?? ''}'.trim();
      return text.isEmpty ? null : text;
    }

    return MarketingSocialAccount(
      id: '${json['id'] ?? ''}',
      type: parseMarketingSocialAccountType('${json['type'] ?? ''}'),
      accountName: '${json['accountName'] ?? ''}',
      username: asNullable(json['username']),
      password: asNullable(json['password']),
      profileLink: asNullable(json['profileLink']),
      whatsappNumber: asNullable(json['whatsappNumber']),
      whatsappWaLink: asNullable(json['whatsappWaLink']),
      observations: asNullable(json['observations']),
      avatarUrl: asNullable(json['avatarUrl']),
      isActive: json['isActive'] == true,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  String get displayUserOrNumber {
    if (type == MarketingSocialAccountType.whatsapp) {
      return (whatsappNumber ?? '').trim().isNotEmpty
          ? whatsappNumber!.trim()
          : 'Sin numero';
    }
    return (username ?? '').trim().isNotEmpty
        ? username!.trim()
        : 'Sin usuario';
  }
}
