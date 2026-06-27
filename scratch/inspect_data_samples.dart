import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = 'c:/Users/BELAL/Videos/ELATTAR2.5/lib/app_database.db';
  final file = File(dbPath);
  try {
    final db = await databaseFactory.openDatabase(file.path);
    
    print('=== Sample from customers ===');
    final List<Map<String, dynamic>> customers = await db.rawQuery('SELECT * FROM customers LIMIT 5');
    for (var r in customers) {
      print(r);
    }

    print('\n=== Sample from sales ===');
    final List<Map<String, dynamic>> sales = await db.rawQuery('SELECT * FROM sales LIMIT 5');
    for (var r in sales) {
      print(r);
    }

    print('\n=== Sample from technicians ===');
    final List<Map<String, dynamic>> technicians = await db.rawQuery('SELECT * FROM technicians LIMIT 5');
    for (var r in technicians) {
      print(r);
    }

    await db.close();
  } catch (e) {
    print('Error: $e');
  }
}
