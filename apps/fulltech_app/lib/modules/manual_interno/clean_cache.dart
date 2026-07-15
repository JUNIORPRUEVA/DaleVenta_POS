// Cleanup script para caché local del Manual Interno en Flutter
// Este script simula el borrado de caché local que debería hacer el sistema

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> clearManualInternoCache() async {
  debugPrint('🧹 Limpiando caché del Manual Interno...');

  try {
    // 1. Limpiar SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    int clearedPrefs = 0;

    for (final key in keys) {
      if (key.contains('company_manual') || key.contains('manual_interno')) {
        await prefs.remove(key);
        clearedPrefs++;
      }
    }
    debugPrint('✓ Limpiadas $clearedPrefs preferencias');

    // 2. Limpiar base de datos local SQLite
    final database = await openDatabase('company_manual_local.db', version: 2);

    try {
      await database.transaction((txn) async {
        await txn.delete('company_manual_entries');
        await txn.delete('company_manual_meta');
        debugPrint('✓ Limpiadas tablas SQLite');
      });
    } finally {
      await database.close();
    }

    debugPrint('✅ Caché limpiado correctamente.');
    debugPrint(
      '💡 Tip: El frontend descargará datos frescos en la próxima carga.',
    );
  } catch (e) {
    debugPrint('❌ Error al limpiar caché: $e');
    rethrow;
  }
}
