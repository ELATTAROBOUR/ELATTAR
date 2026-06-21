import 'package:sqlite3/sqlite3.dart';
import 'dart:io';

Database? _db;

Database getDatabase() {
  if (_db != null) return _db!;

  final dbDir = Directory('data');
  if (!dbDir.existsSync()) {
    dbDir.createSync(recursive: true);
  }

  _db = sqlite3.open('${dbDir.path}/elattar_store.db');
  _createTables();
  return _db!;
}

void closeDatabase() {
  _db?.dispose();
  _db = null;
}

void _createTables() {
  final db = _db!;

  db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      passwordHash TEXT NOT NULL,
      role TEXT NOT NULL,
      name TEXT
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS modification_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      actionDate TEXT NOT NULL,
      actionType TEXT NOT NULL,
      itemType TEXT NOT NULL,
      itemName TEXT NOT NULL,
      details TEXT
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS tickets (
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
      agent TEXT,
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS spare_parts (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      price REAL NOT NULL,
      cost REAL NOT NULL DEFAULT 0.0,
      supplier TEXT,
      category_id INTEGER
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS technicians (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      phone TEXT NOT NULL,
      email TEXT
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS accessories (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS devices (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS deferred_payments (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS deferred_payments_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      deferredId INTEGER NOT NULL,
      amountPaid REAL NOT NULL,
      paymentDate TEXT NOT NULL,
      notes TEXT
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS suppliers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      phone TEXT,
      address TEXT
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS supplier_debts (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS supplier_payments_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      debtId INTEGER NOT NULL,
      amountPaid REAL NOT NULL,
      paymentDate TEXT NOT NULL,
      notes TEXT
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS goods_receipts (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS inventory_transfers (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS inventory_audits (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS warehouses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS sales (
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL
    )
  ''');

  db.execute('''
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

  // Seed default data if empty
  final warehouseCount = db
      .select('SELECT COUNT(*) as c FROM warehouses')
      .first;
  if (warehouseCount['c'] == 0) {
    db.execute("INSERT INTO warehouses (name) VALUES ('المحل الرئيسي')");
    db.execute("INSERT INTO warehouses (name) VALUES ('المخزن')");
  }

  final catCount = db.select('SELECT COUNT(*) as c FROM categories').first;
  if (catCount['c'] == 0) {
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
      db.execute('INSERT INTO categories (name, type) VALUES (?, ?)', [
        cat['name'],
        cat['type'],
      ]);
    }
  }
}
