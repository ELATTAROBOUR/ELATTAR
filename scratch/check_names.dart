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
  
  print('\n=== USERS TABLE ===');
  try {
    final users = await db.query('users');
    for (var u in users) {
      print(u);
    }
  } catch (e) {
    print('Error: $e');
  }
  
  print('\n=== TECHNICIANS TABLE ===');
  try {
    final techs = await db.query('technicians');
    for (var t in techs) {
      print(t);
    }
  } catch (e) {
    print('Error: $e');
  }
  
  await db.close();
}
