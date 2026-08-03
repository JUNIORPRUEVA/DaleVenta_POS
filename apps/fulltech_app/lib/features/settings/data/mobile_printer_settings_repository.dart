import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/auth_provider.dart';
import 'mobile_printer_settings_model.dart';

final mobilePrinterCompanyScopeProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).user;
  final id = (user?.id ?? '').trim();
  return id.isEmpty ? 'default' : id;
});

final mobilePrinterSettingsRepositoryProvider =
    Provider<MobilePrinterSettingsRepository>((ref) {
      return MobilePrinterSettingsRepository(
        companyScope: ref.watch(mobilePrinterCompanyScopeProvider),
      );
    });

final mobilePrinterSettingsProvider =
    FutureProvider<MobilePrinterSettingsModel>((ref) {
      return ref.watch(mobilePrinterSettingsRepositoryProvider).getOrCreate();
    });

class MobilePrinterSettingsRepository {
  MobilePrinterSettingsRepository({required this.companyScope});

  final String companyScope;

  static const _prefix = 'fulltech_mobile_printer_settings_v1';

  String get _key => '$_prefix:$companyScope';

  Future<MobilePrinterSettingsModel> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
        return MobilePrinterSettingsModel.fromMap(
          map,
        ).copyWith(companyScope: companyScope);
      } catch (_) {
        // Corrupt local settings should not block printer configuration.
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaults = MobilePrinterSettingsModel(
      companyScope: companyScope,
      updatedAtMs: now,
    );
    await update(defaults);
    return defaults;
  }

  Future<void> update(MobilePrinterSettingsModel settings) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = settings.copyWith(
      companyScope: companyScope,
      paperWidthMm: settings.paperWidthMm,
      copies: settings.copies.clamp(1, 5),
      timeoutSeconds: settings.timeoutSeconds.clamp(2, 30),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(_key, jsonEncode(normalized.toMap()));
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
