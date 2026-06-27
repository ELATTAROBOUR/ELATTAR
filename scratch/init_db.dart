import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final file = File('subscribers.db');
  if (await file.exists()) {
    print('subscribers.db already exists.');
  }

  print('Opening and initializing subscribers.db...');
  final db = await databaseFactory.openDatabase(file.path);
  
  await db.execute('''
    CREATE TABLE IF NOT EXISTS subscribers (
      hwid TEXT PRIMARY KEY,
      clientName TEXT,
      registeredEmail TEXT,
      status TEXT,
      expiryDate TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS created_users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subscriber_hwid TEXT,
      email TEXT,
      role TEXT,
      FOREIGN KEY (subscriber_hwid) REFERENCES subscribers (hwid) ON DELETE CASCADE
    )
  ''');

  print('Database initialized successfully.');
  await db.close();
}
