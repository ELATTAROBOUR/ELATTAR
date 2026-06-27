import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = 'c:/Users/BELAL/Videos/ELATTAR2.5/lib/app_database.db';
  final file = File(dbPath);
  if (!await file.exists()) {
    print('File does not exist: $dbPath');
    return;
  }

  try {
    final db = await databaseFactory.openDatabase(file.path);
    print('=== Tables in app_database.db ===');
    final List<Map<String, dynamic>> tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';"
    );

    for (var table in tables) {
      final tableName = table['name'] as String;
      final countResult = await db.rawQuery('SELECT COUNT(*) FROM "$tableName"');
      final rowCount = countResult.first.values.first as int;
      print('\nTable: $tableName (Rows: $rowCount)');
      
      final List<Map<String, dynamic>> columns = await db.rawQuery('PRAGMA table_info("$tableName")');
      for (var col in columns) {
        print('  - ${col['name']} (${col['type']})');
      }
    }
    await db.close();
  } catch (e) {
    print('Error inspecting database: $e');
  }
}
