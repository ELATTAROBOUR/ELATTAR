import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  print('=== Checking root subscribers.db ===');
  await checkDb('c:/Users/BELAL/Videos/ELATTAR2.4/subscribers.db');

  print('\n=== Checking keygen/subscribers.db ===');
  await checkDb('c:/Users/BELAL/Videos/ELATTAR2.4/keygen/subscribers.db');
}

Future<void> checkDb(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    print('File does not exist: $path');
    return;
  }
  try {
    final db = await databaseFactory.openDatabase(file.path);
    final List<Map<String, dynamic>> results = await db.query('subscribers');
    if (results.isEmpty) {
      print('Database is empty.');
    } else {
      for (var row in results) {
        print('Row: $row');
      }
    }
    await db.close();
  } catch (e) {
    print('Error reading database $path: $e');
  }
}
