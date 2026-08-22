import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_routes.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../cache/local_json_cache.dart';
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

/// TTL de la caché de impuestos activos por empresa.
///
/// Los impuestos cambian con poca frecuencia. Se usa cache-first con un TTL
/// corto (1 hora) para que la pantalla de Facturación no consulte `/taxes`
/// en cada apertura, mientras que el backend sigue siendo la fuente de verdad
/// para el cálculo/validación transaccional de impuestos en cada venta.
const Duration _taxesCacheTtl = Duration(hours: 1);

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
  final taxes = await loadActiveTaxes(dio, companyKey);
  return ProductTaxUiConfig(settings: settings, activeTaxes: taxes);
});

/// Carga los impuestos activos de la empresa con cache-first + SWR.
///
/// La clave de caché incluye la empresa (`taxes_cache_v1:company:<companyId>`),
/// de modo que cada empresa tiene su propia caché y jamás se comparte entre
/// tenants. Si existe caché fresca se muestra de inmediato y se refresca el
/// servidor en segundo plano (la caché se actualiza para la próxima apertura).
///
/// `cache` es inyectable para tests (mismo patrón que `CatalogRepository`);
/// por defecto usa `LocalJsonCache()` real.
Future<List<ProductTaxOption>> loadActiveTaxes(
  Dio dio,
  String companyKey, {
  LocalJsonCache? cache,
}) async {
  const cacheKeyPrefix = 'taxes_cache_v1';
  final cacheKey = '$cacheKeyPrefix:company:$companyKey';
  final cacheInstance = cache ?? LocalJsonCache();

  List<ProductTaxOption> parse(dynamic data) {
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => ProductTaxOption.fromJson(Map<String, dynamic>.from(row)))
        .where((tax) => tax.rate > 0)
        .toList(growable: false);
  }

  // 1) cache-first: mostrar inmediatamente si hay cache fresca de esta empresa.
  final cached = await cacheInstance.readMap(cacheKey, maxAge: _taxesCacheTtl);
  if (cached != null) {
    final rows = cached['taxes'];
    if (rows is List && rows.isNotEmpty) {
      final fromCache = parse(rows);
      // 3) refrescar en background y actualizar la cache para la próxima vez.
      unawaited(
        _refreshTaxesInBackground(
          dio,
          cacheKey,
          companyKey,
          (data) => _persistTaxes(cacheInstance, cacheKey, parse(data)),
        ),
      );
      return fromCache;
    }
  }

  // 2) sin cache fresca: consultar servidor y guardar.
  final res = await dio.get(
    ApiRoutes.taxes,
    options: Options(extra: {'skipLoader': true, 'companyKey': companyKey}),
  );
  final taxes = parse(res.data);
  unawaited(_persistTaxes(cacheInstance, cacheKey, taxes));
  return taxes;
}

Future<void> _refreshTaxesInBackground(
  Dio dio,
  String cacheKey,
  String companyKey,
  Future<void> Function(dynamic data) onLoaded,
) async {
  try {
    final res = await dio.get(
      ApiRoutes.taxes,
      options: Options(extra: {'skipLoader': true, 'companyKey': companyKey}),
    );
    await onLoaded(res.data);
  } catch (_) {
    // El refresco en segundo plano nunca debe romper la UI.
  }
}

Future<void> _persistTaxes(
  LocalJsonCache cache,
  String cacheKey,
  List<ProductTaxOption> taxes,
) async {
  try {
    await cache.writeMap(cacheKey, {
      'taxes': taxes
          .map(
            (tax) => {
              'id': tax.id,
              'name': tax.name,
              'rate': tax.rate,
              'isDefault': tax.isDefault,
            },
          )
          .toList(growable: false),
    });
  } catch (_) {
    // Fallo de escritura de cache: no debe afectar la carga.
  }
}

double _double(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
