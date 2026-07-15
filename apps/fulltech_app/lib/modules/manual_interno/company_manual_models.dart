import '../../core/auth/app_role.dart';

enum CompanyManualEntryKind {
  generalRule,
  roleRule,
  policy,
  warrantyPolicy,
  responsibility,
  productService,
  priceRule,
  serviceRule,
  moduleGuide,
}

enum CompanyManualAudience { general, roleSpecific }

extension CompanyManualEntryKindX on CompanyManualEntryKind {
  String get apiValue {
    switch (this) {
      case CompanyManualEntryKind.generalRule:
        return 'GENERAL_RULE';
      case CompanyManualEntryKind.roleRule:
        return 'ROLE_RULE';
      case CompanyManualEntryKind.policy:
        return 'POLICY';
      case CompanyManualEntryKind.warrantyPolicy:
        return 'WARRANTY_POLICY';
      case CompanyManualEntryKind.responsibility:
        return 'RESPONSIBILITY';
      case CompanyManualEntryKind.productService:
        return 'PRODUCT_SERVICE';
      case CompanyManualEntryKind.priceRule:
        return 'PRICE_RULE';
      case CompanyManualEntryKind.serviceRule:
        return 'SERVICE_RULE';
      case CompanyManualEntryKind.moduleGuide:
        return 'MODULE_GUIDE';
    }
  }

  String get label {
    switch (this) {
      case CompanyManualEntryKind.generalRule:
        return 'Regla general';
      case CompanyManualEntryKind.roleRule:
        return 'Regla por rol';
      case CompanyManualEntryKind.policy:
        return 'Política';
      case CompanyManualEntryKind.warrantyPolicy:
        return 'Política de garantía';
      case CompanyManualEntryKind.responsibility:
        return 'Responsabilidad';
      case CompanyManualEntryKind.productService:
        return 'Producto o servicio';
      case CompanyManualEntryKind.priceRule:
        return 'Regla de precios';
      case CompanyManualEntryKind.serviceRule:
        return 'Regla de servicio';
      case CompanyManualEntryKind.moduleGuide:
        return 'Guía de módulo';
    }
  }

  static CompanyManualEntryKind fromApi(String value) {
    switch (value.toUpperCase()) {
      case 'GENERAL_RULE':
        return CompanyManualEntryKind.generalRule;
      case 'ROLE_RULE':
        return CompanyManualEntryKind.roleRule;
      case 'POLICY':
        return CompanyManualEntryKind.policy;
      case 'WARRANTY_POLICY':
        return CompanyManualEntryKind.warrantyPolicy;
      case 'RESPONSIBILITY':
        return CompanyManualEntryKind.responsibility;
      case 'PRODUCT_SERVICE':
        return CompanyManualEntryKind.productService;
      case 'PRICE_RULE':
        return CompanyManualEntryKind.priceRule;
      case 'SERVICE_RULE':
        return CompanyManualEntryKind.serviceRule;
      case 'MODULE_GUIDE':
      default:
        return CompanyManualEntryKind.moduleGuide;
    }
  }
}

extension CompanyManualAudienceX on CompanyManualAudience {
  String get apiValue =>
      this == CompanyManualAudience.general ? 'GENERAL' : 'ROLE_SPECIFIC';

  String get label =>
      this == CompanyManualAudience.general ? 'General' : 'Por rol';

  static CompanyManualAudience fromApi(String value) {
    return value.toUpperCase() == 'ROLE_SPECIFIC'
        ? CompanyManualAudience.roleSpecific
        : CompanyManualAudience.general;
  }
}

class CompanyManualEntry {
  final String id;
  final String ownerId;
  final String title;
  final String? summary;
  final String content;
  final CompanyManualEntryKind kind;
  final CompanyManualAudience audience;
  final List<AppRole> targetRoles;
  final String? moduleKey;
  final bool published;
  final int sortOrder;
  final String createdByUserId;
  final String? updatedByUserId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const CompanyManualEntry({
    required this.id,
    required this.ownerId,
    required this.title,
    this.summary,
    required this.content,
    required this.kind,
    required this.audience,
    this.targetRoles = const [],
    this.moduleKey,
    this.published = true,
    this.sortOrder = 0,
    required this.createdByUserId,
    this.updatedByUserId,
    this.createdAt,
    this.updatedAt,
  });

  factory CompanyManualEntry.fromMap(Map<String, dynamic> map) {
    final rolesRaw = map['targetRoles'];
    final roles = rolesRaw is List
        ? rolesRaw
              .whereType<String>()
              .map(parseAppRole)
              .where((role) => role != AppRole.unknown)
              .toList(growable: false)
        : const <AppRole>[];

    return CompanyManualEntry(
      id: (map['id'] ?? '').toString(),
      ownerId: (map['ownerId'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      summary: (map['summary'] as String?)?.trim().isEmpty == true
          ? null
          : map['summary'] as String?,
      content: (map['content'] ?? '').toString(),
      kind: CompanyManualEntryKindX.fromApi((map['kind'] ?? '').toString()),
      audience: CompanyManualAudienceX.fromApi(
        (map['audience'] ?? '').toString(),
      ),
      targetRoles: roles,
      moduleKey: (map['moduleKey'] as String?)?.trim().isEmpty == true
          ? null
          : map['moduleKey'] as String?,
      published: map['published'] != false,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      createdByUserId: (map['createdByUserId'] ?? '').toString(),
      updatedByUserId: map['updatedByUserId']?.toString(),
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'].toString())
          : null,
    );
  }

  CompanyManualEntry copyWith({
    String? id,
    String? ownerId,
    String? title,
    String? summary,
    bool clearSummary = false,
    String? content,
    CompanyManualEntryKind? kind,
    CompanyManualAudience? audience,
    List<AppRole>? targetRoles,
    String? moduleKey,
    bool clearModuleKey = false,
    bool? published,
    int? sortOrder,
    String? createdByUserId,
    String? updatedByUserId,
    bool clearUpdatedByUserId = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CompanyManualEntry(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      title: title ?? this.title,
      summary: clearSummary ? null : (summary ?? this.summary),
      content: content ?? this.content,
      kind: kind ?? this.kind,
      audience: audience ?? this.audience,
      targetRoles: targetRoles ?? this.targetRoles,
      moduleKey: clearModuleKey ? null : (moduleKey ?? this.moduleKey),
      published: published ?? this.published,
      sortOrder: sortOrder ?? this.sortOrder,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      updatedByUserId: clearUpdatedByUserId
          ? null
          : (updatedByUserId ?? this.updatedByUserId),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'ownerId': ownerId,
      'title': title,
      'summary': summary,
      'content': content,
      'kind': kind.apiValue,
      'audience': audience.apiValue,
      'targetRoles': targetRoles
          .map(toApiRole)
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
      'moduleKey': moduleKey,
      'published': published,
      'sortOrder': sortOrder,
      'createdByUserId': createdByUserId,
      'updatedByUserId': updatedByUserId,
      'createdAt': createdAt?.toUtc().toIso8601String(),
      'updatedAt': updatedAt?.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toUpsertDto() {
    final idTrimmed = id.trim();
    return {
      if (idTrimmed.isNotEmpty) 'id': idTrimmed,
      'title': title,
      'summary': summary,
      'content': content,
      'kind': kind.apiValue,
      'audience': audience.apiValue,
      'targetRoles': targetRoles
          .map(toApiRole)
          .where((e) => e.isNotEmpty)
          .toList(),
      'moduleKey': moduleKey,
      'published': published,
      'sortOrder': sortOrder,
    };
  }
}

class CompanyManualSummary {
  final int totalCount;
  final int unreadCount;
  final DateTime? latestUpdatedAt;

  const CompanyManualSummary({
    required this.totalCount,
    required this.unreadCount,
    required this.latestUpdatedAt,
  });

  const CompanyManualSummary.empty()
    : this(totalCount: 0, unreadCount: 0, latestUpdatedAt: null);

  factory CompanyManualSummary.fromMap(Map<String, dynamic> map) {
    return CompanyManualSummary(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      unreadCount: (map['unreadCount'] as num?)?.toInt() ?? 0,
      latestUpdatedAt: map['latestUpdatedAt'] != null
          ? DateTime.tryParse(map['latestUpdatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalCount': totalCount,
      'unreadCount': unreadCount,
      'latestUpdatedAt': latestUpdatedAt?.toUtc().toIso8601String(),
    };
  }
}
