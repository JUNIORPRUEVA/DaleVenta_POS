import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'printer_settings_model.dart';

final printerSettingsRepositoryProvider = Provider<PrinterSettingsRepository>(
  (_) => PrinterSettingsRepository(),
);

final printerSettingsProvider = FutureProvider<PrinterSettingsModel>((ref) {
  return ref.watch(printerSettingsRepositoryProvider).getOrCreate();
});

class PrinterSettingsRepository {
  static const _key = 'fulltech_printer_settings_v1';

  Future<PrinterSettingsModel?> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return PrinterSettingsModel.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  Future<PrinterSettingsModel> getOrCreate() async {
    final current = await getSettings();
    if (current != null) return current;
    const defaults = PrinterSettingsModel();
    await updateSettings(defaults);
    return defaults;
  }

  Future<void> updateSettings(PrinterSettingsModel settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toMap()));
  }

  Future<PrinterSettingsModel> resetToDefaults() async {
    final current = await getSettings();
    final reset = PrinterSettingsModel(
      selectedPrinterName: current?.selectedPrinterName,
    );
    await updateSettings(reset);
    return reset;
  }

  Future<PrinterSettingsModel> resetToProfessional() async {
    final current = await getSettings();
    final reset = PrinterSettingsModel(
      selectedPrinterName: current?.selectedPrinterName,
      paperWidthMm: 80,
      charsPerLine: 48,
      fontSize: 'normal',
      fontSizeLevel: 6,
      lineSpacingLevel: 5,
      sectionSpacingLevel: 6,
      sectionSeparatorStyle: 'single',
      footerMessage: 'Gracias por su compra',
      showBusinessData: true,
      showSubtotalItbisTotal: true,
    );
    await updateSettings(reset);
    return reset;
  }
}
