double _asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

enum PayableProviderKind { person, company }

extension PayableProviderKindX on PayableProviderKind {
  String get apiValue {
    switch (this) {
      case PayableProviderKind.person:
        return 'PERSON';
      case PayableProviderKind.company:
        return 'COMPANY';
    }
  }

  String get label {
    switch (this) {
      case PayableProviderKind.person:
        return 'Persona';
      case PayableProviderKind.company:
        return 'Empresa';
    }
  }

  static PayableProviderKind fromApi(String raw) {
    return raw.trim().toUpperCase() == 'COMPANY'
        ? PayableProviderKind.company
        : PayableProviderKind.person;
  }
}

enum PayableFrequency { oneTime, monthly, biweekly }

extension PayableFrequencyX on PayableFrequency {
  String get apiValue {
    switch (this) {
      case PayableFrequency.oneTime:
        return 'ONE_TIME';
      case PayableFrequency.monthly:
        return 'MONTHLY';
      case PayableFrequency.biweekly:
        return 'BIWEEKLY';
    }
  }

  String get label {
    switch (this) {
      case PayableFrequency.oneTime:
        return 'Único';
      case PayableFrequency.monthly:
        return 'Mensual';
      case PayableFrequency.biweekly:
        return 'Quincenal';
    }
  }

  static PayableFrequency fromApi(String raw) {
    final value = raw.trim().toUpperCase();
    if (value == 'MONTHLY') return PayableFrequency.monthly;
    if (value == 'BIWEEKLY') return PayableFrequency.biweekly;
    return PayableFrequency.oneTime;
  }
}

class PayableService {
  final String id;
  final String title;
  final PayableProviderKind providerKind;
  final String providerName;
  final String? description;
  final PayableFrequency frequency;
  final double? defaultAmount;
  final DateTime nextDueDate;
  final DateTime? lastPaidAt;
  final bool active;
  final String? createdByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PayablePayment> payments;

  const PayableService({
    required this.id,
    required this.title,
    required this.providerKind,
    required this.providerName,
    this.description,
    required this.frequency,
    required this.defaultAmount,
    required this.nextDueDate,
    this.lastPaidAt,
    required this.active,
    this.createdByName,
    required this.createdAt,
    required this.updatedAt,
    this.payments = const [],
  });

  factory PayableService.fromJson(Map<String, dynamic> json) {
    final rows = (json['payments'] is List)
        ? (json['payments'] as List)
        : const [];
    return PayableService(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      providerKind: PayableProviderKindX.fromApi(
        (json['providerKind'] ?? '').toString(),
      ),
      providerName: (json['providerName'] ?? '').toString(),
      description: (json['description'] as String?)?.trim().isEmpty == true
          ? null
          : json['description'] as String?,
      frequency: PayableFrequencyX.fromApi(
        (json['frequency'] ?? '').toString(),
      ),
      defaultAmount: json['defaultAmount'] == null
          ? null
          : _asDouble(json['defaultAmount']),
      nextDueDate: DateTime.parse(json['nextDueDate'].toString()),
      lastPaidAt: json['lastPaidAt'] == null
          ? null
          : DateTime.parse(json['lastPaidAt'].toString()),
      active: json['active'] == true,
      createdByName: json['createdByName'] as String?,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      updatedAt: DateTime.parse(json['updatedAt'].toString()),
      payments: rows
          .whereType<Map>()
          .map((item) => PayablePayment.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class PayablePayment {
  final String id;
  final String serviceId;
  final double amount;
  final DateTime paidAt;
  final String? note;
  final String? createdByName;
  final DateTime createdAt;
  final PayableServiceRef? service;

  const PayablePayment({
    required this.id,
    required this.serviceId,
    required this.amount,
    required this.paidAt,
    this.note,
    this.createdByName,
    required this.createdAt,
    this.service,
  });

  factory PayablePayment.fromJson(Map<String, dynamic> json) {
    final serviceMap = json['service'];
    return PayablePayment(
      id: (json['id'] ?? '').toString(),
      serviceId: (json['serviceId'] ?? '').toString(),
      amount: _asDouble(json['amount']),
      paidAt: DateTime.parse(json['paidAt'].toString()),
      note: (json['note'] as String?)?.trim().isEmpty == true
          ? null
          : json['note'] as String?,
      createdByName: json['createdByName'] as String?,
      createdAt: DateTime.parse(json['createdAt'].toString()),
      service: serviceMap is Map
          ? PayableServiceRef.fromJson(serviceMap.cast<String, dynamic>())
          : null,
    );
  }
}

class PayableServiceRef {
  final String id;
  final String title;
  final String providerName;
  final PayableProviderKind providerKind;
  final PayableFrequency frequency;

  const PayableServiceRef({
    required this.id,
    required this.title,
    required this.providerName,
    required this.providerKind,
    required this.frequency,
  });

  factory PayableServiceRef.fromJson(Map<String, dynamic> json) {
    return PayableServiceRef(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      providerName: (json['providerName'] ?? '').toString(),
      providerKind: PayableProviderKindX.fromApi(
        (json['providerKind'] ?? '').toString(),
      ),
      frequency: PayableFrequencyX.fromApi(
        (json['frequency'] ?? '').toString(),
      ),
    );
  }
}
