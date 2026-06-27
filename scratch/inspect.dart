import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;
  
  final dbPath = 'C:\\Users\\BELAL\\AppData\\Local\\Microsoft\\Windows\\Shell\\ELATTAR_STORE.db';
  if (!File(dbPath).existsSync()) {
    print('Database file not found at: $dbPath');
    return;
  }
  
  print('Opening database at: $dbPath');
  final db = await databaseFactory.openDatabase(dbPath);
  
  try {
    print('\n=== USERS ===');
    final users = await db.query('users');
    for (var u in users) {
      print(u);
    }
    
    print('\n=== TECHNICIANS ===');
    final techs = await db.query('technicians');
    for (var t in techs) {
      print(t);
    }
    
    print('\n=== ATTENDANCE ===');
    final attendance = await db.query('attendance');
    for (var a in attendance) {
      print(a);
    }
    
    print('\n=== MODIFICATION LOGS (Last 5) ===');
    final logs = await db.query('modification_logs', orderBy: 'id DESC', limit: 5);
    for (var l in logs) {
      print(l);
    }
  } catch (e) {
    print('Error querying database: $e');
  } finally {
    await db.close();
  }
}
