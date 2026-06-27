// Convert old database (E:\app_database.db) to new database format (ELATTAR_STORE.db)
// Uses batch inserts for fast performance on 8000+ records

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final oldDbPath = r'E:\app_database.db';
  final outputDir = Directory.current.path;
  final newDbPath = p.join(outputDir, 'ELATTAR_STORE.db');

  print('Old DB: $oldDbPath');
  print('Output: $newDbPath');

  Database oldDb;
  try {
    oldDb = await databaseFactory.openDatabase(oldDbPath);
  } catch (e) {
    print('Error opening old database: $e');
    return;
  }

  if (File(newDbPath).existsSync()) {
    File(newDbPath).deleteSync();
    print('Deleted existing output database');
  }

  print('Creating new database...');
  Database newDb;
  try {
    newDb = await databaseFactory.openDatabase(newDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await _createNewSchema(db);
          },
        ));
  } catch (e) {
    print('Error creating new database: $e');
    await oldDb.close();
    return;
  }

  print('\n========== STARTING CONVERSION ==========\n');

  await _convertTechnicians(oldDb, newDb);
  await _convertCustomersToTickets(oldDb, newDb);
  await _convertSuppliers(oldDb, newDb);
  await _convertParts(oldDb, newDb);
  await _convertAccessories(oldDb, newDb);
  await _convertDevices(oldDb, newDb);
  await _convertSales(oldDb, newDb);
  await _insertDefaults(newDb);

  // Get file size before closing
  final fileSize = File(newDbPath).lengthSync();

  await newDb.close();
  await oldDb.close();

  print('\n========== CONVERSION COMPLETE ==========');
  print('Output: $newDbPath');
  print('Size: ${(fileSize / 1024).toStringAsFixed(0)} KB');
  print('\nTo use this database, copy it to:');
  print(r'  %LOCALAPPDATA%\Microsoft\Windows\Shell\ELATTAR_STORE.db');
}

Future<void> _createNewSchema(Database db) async {
  await db.execute(
      'CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE NOT NULL, passwordHash TEXT NOT NULL, role TEXT NOT NULL)');
  await db.execute(
      'CREATE TABLE IF NOT EXISTS modification_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, actionDate TEXT NOT NULL, actionType TEXT NOT NULL, itemType TEXT NOT NULL, itemName TEXT NOT NULL, details TEXT)');
  await db.execute(
      'CREATE TABLE tickets (id INTEGER PRIMARY KEY, customerName TEXT NOT NULL, customerPhone TEXT NOT NULL, deviceModel TEXT NOT NULL, problem TEXT NOT NULL, status TEXT NOT NULL, receivedDate TEXT NOT NULL, deliveryDate TEXT, cost REAL NOT NULL, notes TEXT NOT NULL, technicianName TEXT, technicianPhone TEXT, complaintNumber TEXT, deviceCondition TEXT NOT NULL DEFAULT \'\', paymentMethod TEXT, paymentDetails TEXT, partsCost REAL DEFAULT 0.0, partsUsed TEXT, commissionRate REAL DEFAULT 50.0, isClosed INTEGER DEFAULT 0, expectedDelivery TEXT, agent TEXT)');
  await db.execute(
      'CREATE TABLE spare_parts (id INTEGER PRIMARY KEY, name TEXT NOT NULL, quantity INTEGER NOT NULL, price REAL NOT NULL, cost REAL NOT NULL DEFAULT 0.0, supplier TEXT, category_id INTEGER)');
  await db.execute(
      'CREATE TABLE technicians (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT NOT NULL, email TEXT)');
  await db.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  await db.execute(
      'CREATE TABLE accessories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, quantity INTEGER NOT NULL, price REAL NOT NULL, cost REAL NOT NULL DEFAULT 0.0, supplier TEXT, warehouse TEXT NOT NULL DEFAULT \'\u0627\u0644\u0645\u062d\u0644 \u0627\u0644\u0631\u0626\u064a\u0633\u064a\', code TEXT, category_id INTEGER)');
  await db.execute(
      'CREATE TABLE devices (id INTEGER PRIMARY KEY AUTOINCREMENT, model TEXT NOT NULL, imei TEXT NOT NULL, condition TEXT NOT NULL DEFAULT \'new\', quantity INTEGER NOT NULL, price REAL NOT NULL, cost REAL NOT NULL DEFAULT 0.0, supplier TEXT, warehouse TEXT NOT NULL DEFAULT \'\u0627\u0644\u0645\u062d\u0644 \u0627\u0644\u0631\u0626\u064a\u0633\u064a\', code TEXT, category_id INTEGER)');
  await db.execute(
      'CREATE TABLE deferred_payments (id INTEGER PRIMARY KEY AUTOINCREMENT, customerName TEXT NOT NULL, customerPhone TEXT NOT NULL, totalAmount REAL NOT NULL, paidAmount REAL NOT NULL DEFAULT 0.0, remainingAmount REAL NOT NULL, dueDate TEXT, notes TEXT, transactionType TEXT, createdDate TEXT NOT NULL)');
  await db.execute(
      'CREATE TABLE deferred_payments_history (id INTEGER PRIMARY KEY AUTOINCREMENT, deferredId INTEGER NOT NULL, amountPaid REAL NOT NULL, paymentDate TEXT NOT NULL, notes TEXT)');
  await db.execute(
      'CREATE TABLE suppliers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, phone TEXT, address TEXT)');
  await db.execute(
      'CREATE TABLE supplier_debts (id INTEGER PRIMARY KEY AUTOINCREMENT, supplierId INTEGER NOT NULL, supplierName TEXT NOT NULL, totalAmount REAL NOT NULL, paidAmount REAL NOT NULL DEFAULT 0.0, remainingAmount REAL NOT NULL, dueDate TEXT, notes TEXT, createdDate TEXT NOT NULL)');
  await db.execute(
      'CREATE TABLE supplier_payments_history (id INTEGER PRIMARY KEY AUTOINCREMENT, debtId INTEGER NOT NULL, amountPaid REAL NOT NULL, paymentDate TEXT NOT NULL, notes TEXT)');
  await db.execute(
      'CREATE TABLE goods_receipts (id INTEGER PRIMARY KEY AUTOINCREMENT, receiptDate TEXT NOT NULL, itemType TEXT NOT NULL, itemName TEXT NOT NULL, quantity INTEGER NOT NULL, cost REAL NOT NULL, price REAL NOT NULL, supplier TEXT, warehouse TEXT NOT NULL DEFAULT \'\u0627\u0644\u0645\u062d\u0644 \u0627\u0644\u0631\u0626\u064a\u0633\u064a\')');
  await db.execute(
      'CREATE TABLE inventory_transfers (id INTEGER PRIMARY KEY AUTOINCREMENT, transferDate TEXT NOT NULL, itemType TEXT NOT NULL, itemName TEXT NOT NULL, quantity INTEGER NOT NULL, fromWarehouse TEXT NOT NULL, toWarehouse TEXT NOT NULL, notes TEXT)');
  await db.execute(
      'CREATE TABLE inventory_audits (id INTEGER PRIMARY KEY AUTOINCREMENT, auditDate TEXT NOT NULL, itemType TEXT NOT NULL, itemName TEXT NOT NULL, expectedQty INTEGER NOT NULL, actualQty INTEGER NOT NULL, difference INTEGER NOT NULL, auditor TEXT, notes TEXT)');
  await db.execute(
      'CREATE TABLE warehouses (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE)');
  await db.execute(
      'CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, saleDate TEXT NOT NULL, customerName TEXT, customerPhone TEXT, totalAmount REAL NOT NULL, discount REAL NOT NULL DEFAULT 0.0, finalAmount REAL NOT NULL, paymentMethod TEXT NOT NULL, itemsJson TEXT NOT NULL)');
  await db.execute(
      'CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, type TEXT NOT NULL)');
  await db.execute(
      'CREATE TABLE IF NOT EXISTS returns (id INTEGER PRIMARY KEY AUTOINCREMENT, returnDate TEXT NOT NULL, customerName TEXT, customerPhone TEXT, totalAmount REAL NOT NULL, paymentMethod TEXT NOT NULL, itemsJson TEXT NOT NULL, notes TEXT)');
}

Future<void> _insertBatch(
    Database db, String table, List<Map<String, dynamic>> rows,
    {int chunkSize = 500}) async {
  final total = rows.length;
  for (int i = 0; i < total; i += chunkSize) {
    final end = (i + chunkSize > total) ? total : i + chunkSize;
    final batch = db.batch();
    for (int j = i; j < end; j++) {
      batch.insert(table, rows[j], conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    if (i > 0) {
      final pct = end * 100 ~/ total;
      if (pct % 10 == 0) print('    ... $pct% ($end/$total)');
    }
  }
}

String _mapStatus(String? oldStatus) {
  if (oldStatus == null || oldStatus.trim().isEmpty) return 'pending';
  final s = oldStatus.trim();
  if (s == 'تم التسليم') return 'delivered';
  if (s == 'مستلم') return 'delivered';
  if (s == 'قيد الإصلاح') return 'in_progress';
  if (s == 'تم الإصلاح') return 'repaired';
  return 'pending';
}

String _tsToIso(int? timestamp) {
  if (timestamp == null || timestamp == 0)
    return DateTime.now().toIso8601String();
  return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
      .toIso8601String();
}

Future<void> _convertTechnicians(Database oldDb, Database newDb) async {
  print('\n--- Converting technicians ---');
  final rows = await oldDb.rawQuery('SELECT * FROM technicians');
  final mapped = <Map<String, dynamic>>[];
  for (var row in rows) {
    final name = (row['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    mapped
        .add({'name': name, 'phone': (row['phone'] as String?)?.trim() ?? ''});
  }
  await _insertBatch(newDb, 'technicians', mapped);
  print('  Converted ${mapped.length} technicians');
}

Future<void> _convertCustomersToTickets(Database oldDb, Database newDb) async {
  print('\n--- Converting customers to tickets ---');
  final rows = await oldDb.rawQuery('SELECT * FROM customers ORDER BY id');
  print('  Found ${rows.length} records');

  final tickets = <Map<String, dynamic>>[];
  for (var row in rows) {
    final ticketId = row['id'] as int;
    if (ticketId <= 0) continue;

    final name = (row['name'] as String?)?.trim() ?? '';
    final deviceModel = (row['phone'] as String?)?.trim() ?? '';
    final customerPhone = (row['number'] as String?)?.trim() ?? '';
    final problem = (row['repair'] as String?)?.trim() ?? '';
    final notes = (row['notes'] as String?)?.trim() ?? '';
    final deviceCondition = (row['device_condition'] as String?)?.trim() ?? '';
    final technicianName = (row['technician_name'] as String?)?.trim();
    final technicianPhone = (row['technician_phone'] as String?)?.trim();
    final receiverName = (row['receiver_name'] as String?)?.trim();
    final status = _mapStatus(row['status'] as String?);
    final price = (row['price'] as num?)?.toDouble() ?? 0.0;
    final initialCost = (row['initial_cost'] as num?)?.toDouble();
    final paid = (row['paid'] as num?)?.toDouble() ?? 0.0;
    final remaining = (row['remaining'] as num?)?.toDouble() ?? 0.0;
    final addedAt = row['added_at'] as int?;
    final expectedDeliveryDate = row['expected_delivery_date'] as int?;
    final deliveryType = (row['delivery_type'] as String?)?.trim();
    final isPurchased = row['is_purchased'] as int? ?? 0;
    final phoneCondition = (row['phone_condition'] as String?)?.trim();
    final deliveryTimeValue = (row['delivery_time_value'] as String?)?.trim();
    final deliveryTimeUnit = (row['delivery_time_unit'] as String?)?.trim();

    final extraNotes = <String>[];
    if (notes.isNotEmpty) extraNotes.add(notes);
    if (isPurchased == 1) extraNotes.add('مشتري');
    if (phoneCondition != null && phoneCondition.isNotEmpty)
      extraNotes.add('حالة الجهاز: $phoneCondition');
    if (deliveryTimeValue != null && deliveryTimeValue.isNotEmpty)
      extraNotes.add('وقت التسليم: $deliveryTimeValue $deliveryTimeUnit');
    if (paid > 0 || remaining > 0)
      extraNotes.add('مدفوع: $paid - متبقي: $remaining');
    if (initialCost != null && initialCost > 0)
      extraNotes.add('التكلفة الأولية: $initialCost');
    final combinedNotes = extraNotes.join(' | ');

    final isClosed = (status == 'delivered' || remaining <= 0) ? 1 : 0;

    tickets.add({
      'id': ticketId,
      'customerName': name.isEmpty ? 'غير محدد' : name,
      'customerPhone': customerPhone,
      'deviceModel': deviceModel,
      'problem': problem.isEmpty ? 'غير محدد' : problem,
      'status': status,
      'receivedDate': _tsToIso(addedAt),
      'deliveryDate': status == 'delivered' ? _tsToIso(addedAt) : null,
      'cost': price,
      'notes': combinedNotes.isNotEmpty ? combinedNotes : ' ',
      'technicianName': technicianName,
      'technicianPhone': technicianPhone,
      'deviceCondition': deviceCondition,
      'paymentMethod': deliveryType ?? 'فوري',
      'paymentDetails': paid > 0 ? 'مدفوع: $paid' : null,
      'partsCost': initialCost ?? 0.0,
      'commissionRate': 50.0,
      'isClosed': isClosed,
      'expectedDelivery':
          expectedDeliveryDate != null ? _tsToIso(expectedDeliveryDate) : null,
      'agent': receiverName,
    });
  }

  print('  Prepared ${tickets.length} records, inserting...');
  await _insertBatch(newDb, 'tickets', tickets);
  print('  Done - ${tickets.length} tickets');
}

Future<void> _convertSuppliers(Database oldDb, Database newDb) async {
  print('\n--- Converting suppliers ---');
  final rows = await oldDb.rawQuery('SELECT * FROM suppliers');
  final mapped = <Map<String, dynamic>>[];
  for (var row in rows) {
    final name = (row['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    mapped.add({
      'name': name,
      'phone': (row['contact_info'] as String?)?.trim(),
      'address': (row['address'] as String?)?.trim(),
    });
  }
  await _insertBatch(newDb, 'suppliers', mapped);
  print('  Converted ${mapped.length} suppliers');
}

Future<void> _convertParts(Database oldDb, Database newDb) async {
  print('\n--- Converting parts to spare_parts ---');
  final seen = <String>{};
  final mapped = <Map<String, dynamic>>[];

  void addPart(String name, double price) {
    if (name.isEmpty || seen.contains(name)) return;
    seen.add(name);
    mapped.add(
        {'name': name, 'quantity': 1, 'price': price, 'cost': price * 0.7});
  }

  for (var row in await oldDb.rawQuery('SELECT * FROM parts')) {
    addPart((row['part_name'] as String?)?.trim() ?? '',
        (row['price'] as num?)?.toDouble() ?? 0.0);
  }
  for (var inv in await oldDb.rawQuery('SELECT * FROM spare_parts_invoices')) {
    final invId = inv['id'] as int;
    for (var item in await oldDb.rawQuery(
        'SELECT * FROM spare_parts_items WHERE invoice_id = $invId')) {
      addPart((item['name'] as String?)?.trim() ?? '',
          (item['price'] as num?)?.toDouble() ?? 0.0);
    }
  }

  if (mapped.isNotEmpty) await _insertBatch(newDb, 'spare_parts', mapped);
  print('  Converted ${mapped.length} spare parts');
}

Future<void> _convertAccessories(Database oldDb, Database newDb) async {
  print('\n--- Converting accessories ---');
  final rows = await oldDb.rawQuery('SELECT * FROM accessories');
  final mapped = <Map<String, dynamic>>[];
  for (var row in rows) {
    final name = (row['item_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    mapped.add({
      'name': name,
      'quantity': (row['stock_qty'] as int?) ?? 0,
      'price': (row['sale_price'] as num?)?.toDouble() ?? 0.0,
      'cost': (row['cost_price'] as num?)?.toDouble() ?? 0.0,
    });
  }
  if (mapped.isNotEmpty) await _insertBatch(newDb, 'accessories', mapped);
  print('  Converted ${mapped.length} accessories');
}

Future<void> _convertDevices(Database oldDb, Database newDb) async {
  print('\n--- Converting devices ---');
  final rows = await oldDb.rawQuery('SELECT * FROM devices');
  final mapped = <Map<String, dynamic>>[];
  for (var row in rows) {
    final name = (row['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) continue;
    final brand = (row['brand'] as String?)?.trim() ?? '';
    final model = (row['model'] as String?)?.trim() ?? '';
    final storage = (row['storage'] as String?)?.trim() ?? '';
    final fullModel =
        [brand, model, storage].where((s) => s.isNotEmpty).join(' ');
    mapped.add({
      'model': fullModel.isNotEmpty ? fullModel : name,
      'imei': (row['imei1'] as String?)?.trim() ?? '',
      'condition': (row['condition'] as String?)?.trim() ?? 'used',
      'quantity': 1,
      'price': (row['selling_price'] as num?)?.toDouble() ?? 0.0,
      'cost': (row['purchase_price'] as num?)?.toDouble() ?? 0.0,
      'supplier': (row['seller_name'] as String?)?.trim(),
      'code': '$brand $model',
    });
  }
  if (mapped.isNotEmpty) await _insertBatch(newDb, 'devices', mapped);
  print('  Converted ${mapped.length} devices');
}

Future<void> _convertSales(Database oldDb, Database newDb) async {
  print('\n--- Converting sales ---');
  final rows = await oldDb.rawQuery('SELECT * FROM sales');
  final mapped = <Map<String, dynamic>>[];
  for (var row in rows) {
    final price = (row['price'] as num?)?.toDouble() ?? 0.0;
    final date = row['date'] as int?;
    final customerId = row['customer_id'] as int?;
    String? customerName;
    String? customerPhone;
    if (customerId != null) {
      final cust = await oldDb.rawQuery(
          'SELECT name, number FROM customers WHERE id = $customerId LIMIT 1');
      if (cust.isNotEmpty) {
        customerName = cust.first['name'] as String?;
        customerPhone = cust.first['number'] as String?;
      }
    }
    mapped.add({
      'saleDate': _tsToIso(date),
      'customerName': customerName,
      'customerPhone': customerPhone,
      'totalAmount': price,
      'discount': 0.0,
      'finalAmount': price,
      'paymentMethod': 'cash',
      'itemsJson': '[]',
    });
  }
  if (mapped.isNotEmpty) await _insertBatch(newDb, 'sales', mapped);
  print('  Converted ${mapped.length} sales');
}

Future<void> _insertDefaults(Database db) async {
  print('\n--- Inserting defaults ---');
  try {
    await db.insert('warehouses', {'name': 'المحل الرئيسي'});
  } catch (_) {}
  try {
    await db.insert('warehouses', {'name': 'المخزن'});
  } catch (_) {}
  print('  Warehouses done');
  const cats = [
    {'name': 'جرابات', 'type': 'accessory'},
    {'name': 'سماعات', 'type': 'accessory'},
    {'name': 'ساعات عادية', 'type': 'accessory'},
    {'name': 'ساعات وايرليس', 'type': 'accessory'},
    {'name': 'بطارية', 'type': 'spare_part'},
    {'name': 'شاشة', 'type': 'spare_part'},
    {'name': 'سوكتات', 'type': 'spare_part'},
    {'name': 'بوردة', 'type': 'spare_part'},
    {'name': 'آيفون', 'type': 'device_brand'},
    {'name': 'سامسونج', 'type': 'device_brand'},
    {'name': 'شاومي', 'type': 'device_brand'},
    {'name': 'أوبو', 'type': 'device_brand'},
    {'name': 'ريلمي', 'type': 'device_brand'},
    {'name': 'جديد', 'type': 'device_condition'},
    {'name': 'مستعمل', 'type': 'device_condition'},
    {'name': 'خارج صيانة', 'type': 'device_condition'},
  ];
  for (var c in cats) {
    try {
      await db.insert('categories', c,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } catch (_) {}
  }
  print('  Categories done');
  try {
    await db.insert(
        'users',
        {
          'email': 'admin@elattar.com',
          'passwordHash':
              '5994471abb01112afcc18159f6cc74b4f511b99806da59b3caf5a9c173cacfc5',
          'role': 'admin'
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    print('  Admin user done');
  } catch (_) {}
  try {
    await db.insert('modification_logs', {
      'actionDate': DateTime.now().toIso8601String(),
      'actionType': 'تحويل',
      'itemType': 'قاعدة بيانات',
      'itemName': 'ELATTAR_STORE',
      'details': 'تم تحويل قاعدة البيانات من النظام القديم إلى النظام الجديد'
    });
    print('  Log done');
  } catch (_) {}
}
