import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/storage/local_database_path.dart';
import 'printer_settings_model.dart';

final printerSettingsRepositoryProvider = Provider<PrinterSettingsRepository>(
  (_) => PrinterSettingsRepository(),
);

final printerSettingsProvider = FutureProvider<PrinterSettingsModel>((ref) {
  return ref.watch(printerSettingsRepositoryProvider).getOrCreate();
});

class PrinterSettingsRepository {
  static const _legacyKey = 'fulltech_printer_settings_v1';
  static const _dbName = 'fulltech_printing.db';
  static const _table = 'printer_settings';

  Database? _db;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    final path = await resolveLocalDatabasePath(_dbName);
    final db = await openDatabase(path, version: 1);
    _db = db;
    await _ensureSchema(db);
    return db;
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY,
        selectedPrinterName TEXT,
        paperWidthMm INTEGER NOT NULL DEFAULT 80,
        charsPerLine INTEGER NOT NULL DEFAULT 48,
        autoPrintOnPayment INTEGER NOT NULL DEFAULT 1,
        autoOpenDrawerOnChargeWithoutTicket INTEGER NOT NULL DEFAULT 0,
        copies INTEGER NOT NULL DEFAULT 1,
        showItbis INTEGER NOT NULL DEFAULT 1,
        showElectronicInvoiceReference INTEGER NOT NULL DEFAULT 1,
        showCashier INTEGER NOT NULL DEFAULT 1,
        showClient INTEGER NOT NULL DEFAULT 1,
        showPaymentMethod INTEGER NOT NULL DEFAULT 1,
        showDiscounts INTEGER NOT NULL DEFAULT 1,
        showCode INTEGER NOT NULL DEFAULT 1,
        showDatetime INTEGER NOT NULL DEFAULT 1,
        headerBusinessName TEXT NOT NULL DEFAULT 'FULLPOS',
        headerRnc TEXT NOT NULL DEFAULT '',
        headerAddress TEXT NOT NULL DEFAULT '',
        headerPhone TEXT NOT NULL DEFAULT '',
        headerExtra TEXT NOT NULL DEFAULT '',
        footerMessage TEXT NOT NULL DEFAULT '¡Gracias por su preferencia!',
        warrantyPolicy TEXT NOT NULL DEFAULT '',
        leftMargin INTEGER NOT NULL DEFAULT 0,
        rightMargin INTEGER NOT NULL DEFAULT 0,
        autoCut INTEGER NOT NULL DEFAULT 1,
        itbisRate REAL NOT NULL DEFAULT 0.18,
        fontFamily TEXT NOT NULL DEFAULT 'arial',
        fontSize TEXT NOT NULL DEFAULT 'normal',
        showLogo INTEGER NOT NULL DEFAULT 1,
        logoSize INTEGER NOT NULL DEFAULT 70,
        showBusinessData INTEGER NOT NULL DEFAULT 1,
        showSubtotalItbisTotal INTEGER NOT NULL DEFAULT 1,
        autoHeight INTEGER NOT NULL DEFAULT 1,
        topMargin INTEGER NOT NULL DEFAULT 8,
        bottomMargin INTEGER NOT NULL DEFAULT 8,
        fontSizeLevel INTEGER NOT NULL DEFAULT 6,
        lineSpacingLevel INTEGER NOT NULL DEFAULT 6,
        sectionSpacingLevel INTEGER NOT NULL DEFAULT 6,
        sectionSeparatorStyle TEXT NOT NULL DEFAULT 'single',
        headerAlignment TEXT NOT NULL DEFAULT 'left',
        detailsAlignment TEXT NOT NULL DEFAULT 'left',
        totalsAlignment TEXT NOT NULL DEFAULT 'right',
        createdAtMs INTEGER NOT NULL DEFAULT 0,
        updatedAtMs INTEGER NOT NULL DEFAULT 0
      )
    ''');

    final existingColumns = await db.rawQuery('PRAGMA table_info($_table)');
    final names = existingColumns
        .map((row) => (row['name'] ?? '').toString())
        .toSet();
    for (final column in _columnDefinitions.entries) {
      if (names.contains(column.key)) continue;
      await db.execute('ALTER TABLE $_table ADD COLUMN ${column.value}');
    }
  }

  static const Map<String, String> _columnDefinitions = {
    'selectedPrinterName': 'selectedPrinterName TEXT',
    'paperWidthMm': 'paperWidthMm INTEGER NOT NULL DEFAULT 80',
    'charsPerLine': 'charsPerLine INTEGER NOT NULL DEFAULT 48',
    'autoPrintOnPayment': 'autoPrintOnPayment INTEGER NOT NULL DEFAULT 1',
    'autoOpenDrawerOnChargeWithoutTicket':
        'autoOpenDrawerOnChargeWithoutTicket INTEGER NOT NULL DEFAULT 0',
    'copies': 'copies INTEGER NOT NULL DEFAULT 1',
    'showItbis': 'showItbis INTEGER NOT NULL DEFAULT 1',
    'showElectronicInvoiceReference':
        'showElectronicInvoiceReference INTEGER NOT NULL DEFAULT 1',
    'showCashier': 'showCashier INTEGER NOT NULL DEFAULT 1',
    'showClient': 'showClient INTEGER NOT NULL DEFAULT 1',
    'showPaymentMethod': 'showPaymentMethod INTEGER NOT NULL DEFAULT 1',
    'showDiscounts': 'showDiscounts INTEGER NOT NULL DEFAULT 1',
    'showCode': 'showCode INTEGER NOT NULL DEFAULT 1',
    'showDatetime': 'showDatetime INTEGER NOT NULL DEFAULT 1',
    'headerBusinessName': "headerBusinessName TEXT NOT NULL DEFAULT 'FULLPOS'",
    'headerRnc': "headerRnc TEXT NOT NULL DEFAULT ''",
    'headerAddress': "headerAddress TEXT NOT NULL DEFAULT ''",
    'headerPhone': "headerPhone TEXT NOT NULL DEFAULT ''",
    'headerExtra': "headerExtra TEXT NOT NULL DEFAULT ''",
    'footerMessage':
        "footerMessage TEXT NOT NULL DEFAULT '¡Gracias por su preferencia!'",
    'warrantyPolicy': "warrantyPolicy TEXT NOT NULL DEFAULT ''",
    'leftMargin': 'leftMargin INTEGER NOT NULL DEFAULT 0',
    'rightMargin': 'rightMargin INTEGER NOT NULL DEFAULT 0',
    'autoCut': 'autoCut INTEGER NOT NULL DEFAULT 1',
    'itbisRate': 'itbisRate REAL NOT NULL DEFAULT 0.18',
    'fontFamily': "fontFamily TEXT NOT NULL DEFAULT 'arial'",
    'fontSize': "fontSize TEXT NOT NULL DEFAULT 'normal'",
    'showLogo': 'showLogo INTEGER NOT NULL DEFAULT 1',
    'logoSize': 'logoSize INTEGER NOT NULL DEFAULT 70',
    'showBusinessData': 'showBusinessData INTEGER NOT NULL DEFAULT 1',
    'showSubtotalItbisTotal':
        'showSubtotalItbisTotal INTEGER NOT NULL DEFAULT 1',
    'autoHeight': 'autoHeight INTEGER NOT NULL DEFAULT 1',
    'topMargin': 'topMargin INTEGER NOT NULL DEFAULT 8',
    'bottomMargin': 'bottomMargin INTEGER NOT NULL DEFAULT 8',
    'fontSizeLevel': 'fontSizeLevel INTEGER NOT NULL DEFAULT 6',
    'lineSpacingLevel': 'lineSpacingLevel INTEGER NOT NULL DEFAULT 6',
    'sectionSpacingLevel': 'sectionSpacingLevel INTEGER NOT NULL DEFAULT 6',
    'sectionSeparatorStyle':
        "sectionSeparatorStyle TEXT NOT NULL DEFAULT 'single'",
    'headerAlignment': "headerAlignment TEXT NOT NULL DEFAULT 'left'",
    'detailsAlignment': "detailsAlignment TEXT NOT NULL DEFAULT 'left'",
    'totalsAlignment': "totalsAlignment TEXT NOT NULL DEFAULT 'right'",
    'createdAtMs': 'createdAtMs INTEGER NOT NULL DEFAULT 0',
    'updatedAtMs': 'updatedAtMs INTEGER NOT NULL DEFAULT 0',
  };

  Future<PrinterSettingsModel?> getSettings() async {
    final db = await _database();
    final rows = await db.query(_table, limit: 1);
    if (rows.isNotEmpty) {
      return PrinterSettingsModel.fromMap(rows.first);
    }

    final legacy = await _readLegacySettings();
    if (legacy != null) {
      await updateSettings(legacy);
      return legacy;
    }
    return null;
  }

  Future<PrinterSettingsModel?> _readLegacySettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey);
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
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaults = PrinterSettingsModel(
      id: 1,
      createdAtMs: now,
      updatedAtMs: now,
    );
    await updateSettings(defaults);
    return defaults;
  }

  Future<void> updateSettings(PrinterSettingsModel settings) async {
    final db = await _database();
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalized = settings.copyWith(
      id: settings.id ?? 1,
      createdAtMs: settings.createdAtMs == 0 ? now : settings.createdAtMs,
      updatedAtMs: now,
      charsPerLine: settings.paperWidthMm == 58 ? 32 : 48,
    );
    await db.insert(
      _table,
      _toDbMap(normalized),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PrinterSettingsModel> resetToDefaults() async {
    final current = await getSettings();
    final now = DateTime.now().millisecondsSinceEpoch;
    final reset = PrinterSettingsModel(
      id: current?.id ?? 1,
      selectedPrinterName: current?.selectedPrinterName,
      createdAtMs: current?.createdAtMs == 0 || current?.createdAtMs == null
          ? now
          : current!.createdAtMs,
      updatedAtMs: now,
    );
    await updateSettings(reset);
    return reset;
  }

  Future<PrinterSettingsModel> resetToProfessional() async {
    final current = await getSettings();
    final now = DateTime.now().millisecondsSinceEpoch;
    final reset = PrinterSettingsModel(
      id: current?.id ?? 1,
      selectedPrinterName: current?.selectedPrinterName,
      paperWidthMm: 80,
      charsPerLine: 48,
      autoPrintOnPayment: true,
      fontFamily: 'arial',
      fontSize: 'normal',
      fontSizeLevel: 6,
      lineSpacingLevel: 5,
      sectionSpacingLevel: 6,
      sectionSeparatorStyle: 'single',
      headerBusinessName: current?.headerBusinessName ?? 'FULLPOS',
      headerRnc: current?.headerRnc ?? '',
      headerAddress: current?.headerAddress ?? '',
      headerPhone: current?.headerPhone ?? '',
      headerExtra: current?.headerExtra ?? '',
      footerMessage: current?.footerMessage ?? '¡Gracias por su preferencia!',
      warrantyPolicy: current?.warrantyPolicy ?? '',
      showBusinessData: true,
      showSubtotalItbisTotal: true,
      createdAtMs: current?.createdAtMs == 0 || current?.createdAtMs == null
          ? now
          : current!.createdAtMs,
      updatedAtMs: now,
    );
    await updateSettings(reset);
    return reset;
  }

  Map<String, Object?> _toDbMap(PrinterSettingsModel settings) {
    final map = settings.toMap();
    return map.map((key, value) {
      if (value is bool) return MapEntry(key, value ? 1 : 0);
      return MapEntry(key, value);
    });
  }
}
