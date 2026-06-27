import 'dart:convert';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final sourceDbPath = 'c:/Users/BELAL/Videos/ELATTAR2.5/lib/app_database.db';
  final destDbPath = 'c:/Users/BELAL/Videos/ELATTAR2.5/ELATTAR_STORE.db';

  final sourceFile = File(sourceDbPath);
  if (!await sourceFile.exists()) {
    print('❌ Error: Source database not found at $sourceDbPath');
    return;
  }

  // 1. Delete destination database if it already exists
  final destFile = File(destDbPath);
  if (await destFile.exists()) {
    print('🗑️ Deleting existing destination database...');
    await destFile.delete();
  }

  print('🚀 Initializing destination database with version 11 schema...');
  final destDb = await databaseFactory.openDatabase(
    destDbPath,
    options: OpenDatabaseOptions(
      version: 11,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            passwordHash TEXT NOT NULL,
            role TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS modification_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            actionDate TEXT NOT NULL,
            actionType TEXT NOT NULL,
            itemType TEXT NOT NULL,
            itemName TEXT NOT NULL,
            details TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE tickets (
            id INTEGER PRIMARY KEY,
            customerName TEXT NOT NULL,
            customerPhone TEXT NOT NULL,
            deviceModel TEXT NOT NULL,
            problem TEXT NOT NULL,
            status TEXT NOT NULL,
            receivedDate TEXT NOT NULL,
            deliveryDate TEXT,
            cost REAL NOT NULL,
            notes TEXT NOT NULL,
            technicianName TEXT,
            technicianPhone TEXT,
            complaintNumber TEXT,
            deviceCondition TEXT NOT NULL DEFAULT '',
            paymentMethod TEXT,
            paymentDetails TEXT,
            partsCost REAL DEFAULT 0.0,
            partsUsed TEXT,
            commissionRate REAL DEFAULT 50.0,
            isClosed INTEGER DEFAULT 0,
            expectedDelivery TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE spare_parts (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            price REAL NOT NULL,
            cost REAL NOT NULL DEFAULT 0.0,
            supplier TEXT,
            category_id INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE technicians (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            phone TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE accessories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            price REAL NOT NULL,
            cost REAL NOT NULL DEFAULT 0.0,
            supplier TEXT,
            warehouse TEXT NOT NULL DEFAULT 'المحل الرئيسي',
            code TEXT,
            category_id INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model TEXT NOT NULL,
            imei TEXT NOT NULL,
            condition TEXT NOT NULL DEFAULT 'new',
            quantity INTEGER NOT NULL,
            price REAL NOT NULL,
            cost REAL NOT NULL DEFAULT 0.0,
            supplier TEXT,
            warehouse TEXT NOT NULL DEFAULT 'المحل الرئيسي',
            code TEXT,
            category_id INTEGER
          )
        ''');

        await db.execute('''
          CREATE TABLE deferred_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customerName TEXT NOT NULL,
            customerPhone TEXT NOT NULL,
            totalAmount REAL NOT NULL,
            paidAmount REAL NOT NULL DEFAULT 0.0,
            remainingAmount REAL NOT NULL,
            dueDate TEXT,
            notes TEXT,
            transactionType TEXT,
            createdDate TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE deferred_payments_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deferredId INTEGER NOT NULL,
            amountPaid REAL NOT NULL,
            paymentDate TEXT NOT NULL,
            notes TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE suppliers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            phone TEXT,
            address TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE supplier_debts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            supplierId INTEGER NOT NULL,
            supplierName TEXT NOT NULL,
            totalAmount REAL NOT NULL,
            paidAmount REAL NOT NULL DEFAULT 0.0,
            remainingAmount REAL NOT NULL,
            dueDate TEXT,
            notes TEXT,
            createdDate TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE supplier_payments_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            debtId INTEGER NOT NULL,
            amountPaid REAL NOT NULL,
            paymentDate TEXT NOT NULL,
            notes TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE goods_receipts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            receiptDate TEXT NOT NULL,
            itemType TEXT NOT NULL,
            itemName TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            cost REAL NOT NULL,
            price REAL NOT NULL,
            supplier TEXT,
            warehouse TEXT NOT NULL DEFAULT 'المحل الرئيسي'
          )
        ''');

        await db.execute('''
          CREATE TABLE inventory_transfers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transferDate TEXT NOT NULL,
            itemType TEXT NOT NULL,
            itemName TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            fromWarehouse TEXT NOT NULL,
            toWarehouse TEXT NOT NULL,
            notes TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE inventory_audits (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            auditDate TEXT NOT NULL,
            itemType TEXT NOT NULL,
            itemName TEXT NOT NULL,
            expectedQty INTEGER NOT NULL,
            actualQty INTEGER NOT NULL,
            difference INTEGER NOT NULL,
            auditor TEXT,
            notes TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE warehouses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )
        ''');

        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            saleDate TEXT NOT NULL,
            customerName TEXT,
            customerPhone TEXT,
            totalAmount REAL NOT NULL,
            discount REAL NOT NULL DEFAULT 0.0,
            finalAmount REAL NOT NULL,
            paymentMethod TEXT NOT NULL,
            itemsJson TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS returns (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            returnDate TEXT NOT NULL,
            customerName TEXT,
            customerPhone TEXT,
            totalAmount REAL NOT NULL,
            paymentMethod TEXT NOT NULL,
            itemsJson TEXT NOT NULL,
            notes TEXT
          )
        ''');

        // Insert Defaults
        await db.insert('warehouses', {'name': 'المحل الرئيسي'});
        await db.insert('warehouses', {'name': 'المخزن'});

        final defaultCategories = [
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
        for (var cat in defaultCategories) {
          await db.insert('categories', cat);
        }
      },
    ),
  );

  print('📂 Opening source database...');
  final sourceDb = await databaseFactory.openDatabase(sourceFile.path);

  // Helper to format date
  String formatDate(int? epochSeconds) {
    if (epochSeconds == null || epochSeconds == 0) {
      return DateTime.now().toLocal().toString().split('.')[0];
    }
    return DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000)
        .toLocal()
        .toString()
        .split('.')[0];
  }

  String formatDateOnly(int? epochSeconds) {
    if (epochSeconds == null || epochSeconds == 0) {
      return DateTime.now().toLocal().toString().split(' ')[0];
    }
    return DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000)
        .toLocal()
        .toString()
        .split(' ')[0];
  }

  // 2. Migrate Technicians
  print('👥 Migrating Technicians...');
  final List<Map<String, dynamic>> technicians = await sourceDb.query('technicians');
  int techCount = 0;
  final techBatch = destDb.batch();
  for (var tech in technicians) {
    techBatch.insert('technicians', {
      'id': tech['id'],
      'name': tech['name'] ?? '',
      'phone': tech['phone'] ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    techCount++;
  }
  await techBatch.commit(noResult: true);
  print('   ✅ Migrated $techCount technicians.');

  // 3. Migrate Suppliers
  print('🏬 Migrating Suppliers...');
  final List<Map<String, dynamic>> suppliers = await sourceDb.query('suppliers');
  int suppCount = 0;
  final suppBatch = destDb.batch();
  for (var supp in suppliers) {
    suppBatch.insert('suppliers', {
      'id': supp['iddel'] ?? supp['id'],
      'name': supp['name'] ?? '',
      'phone': supp['contact_info'] ?? '',
      'address': supp['address'] ?? '',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    suppCount++;
  }
  await suppBatch.commit(noResult: true);
  print('   ✅ Migrated $suppCount suppliers.');

  // 4. Migrate Customers (Old) to Tickets (New)
  print('🎫 Migrating Customers to Tickets...');
  final List<Map<String, dynamic>> customers = await sourceDb.query('customers');
  int ticketCount = 0;
  final ticketBatch = destDb.batch();
  for (var cust in customers) {
    final String oldStatus = cust['status'] ?? 'مستلم';
    String status = 'pending';
    if (oldStatus == 'تم التسليم' || oldStatus == 'delivered') {
      status = 'delivered';
    } else if (oldStatus == 'تم الإصلاح' || oldStatus == 'repaired') {
      status = 'repaired';
    } else if (oldStatus == 'قيد الإصلاح' || oldStatus == 'تحت الصيانة' || oldStatus == 'in_progress') {
      status = 'in_progress';
    } else if (oldStatus == 'مرفوض' || oldStatus == 'rejected') {
      status = 'rejected';
    } else if (oldStatus == 'تم الشراء' || oldStatus == 'bought_from_customer') {
      status = 'bought_from_customer';
    }

    final double cost = (cust['price'] as num? ?? 0.0).toDouble();
    final double paid = (cust['paid'] as num? ?? 0.0).toDouble();
    final double remaining = (cust['remaining'] as num? ?? 0.0).toDouble();

    final receivedDateStr = formatDate(cust['added_at'] as int?);
    final deliveryDateStr = cust['expected_delivery_date'] != null 
        ? formatDateOnly(cust['expected_delivery_date'] as int?) 
        : null;

    ticketBatch.insert('tickets', {
      'id': cust['id'],
      'customerName': cust['name'] ?? '',
      'customerPhone': cust['number'] ?? '',
      'deviceModel': cust['phone'] ?? '',
      'problem': cust['repair'] ?? '',
      'status': status,
      'receivedDate': receivedDateStr,
      'deliveryDate': deliveryDateStr,
      'cost': cost,
      'notes': cust['notes'] ?? '',
      'technicianName': cust['technician_name'] ?? '',
      'technicianPhone': cust['technician_phone'] ?? '',
      'complaintNumber': '01000361006',
      'deviceCondition': cust['device_condition'] ?? cust['phone_condition'] ?? '',
      'paymentMethod': 'نقدي',
      'paymentDetails': 'مدفوع: $paid, متبقي: $remaining',
      'partsCost': 0.0,
      'partsUsed': '[]',
      'commissionRate': 50.0,
      'isClosed': (status == 'delivered') ? 1 : 0,
      'expectedDelivery': deliveryDateStr,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    ticketCount++;
  }
  await ticketBatch.commit(noResult: true);
  print('   ✅ Migrated $ticketCount tickets.');

  // Helper map for customer details
  final Map<int, Map<String, String>> customerMap = {};
  for (var cust in customers) {
    final int id = cust['id'];
    customerMap[id] = {
      'name': cust['name'] ?? '',
      'phone': cust['number'] ?? '',
    };
  }

  // 5. Migrate Sales
  print('💰 Migrating Sales...');
  final List<Map<String, dynamic>> sales = await sourceDb.query('sales');
  int salesCount = 0;
  final salesBatch = destDb.batch();
  for (var sale in sales) {
    final int customerId = sale['customer_id'] ?? 0;
    final customerDetails = customerMap[customerId] ?? {'name': 'عميل غير معروف', 'phone': ''};
    final double price = (sale['price'] as num? ?? 0.0).toDouble();
    final saleDateStr = formatDate(sale['date'] as int?);

    final itemsJson = jsonEncode([
      {
        'name': 'صيانة تذكرة رقم $customerId',
        'quantity': 1,
        'price': price,
        'total': price,
      }
    ]);

    salesBatch.insert('sales', {
      'id': sale['id'],
      'saleDate': saleDateStr,
      'customerName': customerDetails['name'],
      'customerPhone': customerDetails['phone'],
      'totalAmount': price,
      'discount': 0.0,
      'finalAmount': price,
      'paymentMethod': 'نقدي',
      'itemsJson': itemsJson,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    salesCount++;
  }
  await salesBatch.commit(noResult: true);
  print('   ✅ Migrated $salesCount sales.');

  // 6. Migrate Spare Parts Items -> spare_parts
  print('🔧 Migrating Spare Parts Inventory...');
  final List<Map<String, dynamic>> parts = await sourceDb.query('spare_parts_items');
  int partsCount = 0;
  final partsBatch = destDb.batch();
  for (var part in parts) {
    partsBatch.insert('spare_parts', {
      'id': part['id'],
      'name': part['name'] ?? '',
      'quantity': 1,
      'price': (part['price'] as num? ?? 0.0).toDouble(),
      'cost': 0.0,
      'supplier': '',
      'category_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    partsCount++;
  }
  await partsBatch.commit(noResult: true);
  print('   ✅ Migrated $partsCount spare parts.');

  // Close connections
  await sourceDb.close();
  await destDb.close();

  print('🎉 Database migration completed successfully!');
  print('📁 Created: $destDbPath');

  // 7. Copy to LOCALAPPDATA Shell folder to activate immediately
  final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
  if (localAppData.isNotEmpty) {
    final targetShellDir = '$localAppData\\Microsoft\\Windows\\Shell';
    final targetDbFile = File('$targetShellDir\\ELATTAR_STORE.db');
    print('📦 Copying ELATTAR_STORE.db to active Shell directory at $targetShellDir...');
    await Directory(targetShellDir).create(recursive: true);
    await File(destDbPath).copy(targetDbFile.path);
    print('   ✅ Active database updated successfully!');
  }
}
