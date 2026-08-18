import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../company/company_settings_model.dart';
import '../company/company_settings_repository.dart';

class ProductTaxOption {
  const ProductTaxOption({
    required this.id,
    required this.name,
    required this.rate,
    required this.isDefault,
  });

  final String id;
  final String name;
  final double rate;
  final bool isDefault;

  factory ProductTaxOption.fromJson(Map<String, dynamic> json) {
    return ProductTaxOption(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? 'ITBIS').toString(),
      rate: _double(json['rate']),
      isDefault: json['isDefault'] == true,
    );
  }
}

class ProductTaxUiConfig {
  const ProductTaxUiConfig({required this.settings, required this.activeTaxes});

  final CompanySettings settings;
  final List<ProductTaxOption> activeTaxes;

  double get defaultRate {
    final defaultId = settings.defaultTaxId?.trim();
    if (defaultId != null && defaultId.isNotEmpty) {
      ProductTaxOption? match;
      for (final tax in activeTaxes) {
        if (tax.id == defaultId) {
          match = tax;
          break;
        }
      }
      if (match != null) return match.rate;
    }
    ProductTaxOption? defaultTax;
    for (final tax in activeTaxes) {
      if (tax.isDefault) {
        defaultTax = tax;
        break;
      }
    }
    if (defaultTax != null) return defaultTax.rate;
    if (settings.defaultTaxRate > 0) return settings.defaultTaxRate;
    return activeTaxes.isNotEmpty ? activeTaxes.first.rate : 0;
  }
}

final productTaxUiConfigProvider = FutureProvider<ProductTaxUiConfig>((
  ref,
) async {
  final user = ref.watch(authStateProvider).user;
  final companyKey = user?.companyId ?? user?.email ?? user?.id ?? 'guest';
  final settings = await ref.watch(companySettingsProvider.future);
  if (!settings.taxEnabled) {
    return ProductTaxUiConfig(settings: settings, activeTaxes: const []);
  }

  final dio = ref.watch(dioProvider);
  final res = await dio.get(
    ApiRoutes.taxes,
    options: Options(extra: {'skipLoader': true, 'companyKey': companyKey}),
  );
  final raw = res.data is List ? res.data as List : const [];
  final taxes = raw
      .whereType<Map>()
      .map((row) => ProductTaxOption.fromJson(row.cast<String, dynamic>()))
      .where((tax) => tax.rate > 0)
      .toList(growable: false);
  return ProductTaxUiConfig(settings: settings, activeTaxes: taxes);
});

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
