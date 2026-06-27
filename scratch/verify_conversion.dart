import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = 'ELATTAR_STORE.db';
  if (!File(dbPath).existsSync()) {
    print('ERROR: Database file not found: $dbPath');
    return;
  }

  Database db;
  try {
    db = await databaseFactory.openDatabase(dbPath);
  } catch (e) {
    print('Error opening database: $e');
    return;
  }

  // Row counts
  final tables = [
    'tickets',
    'technicians',
    'suppliers',
    'spare_parts',
    'accessories',
    'devices',
    'sales',
    'users',
    'warehouses',
    'categories'
  ];
  print('=== ROW COUNTS ===');
  for (var t in tables) {
    final cnt = await db.rawQuery('SELECT COUNT(*) as c FROM $t');
    print('  $t: ${cnt.first['c']}');
  }

  // Sample tickets
  print('\n=== SAMPLE TICKETS (first 3) ===');
  final sampleTickets = await db.rawQuery(
      'SELECT id, customerName, customerPhone, deviceModel, problem, status, cost, technicianName, receivedDate FROM tickets LIMIT 3');
  for (var t in sampleTickets) {
    print('  $t');
  }

  // Sample technicians
  print('\n=== TECHNICIANS ===');
  final techs = await db.rawQuery('SELECT * FROM technicians');
  for (var t in techs) {
    print('  $t');
  }

  // Sample suppliers
  print('\n=== SUPPLIERS ===');
  final sups = await db.rawQuery('SELECT * FROM suppliers');
  for (var s in sups) {
    print('  $s');
  }

  // Sample spare parts
  print('\n=== SPARE PARTS ===');
  final parts = await db.rawQuery('SELECT * FROM spare_parts');
  for (var p in parts) {
    print('  $p');
  }

  // Sample sales
  print('\n=== SALES (first 3) ===');
  final sales = await db.rawQuery(
      'SELECT id, saleDate, customerName, totalAmount, finalAmount FROM sales LIMIT 3');
  for (var s in sales) {
    print('  $s');
  }

  // Status distribution
  print('\n=== TICKET STATUS DISTRIBUTION ===');
  final statuses = await db.rawQuery(
      'SELECT status, COUNT(*) as cnt FROM tickets GROUP BY status ORDER BY cnt DESC');
  for (var s in statuses) {
    print('  ${s['status']}: ${s['cnt']}');
  }

  // Users
  print('\n=== USERS ===');
  final users = await db.rawQuery('SELECT id, email, role FROM users');
  for (var u in users) {
    print('  ${u['id']}: ${u['email']} (${u['role']})');
  }

  await db.close();
}
