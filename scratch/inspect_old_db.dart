import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = r'E:\app_database.db';
  print('Opening: $dbPath');

  Database db;
  try {
    db = await databaseFactory.openDatabase(dbPath);
  } catch (e) {
    print('Error opening database: $e');
    return;
  }

  // Get list of tables
  final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
  print('\n=== TABLES ===');
  for (var t in tables) {
    print('  ${t['name']}');
  }

  // Get schema for each table
  print('\n=== SCHEMA ===');
  for (var t in tables) {
    final name = t['name'] as String;
    final schema =
        await db.rawQuery("SELECT sql FROM sqlite_master WHERE name='$name'");
    if (schema.isNotEmpty) {
      print('\n--- $name ---');
      print(schema.first['sql']);
    }
  }

  // Get row counts
  print('\n=== ROW COUNTS ===');
  for (var t in tables) {
    final name = t['name'] as String;
    final count = await db.rawQuery('SELECT COUNT(*) as cnt FROM "$name"');
    print('  $name: ${count.first['cnt']} rows');
  }

  // Sample data from each table
  print('\n=== SAMPLE DATA (first 3 rows) ===');
  for (var t in tables) {
    final name = t['name'] as String;
    final rows = await db.rawQuery('SELECT * FROM "$name" LIMIT 3');
    if (rows.isNotEmpty) {
      print('\n--- $name (sample) ---');
      for (var r in rows) {
        print('  $r');
      }
    }
  }

  // Also check sequel_master for any views or indices
  print('\n=== INDICES ===');
  final indices = await db.rawQuery(
      "SELECT name, sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name");
  for (var idx in indices) {
    print('  ${idx['name']}: ${idx['sql']}');
  }

  print('\n=== VERSION INFO ===');
  final ver = await db.rawQuery('PRAGMA user_version');
  print('  user_version: ${ver.first['user_version']}');

  await db.close();
}
