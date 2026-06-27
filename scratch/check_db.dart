import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  
  final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
  final dbPath = '$localAppData\\Microsoft\\Windows\\Shell\\ELATTAR_STORE.db';
  print('Opening database at: $dbPath');
  
  if (!File(dbPath).existsSync()) {
    print('Error: Database file does not exist!');
    return;
  }
  
  final db = await databaseFactory.openDatabase(dbPath);
  
  print('\n--- ATTENDANCE TABLE (LAST 5 ROWS) ---');
  try {
    final attResult = await db.rawQuery('SELECT * FROM attendance ORDER BY id DESC LIMIT 5');
    if (attResult.isEmpty) {
      print('No records found.');
    }
    for (var row in attResult) {
      print(row);
    }
  } catch (e) {
    print('Error querying attendance: $e');
  }
  
  print('\n--- MODIFICATION LOGS (LAST 5 ROWS) ---');
  try {
    final logsResult = await db.rawQuery('SELECT * FROM modification_logs ORDER BY id DESC LIMIT 5');
    if (logsResult.isEmpty) {
      print('No records found.');
    }
    for (var row in logsResult) {
      print(row);
    }
  } catch (e) {
    print('Error querying modification_logs: $e');
  }
  
  await db.close();
}
