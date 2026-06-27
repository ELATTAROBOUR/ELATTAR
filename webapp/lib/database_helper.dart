// lib/database_helper.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'db_init.dart';
import 'platform_stub.dart' if (dart.library.io) 'dart:io';

class DatabaseConnectionException implements Exception {
  final String message;
  DatabaseConnectionException(this.message);
  @override
  String toString() => message;
}

class DatabaseMissingException implements Exception {
  final String message;
  DatabaseMissingException(this.message);
  @override
  String toString() => message;
}

class DatabaseHelper {
  static Database? _db;
  static const String _dbName = 'ELATTAR_STORE.db';
  static String? dbConnectionError;
  static bool forceCreate = false;
  static AppUser? currentLoggedInUser;

  /// Returns the branch-specific database file name, or the default if no
  /// branch config has been loaded yet.
  static String get _activeDbName => currentBranch?.dbFileName ?? _dbName;

  static bool _isSyncing = false;
  static bool _syncPending = false;

  static Set<int> _loadedTicketIds = {};
  static Set<int> _loadedSparePartIds = {};
  static Set<String> _loadedTechnicianNames = {};

  static String complaintNumber = '01000361006';
  static int machineId = 1;

  static Future<void> loadMachineId() async {
    try {
      final config = await _loadSyncConfig();
      if (config != null && config['machine_id'] != null) {
        machineId = int.tryParse(config['machine_id']!) ?? 1;
        debugPrint('Loaded Machine ID: $machineId');
      } else {
        machineId = 1;
        debugPrint('Using default Machine ID: $machineId');
      }
    } catch (e) {
      debugPrint('Error loading machine ID: $e');
      machineId = 1;
    }
  }

  static Future<void> loadComplaintNumber() async {
    try {
      final val = await getSetting('complaintNumber');
      if (val != null && val.trim().isNotEmpty) {
        complaintNumber = val.trim();
      } else {
        complaintNumber = '01000361006';
      }
    } catch (e) {
      debugPrint('Error loading complaint number: $e');
      complaintNumber = '01000361006';
    }
  }

  /// Returns the database directory: %LOCALAPPDATA%\Microsoft\Windows\Shell
  static String getDbDir() {
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    if (localAppData.isEmpty) {
      return Directory.current.path;
    }
    return '$localAppData\\Microsoft\\Windows\\Shell';
  }

  static bool _initTimedOut = false;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    if (_initTimedOut) {
      throw DatabaseMissingException(
        'Database initialization timed out. Please check your connection and try again.',
      );
    }
    try {
      _db = await init().timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _initTimedOut = true;
      throw DatabaseMissingException(
        'Database initialization timed out. Please check your connection and try again.',
      );
    }
    return _db!;
  }

  static Future<void> reset() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
    _initTimedOut = false;
    dbConnectionError = null;
    forceCreate = false;
  }

  static int generateNextIdFromMax(int currentMax) {
    int base = (currentMax ~/ 10) * 10;
    if (base + machineId > currentMax) {
      return base + machineId;
    } else {
      return base + 10 + machineId;
    }
  }

  static Future<int> _generateNextId(
    DatabaseExecutor db,
    String tableName,
  ) async {
    try {
      final result = await db.rawQuery(
        'SELECT MAX(id) as max_id FROM $tableName',
      );
      int maxId = 0;
      if (result.isNotEmpty && result.first['max_id'] != null) {
        maxId = result.first['max_id'] as int;
      }
      return generateNextIdFromMax(maxId);
    } catch (e) {
      debugPrint('Error generating next ID for table $tableName: $e');
      return DateTime.now().millisecondsSinceEpoch * 10 + machineId;
    }
  }

  static Future<int> _insert(
    DatabaseExecutor database,
    String table,
    Map<String, dynamic> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'settings') {
      return await database.insert(
        table,
        values,
        nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm,
      );
    }
    final mutableValues = Map<String, dynamic>.from(values);
    if (mutableValues['id'] == null) {
      final nextId = await _generateNextId(database, table);
      mutableValues['id'] = nextId;
    }
    return await database.insert(
      table,
      mutableValues,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  // Load configuration from sync_config.json asset
  static Future<Map<String, String>?> loadSyncConfig() async {
    try {
      final jsonStr = await rootBundle.loadString('assets/sync_config.json');
      final data = jsonDecode(jsonStr);
      return {
        'repo_url': data['repo_url']?.toString() ?? '',
        'branch_name': data['branch_name']?.toString() ?? 'main',
        'store_email': data['store_email']?.toString() ?? 'store@example.com',
        'store_name': data['store_name']?.toString() ?? 'ELATTAR Store',
        'machine_id': data['machine_id']?.toString() ?? '1',
        'supabase_url': data['supabase_url']?.toString() ?? '',
        'supabase_anon_key': data['supabase_anon_key']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('Error loading sync_config.json from assets: $e');
      return null;
    }
  }

  // Private redirect to avoid breaking other calls in this file
  static Future<Map<String, String>?> _loadSyncConfig() => loadSyncConfig();

  // Startup Sync: Initialize Supabase and run sync
  static Future<void> performStartupSync() async {
    debugPrint('Startup Sync: Starting Supabase synchronization...');
    await syncDatabase();
  }

  // Runtime Sync: Bidirectional offline-first Supabase sync
  static Future<void> _performSupabaseSync() async {
    if (_isSyncing) {
      _syncPending = true;
      return;
    }
    _isSyncing = true;

    try {
      final config = await loadSyncConfig();
      if (config == null) {
        _isSyncing = false;
        return;
      }
      final url = config['supabase_url'];
      final anonKey = config['supabase_anon_key'];
      if (url == null ||
          url.isEmpty ||
          url == 'YOUR_SUPABASE_URL' ||
          anonKey == null ||
          anonKey.isEmpty ||
          anonKey == 'YOUR_SUPABASE_ANON_KEY') {
        debugPrint('Sync: Supabase is not configured yet.');
        _isSyncing = false;
        return;
      }

      // Initialize Supabase client if not already initialized
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(url: url, anonKey: anonKey);
        debugPrint('Sync: Supabase client initialized.');
      }

      final client = Supabase.instance.client;
      final database = await db;

      // 1. Process deletes first
      final deletes = await database.query('deleted_records');
      if (deletes.isNotEmpty) {
        debugPrint('Sync: Processing ${deletes.length} pending deletes...');
        for (var del in deletes) {
          final table = del['tableName'] as String;
          final recordId = del['recordId'] as String;
          final pk = table == 'settings' ? 'key' : 'id';

          try {
            final parsedId = int.tryParse(recordId) ?? recordId;
            await client.from(table).delete().eq(pk, parsedId);
            await database.delete(
              'deleted_records',
              where: 'id = ?',
              whereArgs: [del['id']],
            );
          } catch (e) {
            debugPrint(
              'Sync: Failed to delete $table record $recordId on remote: $e',
            );
          }
        }
      }

      // 2. Sync all tables in order
      final tablesToSync = [
        'users',
        'tickets',
        'spare_parts',
        'technicians',
        'settings',
        'accessories',
        'devices',
        'deferred_payments',
        'deferred_payments_history',
        'suppliers',
        'supplier_debts',
        'supplier_payments_history',
        'goods_receipts',
        'inventory_transfers',
        'inventory_audits',
        'warehouses',
        'sales',
        'categories',
        'returns',
        'attendance',
      ];

      for (var table in tablesToSync) {
        final pk = table == 'settings' ? 'key' : 'id';
        try {
          await _syncTable(table, pk, client);
        } catch (e) {
          debugPrint('Sync: Error syncing table $table: $e');
        }
      }

      debugPrint('Sync: Database fully synchronized with Supabase.');
      _publishSyncPing();
    } catch (e) {
      debugPrint('Sync: Error during synchronization: $e');
    } finally {
      _isSyncing = false;
      if (_syncPending) {
        _syncPending = false;
        Future.delayed(const Duration(seconds: 3), _performSupabaseSync);
      }
    }
  }

  // Generic table sync coordinator
  static Future<void> _syncTable(
    String tableName,
    String pk,
    SupabaseClient client,
  ) async {
    final database = await db;

    // Get local records
    final localRows = await database.query(tableName);

    // Fetch all remote records from Supabase using pagination to bypass the 1000-row limit
    final List<Map<String, dynamic>> remoteRows = [];
    int from = 0;
    const int pageSize = 1000;
    while (true) {
      final List<dynamic> response = await client
          .from(tableName)
          .select()
          .range(from, from + pageSize - 1);

      if (response.isEmpty) break;
      remoteRows.addAll(response.cast<Map<String, dynamic>>());
      if (response.length < pageSize) break;
      from += pageSize;
    }

    final Map<dynamic, Map<String, dynamic>> localMap = {
      for (var r in localRows) r[pk]: r,
    };
    final Map<dynamic, Map<String, dynamic>> remoteMap = {
      for (var r in remoteRows) r[pk]: r,
    };

    List<Map<String, dynamic>> toUpload = [];
    List<Map<String, dynamic>> toDownload = [];

    final columns = localRows.isNotEmpty
        ? localRows.first.keys.toList().cast<String>()
        : (remoteRows.isNotEmpty
              ? remoteRows.first.keys.toList().cast<String>()
              : <String>[]);

    if (columns.isEmpty) return;

    // Get actual local table columns (PRAGMA) to safely filter out remote-only columns
    // like Supabase auto-generated "created_at" that don't exist in local SQLite schema.
    var localColumnSet = <String>{...columns};
    try {
      final tableInfo = await database.rawQuery(
        'PRAGMA table_info($tableName)',
      );
      localColumnSet = tableInfo.map((r) => r['name'] as String).toSet();
    } catch (_) {
      // Keep default columns if PRAGMA fails
    }

    // Check local records for upload or merge
    for (var localRow in localRows) {
      final id = localRow[pk];
      if (!remoteMap.containsKey(id)) {
        toUpload.add(localRow);
      } else {
        final remoteRow = remoteMap[id]!;
        if (!rowsAreEqual(localRow, remoteRow, columns)) {
          final mergedRow = mergeRows(
            null,
            localRow,
            remoteRow,
            columns,
            tableName,
          );

          if (!rowsAreEqual(mergedRow, remoteRow, columns)) {
            toUpload.add(mergedRow);
          }
          if (!rowsAreEqual(mergedRow, localRow, columns)) {
            toDownload.add(mergedRow);
          }
        }
      }
    }

    // Check remote records for download
    for (var remoteRow in remoteRows) {
      final id = remoteRow[pk];
      if (!localMap.containsKey(id)) {
        toDownload.add(remoteRow);
      }
    }

    // Check if remote has updatedAt column; if not, strip it from upload to avoid Supabase errors
    final bool remoteHasUpdatedAt =
        remoteRows.isNotEmpty && remoteRows.first.containsKey('updatedAt');

    // Execute uploads in batches of 100 to prevent payload size limits / timeouts
    if (toUpload.isNotEmpty) {
      const batchSize = 100;
      for (var i = 0; i < toUpload.length; i += batchSize) {
        final end = (i + batchSize < toUpload.length)
            ? i + batchSize
            : toUpload.length;
        var batch = toUpload.sublist(i, end);
        if (!remoteHasUpdatedAt) {
          batch = batch
              .map((row) => Map<String, dynamic>.from(row)..remove('updatedAt'))
              .toList();
        }
        await client.from(tableName).upsert(batch);
      }
    }

    // Execute downloads
    if (toDownload.isNotEmpty) {
      await database.transaction((txn) async {
        final batch = txn.batch();
        for (var row in toDownload) {
          // Filter to only include columns that exist in the local table
          final filteredRow = Map<String, dynamic>.fromEntries(
            row.entries.where((e) => localColumnSet.contains(e.key)),
          );
          batch.insert(
            tableName,
            filteredRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });
    }
  }

  // Memory-based 3-way row merger (accepts optional base row for true 3-way merge)
  static Map<String, dynamic> mergeRows(
    Map<String, dynamic>? base,
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    List<String> columns,
    String tableName,
  ) {
    final Map<String, dynamic> merged = {};
    for (var col in columns) {
      final baseVal = base?[col];
      final localVal = local[col];
      final remoteVal = remote[col];

      final bool localChanged = !_fieldsAreEqual(localVal, baseVal);
      final bool remoteChanged = !_fieldsAreEqual(remoteVal, baseVal);

      if (localChanged && remoteChanged) {
        // Conflict! Both sides changed the same field
        if (col == 'status' && tableName == 'tickets') {
          // Use updatedAt timestamp for conflict resolution (newer wins)
          final localUpdatedAt = local['updatedAt'] as int? ?? 0;
          final remoteUpdatedAt = remote['updatedAt'] as int? ?? 0;
          merged[col] = localUpdatedAt >= remoteUpdatedAt
              ? localVal
              : remoteVal;
        } else if (col == 'updatedAt') {
          // For updatedAt itself, take the later timestamp
          final localTS = localVal as int? ?? 0;
          final remoteTS = remoteVal as int? ?? 0;
          merged[col] = localTS >= remoteTS ? localVal : remoteVal;
        } else {
          // Default conflict resolution: local wins
          merged[col] = localVal;
        }
      } else if (remoteChanged) {
        // Only remote changed it -> take remote
        merged[col] = remoteVal;
      } else {
        // Only local changed it, or neither did -> keep local
        merged[col] = localVal;
      }
    }
    return merged;
  }

  static int _getRepairStatusWeight(String status) {
    switch (status) {
      case 'pending':
        return 1;
      case 'in_progress':
        return 2;
      case 'repaired':
        return 3;
      case 'delivered':
        return 4;
      case 'rejected':
        return 5;
      default:
        return 0;
    }
  }

  static bool _fieldsAreEqual(dynamic valA, dynamic valB) {
    if (valA == valB) return true;
    if (valA == null || valB == null) {
      if (valA == null && valB == '') return true;
      if (valB == null && valA == '') return true;
      return false;
    }
    if (valA is num && valB is num) {
      return valA.toDouble() == valB.toDouble();
    }
    if (valA is bool && valB is int) {
      return (valA ? 1 : 0) == valB;
    }
    if (valB is bool && valA is int) {
      return (valB ? 1 : 0) == valA;
    }
    return valA.toString().trim() == valB.toString().trim();
  }

  static bool rowsAreEqual(
    Map<String, dynamic> rowA,
    Map<String, dynamic> rowB,
    List<String> columns,
  ) {
    for (var col in columns) {
      if (!_fieldsAreEqual(rowA[col], rowB[col])) return false;
    }
    return true;
  }

  // Dual Mirror Sync Helper
  static Future<void> syncDatabase() async {
    try {
      final dbDir = getDbDir();
      final activeFile = File('$dbDir\\$_activeDbName');

      if (Platform.isWindows && await activeFile.exists()) {
        final execDir = File(Platform.resolvedExecutable).parent.path;
        final backupFile = File('$execDir/$_activeDbName');
        await activeFile.copy(backupFile.path);
        debugPrint(
          'Database mirrored to executable folder successfully: ${backupFile.path}',
        );
      }
    } catch (e) {
      debugPrint('Failed to mirror database file: $e');
    }

    _performSupabaseSync();
  }

  static Future<void> _publishSyncPing() async {
    try {
      final response = await http
          .post(
            Uri.parse('https://ntfy.sh/elattar_sync_obourdist_9f70cb7a'),
            headers: {'Title': 'Sync', 'Priority': 'min'},
            body: 'desktop',
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        debugPrint('Sync Ping: Successfully sent desktop sync ping.');
      } else {
        debugPrint('Sync Ping: Failed to send ping: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Sync Ping: Error sending ping: $e');
    }
  }

  static Future<bool> importDatabase(String sourcePath) async {
    try {
      final file = File(sourcePath);
      if (await file.exists()) {
        final dbDir = getDbDir();
        final dbFile = File('$dbDir\\$_activeDbName');
        await Directory(dbDir).create(recursive: true);
        await file.copy(dbFile.path);
        debugPrint(
          'Database file imported successfully to Shell from: $sourcePath',
        );

        if (Platform.isWindows) {
          try {
            final execDir = File(Platform.resolvedExecutable).parent.path;
            final repoDbFile = File('$execDir/$_activeDbName');
            await file.copy(repoDbFile.path);
            debugPrint('Database file also copied next to executable.');
          } catch (e) {
            debugPrint(
              'Failed to copy imported database next to executable: $e',
            );
          }
        }
        await reset();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to import database: $e');
      return false;
    }
  }

  static Future<Database> init() async {
    await loadMachineId();
    await initBranches(); // ← load multi-branch config (sets machineId too)
    String dbPath = "";
    dbConnectionError = null;

    if (Platform.isWindows) {
      final dbDir = getDbDir();
      dbPath = '$dbDir\\$_activeDbName';
      final dbFile = File(dbPath);

      final execDir = File(Platform.resolvedExecutable).parent.path;
      final execDbFile = File('$execDir/$_activeDbName');

      // Ensure the Shell directory exists
      await Directory(dbDir).create(recursive: true);

      // 1. Startup Sync logic
      if (!dbFile.existsSync() && execDbFile.existsSync()) {
        try {
          execDbFile.copySync(dbFile.path);
          debugPrint(
            'Startup Sync: Restored database from Executable folder to Shell.',
          );
        } catch (e) {
          debugPrint(
            'Startup Sync: Failed to copy database from Executable folder: $e',
          );
        }
      } else if (dbFile.existsSync() && !execDbFile.existsSync()) {
        try {
          dbFile.copySync(execDbFile.path);
          debugPrint(
            'Startup Sync: Copied database from Shell to Executable folder.',
          );
        } catch (e) {
          debugPrint(
            'Startup Sync: Failed to copy database to Executable folder: $e',
          );
        }
      }

      // 2. If database is still missing
      if (!dbFile.existsSync()) {
        if (!forceCreate) {
          throw DatabaseMissingException(
            'لم يتم العثور على قاعدة البيانات محلياً.',
          );
        }
        debugPrint('Database not found. Initializing a new database file.');
      }
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        dbPath = '${dir.path}/$_activeDbName';
      } catch (e) {
        // Web fallback: path_provider has no web implementation
        debugPrint(
          'getApplicationDocumentsDirectory failed (web fallback): $e',
        );
        dbPath = '$_activeDbName';
      }
    }

    setupDatabaseFactory();

    final databaseInstance = await openDatabase(
      dbPath,
      version: 15,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            email TEXT UNIQUE NOT NULL,
            passwordHash TEXT NOT NULL,
            role TEXT NOT NULL,
            name TEXT
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
            expectedDelivery TEXT,
            agent TEXT,
            updatedAt INTEGER
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
            phone TEXT NOT NULL,
            email TEXT,
            mobilePasswordHash TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');

        // Accessories Table
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

        // Devices Table
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

        // Customer Deferred Payments Table
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

        // Customer Payments History
        await db.execute('''
          CREATE TABLE deferred_payments_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            deferredId INTEGER NOT NULL,
            amountPaid REAL NOT NULL,
            paymentDate TEXT NOT NULL,
            notes TEXT
          )
        ''');

        // Suppliers Table
        await db.execute('''
          CREATE TABLE suppliers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            phone TEXT,
            address TEXT
          )
        ''');

        // Supplier Debts Table
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

        // Supplier Payments History
        await db.execute('''
          CREATE TABLE supplier_payments_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            debtId INTEGER NOT NULL,
            amountPaid REAL NOT NULL,
            paymentDate TEXT NOT NULL,
            notes TEXT
          )
        ''');

        // Goods Receipts Table
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

        // Inventory Transfers Table
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

        // Inventory Audits Table
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

        // Warehouses Table
        await db.execute('''
          CREATE TABLE warehouses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE
          )
        ''');

        // Sales Table
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

        // Categories Table
        await db.execute('''
          CREATE TABLE categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL
          )
        ''');

        // Returns Table
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

        // Insert Default Warehouses
        await db.insert('warehouses', {'name': 'المحل الرئيسي'});
        await db.insert('warehouses', {'name': 'المخزن'});

        // Insert Default Categories
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

        // Attendance table
        await db.execute('''
          CREATE TABLE IF NOT EXISTS attendance (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            userId INTEGER,
            userName TEXT NOT NULL,
            userRole TEXT NOT NULL,
            date TEXT NOT NULL,
            checkIn TEXT,
            checkOut TEXT,
            status TEXT NOT NULL DEFAULT 'present',
            notes TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute(
              'ALTER TABLE tickets ADD COLUMN partsCost REAL DEFAULT 0.0',
            );
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE tickets ADD COLUMN partsUsed TEXT');
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE tickets ADD COLUMN commissionRate REAL DEFAULT 50.0',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE tickets ADD COLUMN isClosed INTEGER DEFAULT 0',
            );
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute(
              'ALTER TABLE tickets ADD COLUMN expectedDelivery TEXT',
            );
          } catch (_) {}
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS accessories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              quantity INTEGER NOT NULL,
              price REAL NOT NULL,
              cost REAL NOT NULL DEFAULT 0.0,
              supplier TEXT,
              warehouse TEXT NOT NULL DEFAULT 'المحل الرئيسي',
              code TEXT
            )
          ''');
          await db.execute('''
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
              code TEXT
            )
          ''');
          await db.execute('''
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
          await db.execute('''
            CREATE TABLE IF NOT EXISTS deferred_payments_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              deferredId INTEGER NOT NULL,
              amountPaid REAL NOT NULL,
              paymentDate TEXT NOT NULL,
              notes TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS suppliers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              phone TEXT,
              address TEXT
            )
          ''');
          await db.execute('''
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
          await db.execute('''
            CREATE TABLE IF NOT EXISTS supplier_payments_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              debtId INTEGER NOT NULL,
              amountPaid REAL NOT NULL,
              paymentDate TEXT NOT NULL,
              notes TEXT
            )
          ''');
          await db.execute('''
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
          await db.execute('''
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
          await db.execute('''
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
          await db.execute('''
            CREATE TABLE IF NOT EXISTS warehouses (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE
            )
          ''');

          try {
            await db.insert('warehouses', {'name': 'المحل الرئيسي'});
            await db.insert('warehouses', {'name': 'المخزن'});
          } catch (_) {}
        }

        if (oldVersion < 5) {
          try {
            await db.execute('ALTER TABLE accessories ADD COLUMN code TEXT');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE devices ADD COLUMN code TEXT');
          } catch (_) {}
        }

        if (oldVersion < 6) {
          try {
            await db.execute(
              'ALTER TABLE spare_parts ADD COLUMN cost REAL DEFAULT 0.0',
            );
          } catch (_) {}
        }

        if (oldVersion < 7) {
          try {
            await db.execute('''
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
          } catch (_) {}
        }

        if (oldVersion < 8) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                type TEXT NOT NULL
              )
            ''');
          } catch (_) {}

          try {
            await db.execute(
              'ALTER TABLE accessories ADD COLUMN category_id INTEGER',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE spare_parts ADD COLUMN category_id INTEGER',
            );
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE devices ADD COLUMN category_id INTEGER',
            );
          } catch (_) {}

          // Insert defaults
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
            try {
              await db.insert('categories', cat);
            } catch (_) {}
          }
        }
        if (oldVersion < 9) {
          try {
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
          } catch (_) {}
        }
        if (oldVersion < 10) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT UNIQUE NOT NULL,
                passwordHash TEXT NOT NULL,
                role TEXT NOT NULL
              )
            ''');

            // Migrate existing manager credentials
            final List<Map<String, dynamic>> mapsEmail = await db.query(
              'settings',
              where: 'key = ?',
              whereArgs: ['clientEmail'],
            );
            final List<Map<String, dynamic>> mapsHash = await db.query(
              'settings',
              where: 'key = ?',
              whereArgs: ['clientPasswordHash'],
            );
            if (mapsEmail.isNotEmpty && mapsHash.isNotEmpty) {
              final email = mapsEmail.first['value'] as String?;
              final hash = mapsHash.first['value'] as String?;
              if (email != null &&
                  email.isNotEmpty &&
                  hash != null &&
                  hash.isNotEmpty) {
                await db.insert('users', {
                  'email': email,
                  'passwordHash': hash,
                  'role': 'manager',
                }, conflictAlgorithm: ConflictAlgorithm.ignore);
              }
            }
          } catch (e) {
            debugPrint('Error migrating user credentials to version 10: $e');
          }
        }
        if (oldVersion < 11) {
          try {
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
          } catch (e) {
            debugPrint('Error creating returns table in migration: $e');
          }
        }
        if (oldVersion < 12) {
          try {
            await db.execute(
              "ALTER TABLE technicians ADD COLUMN mobilePasswordHash TEXT",
            );
          } catch (e) {
            debugPrint('Error adding mobilePasswordHash to technicians: $e');
          }
        }
        if (oldVersion < 13) {
          try {
            await db.execute("ALTER TABLE technicians ADD COLUMN email TEXT");
          } catch (e) {
            debugPrint('Error adding email to technicians: $e');
          }
        }
        if (oldVersion < 14) {
          try {
            await db.execute("ALTER TABLE tickets ADD COLUMN agent TEXT");
          } catch (e) {
            debugPrint('Error adding agent to tickets: $e');
          }
        }
        if (oldVersion < 15) {
          try {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS attendance (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId INTEGER,
                userName TEXT NOT NULL,
                userRole TEXT NOT NULL,
                date TEXT NOT NULL,
                checkIn TEXT,
                checkOut TEXT,
                status TEXT NOT NULL DEFAULT 'present',
                notes TEXT
              )
            ''');
          } catch (e) {
            debugPrint('Error creating attendance table: $e');
          }
        }
        if (oldVersion < 16) {
          try {
            await db.execute(
              'ALTER TABLE tickets ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('Migration 16: Added updatedAt column to tickets');
          } catch (e) {
            debugPrint('Migration 16 (updatedAt) error: $e');
          }
        }
      },
      onOpen: (db) async {
        // Self-Healing: Ensure returns table exists in SQLite
        try {
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
        } catch (e) {
          debugPrint('Error creating returns table: $e');
        }

        // Self-Healing: Ensure columns exist in tickets, technicians, and users
        try {
          await db.execute('ALTER TABLE tickets ADD COLUMN agent TEXT');
          debugPrint('Self-Healing: Added agent column to tickets');
        } catch (_) {}
        try {
          await db.execute(
            'ALTER TABLE technicians ADD COLUMN mobilePasswordHash TEXT',
          );
          debugPrint(
            'Self-Healing: Added mobilePasswordHash column to technicians',
          );
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE technicians ADD COLUMN email TEXT');
          debugPrint('Self-Healing: Added email column to technicians');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE users ADD COLUMN name TEXT');
          debugPrint('Self-Healing: Added name column to users');
        } catch (_) {}
        try {
          await db.execute('ALTER TABLE tickets ADD COLUMN updatedAt INTEGER');
          debugPrint('Self-Healing: Added updatedAt column to tickets');
        } catch (_) {}

        // Create deleted_records table to track deletes for Supabase
        await db.execute('''
          CREATE TABLE IF NOT EXISTS deleted_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tableName TEXT NOT NULL,
            recordId TEXT NOT NULL,
            deletedAt TEXT NOT NULL
          )
        ''');

        // Dynamically create delete triggers for all tables
        final tablesToSync = [
          'users',
          'tickets',
          'spare_parts',
          'technicians',
          'settings',
          'accessories',
          'devices',
          'deferred_payments',
          'deferred_payments_history',
          'suppliers',
          'supplier_debts',
          'supplier_payments_history',
          'goods_receipts',
          'inventory_transfers',
          'inventory_audits',
          'warehouses',
          'sales',
          'categories',
          'returns',
          'attendance',
        ];

        for (var table in tablesToSync) {
          final pk = table == 'settings' ? 'key' : 'id';
          try {
            await db.execute('''
              CREATE TRIGGER IF NOT EXISTS log_${table}_delete AFTER DELETE ON $table
              BEGIN
                INSERT INTO deleted_records (tableName, recordId, deletedAt)
                VALUES ('$table', CAST(OLD.$pk AS TEXT), datetime('now'));
              END;
            ''');
          } catch (e) {
            debugPrint('Error creating delete trigger for $table: $e');
          }
        }
      },
    );
    _db = databaseInstance;
    Future.microtask(() => performStartupSync());
    return databaseInstance;
  }

  static int? _firstIntValue(List<Map<String, Object?>> list) {
    if (list.isNotEmpty && list.first.isNotEmpty) {
      final val = list.first.values.first;
      if (val is int) return val;
    }
    return null;
  }

  // --- Check migration (keep support for migrating old JSON data on startup) ---
  static Future<void> checkAndMigrate() async {
    final database = await db;

    // Migrate any 'admin' role to 'manager' in the users table to prevent role mismatches
    try {
      await database.execute(
        "UPDATE users SET role = 'manager' WHERE role = 'admin'",
      );
      debugPrint('Self-Healing: Migrated any admin role to manager.');
    } catch (e) {
      debugPrint('Error migrating admin role to manager: $e');
    }

    final dir = Directory(getDbDir());
    bool didMigrate = false;

    // 1. Migrate tickets.json
    final ticketsFile = File('${dir.path}/tickets.json');
    if (await ticketsFile.exists()) {
      try {
        final count =
            _firstIntValue(
              await database.rawQuery('SELECT COUNT(*) FROM tickets'),
            ) ??
            0;
        if (count == 0) {
          final data = await ticketsFile.readAsString();
          final List jsonList = json.decode(data);
          final batch = database.batch();
          for (var item in jsonList) {
            batch.insert('tickets', {
              'id': item['id'],
              'customerName': item['customerName'],
              'customerPhone': item['customerPhone'],
              'deviceModel': item['deviceModel'],
              'problem': item['problem'],
              'status': item['status'],
              'receivedDate': item['receivedDate'],
              'deliveryDate': item['deliveryDate'],
              'cost': (item['cost'] as num).toDouble(),
              'notes': item['notes'],
              'technicianName': item['technicianName'],
              'technicianPhone': item['technicianPhone'],
              'complaintNumber': item['complaintNumber'],
              'deviceCondition': item['deviceCondition'] ?? '',
              'paymentMethod': item['paymentMethod'],
              'paymentDetails': item['paymentDetails'],
            });
          }
          await batch.commit(noResult: true);
          didMigrate = true;
          debugPrint('Migrated tickets.json to SQLite successfully.');
        }
        await ticketsFile.rename('${dir.path}/tickets.json.bak');
      } catch (e) {
        debugPrint('Error migrating tickets.json: $e');
      }
    }

    // 2. Migrate spare_parts.json
    final partsFile = File('${dir.path}/spare_parts.json');
    if (await partsFile.exists()) {
      try {
        final count =
            _firstIntValue(
              await database.rawQuery('SELECT COUNT(*) FROM spare_parts'),
            ) ??
            0;
        if (count == 0) {
          final data = await partsFile.readAsString();
          final List jsonList = json.decode(data);
          final batch = database.batch();
          for (var item in jsonList) {
            batch.insert('spare_parts', {
              'id': item['id'],
              'name': item['name'],
              'quantity': item['quantity'],
              'price': (item['price'] as num).toDouble(),
              'supplier': item['supplier'],
            });
          }
          await batch.commit(noResult: true);
          didMigrate = true;
          debugPrint('Migrated spare_parts.json to SQLite successfully.');
        }
        await partsFile.rename('${dir.path}/spare_parts.json.bak');
      } catch (e) {
        debugPrint('Error migrating spare_parts.json: $e');
      }
    }

    if (didMigrate) {
      await syncDatabase();
    }
  }

  // --- Tickets ---
  static Future<List<Ticket>> loadTickets() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'tickets',
      orderBy: 'id DESC',
    );
    final list = maps.map((map) {
      return Ticket(
        id: map['id'] as int,
        customerName: map['customerName'] as String,
        customerPhone: map['customerPhone'] as String,
        deviceModel: map['deviceModel'] as String,
        problem: map['problem'] as String,
        status: map['status'] as String,
        receivedDate: DateTime.parse(map['receivedDate'] as String),
        deliveryDate: map['deliveryDate'] != null
            ? DateTime.parse(map['deliveryDate'] as String)
            : null,
        cost: (map['cost'] as num).toDouble(),
        notes: map['notes'] as String,
        agent: map['agent'] as String?,
        technicianName: map['technicianName'] as String?,
        technicianPhone: map['technicianPhone'] as String?,
        complaintNumber: map['complaintNumber'] as String?,
        deviceCondition: map['deviceCondition'] as String? ?? '',
        paymentMethod: map['paymentMethod'] as String?,
        paymentDetails: map['paymentDetails'] as String?,
        partsCost: (map['partsCost'] as num?)?.toDouble() ?? 0.0,
        partsUsed: map['partsUsed'] as String?,
        commissionRate: (map['commissionRate'] as num?)?.toDouble() ?? 50.0,
        isClosed: map['isClosed'] as int? ?? 0,
        expectedDelivery: map['expectedDelivery'] as String?,
      );
    }).toList();
    _loadedTicketIds = list.map((t) => t.id).toSet();
    return list;
  }

  static Future<void> saveTickets(List<Ticket> tickets) async {
    final database = await db;

    // Check if the updatedAt column exists in the tickets table
    bool hasUpdatedAt = false;
    try {
      final tableInfo = await database.rawQuery('PRAGMA table_info(tickets)');
      hasUpdatedAt = tableInfo.any((r) => r['name'] == 'updatedAt');
    } catch (_) {}

    await database.transaction((txn) async {
      final inputIds = tickets.map((t) => t.id).toSet();
      final deletedIds = _loadedTicketIds.difference(inputIds);

      for (var id in deletedIds) {
        await txn.delete('tickets', where: 'id = ?', whereArgs: [id]);
      }

      final batch = txn.batch();
      for (var t in tickets) {
        final json = t.toJson();
        if (!hasUpdatedAt) {
          json.remove('updatedAt');
        }
        batch.insert(
          'tickets',
          json,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      _loadedTicketIds = inputIds;
    });
    await syncDatabase();
  }

  // --- Spare Parts ---
  static Future<List<SparePart>> loadSpareParts() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.rawQuery('''
      SELECT s.*, c.name as category_name
      FROM spare_parts s
      LEFT JOIN categories c ON s.category_id = c.id
    ''');
    final list = maps.map((map) {
      final part = SparePart.fromJson(map);
      part.categoryName = map['category_name'] as String?;
      return part;
    }).toList();
    _loadedSparePartIds = list.map((p) => p.id).toSet();
    return list;
  }

  static Future<void> saveSpareParts(List<SparePart> parts) async {
    final database = await db;
    await database.transaction((txn) async {
      final inputIds = parts.map((p) => p.id).toSet();
      final deletedIds = _loadedSparePartIds.difference(inputIds);

      for (var id in deletedIds) {
        await txn.delete('spare_parts', where: 'id = ?', whereArgs: [id]);
      }

      final batch = txn.batch();
      for (var p in parts) {
        batch.insert(
          'spare_parts',
          p.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      _loadedSparePartIds = inputIds;
    });
    await syncDatabase();
  }

  static Future<int> saveSparePart(SparePart part) async {
    final database = await db;
    String actionType = 'إضافة';
    String details =
        'الكمية: ${part.quantity}، السعر: ${part.price}، التكلفة: ${part.cost}';

    final List<Map<String, dynamic>> existing = await database.query(
      'spare_parts',
      where: 'id = ?',
      whereArgs: [part.id],
    );
    if (existing.isNotEmpty) {
      actionType = 'تعديل';
      final oldPart = existing.first;
      List<String> changes = [];
      if (oldPart['name'] != part.name)
        changes.add('الاسم من "${oldPart['name']}" إلى "${part.name}"');
      if (oldPart['quantity'] != part.quantity)
        changes.add('الكمية من ${oldPart['quantity']} إلى ${part.quantity}');
      if (oldPart['price'] != part.price)
        changes.add('السعر من ${oldPart['price']} إلى ${part.price}');
      if (oldPart['cost'] != part.cost)
        changes.add('التكلفة من ${oldPart['cost']} إلى ${part.cost}');
      details = changes.isEmpty ? 'تعديل البيانات العامة' : changes.join('، ');
    }

    final id = await _insert(
      database,
      'spare_parts',
      part.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await logModification(
      actionType: actionType,
      itemType: 'قطعة غيار',
      itemName: part.name,
      details: details,
    );

    await syncDatabase();
    return id;
  }

  static Future<void> deleteSparePart(int id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'spare_parts',
      where: 'id = ?',
      whereArgs: [id],
    );
    String name = 'غير معروف';
    if (maps.isNotEmpty) name = maps.first['name'] as String;

    await database.delete('spare_parts', where: 'id = ?', whereArgs: [id]);

    await logModification(
      actionType: 'حذف',
      itemType: 'قطعة غيار',
      itemName: name,
      details: 'تم حذف قطعة الغيار نهائياً من النظام',
    );
    await syncDatabase();
  }

  // --- Sales ---
  static Future<int> saveSale(Sale sale) async {
    final database = await db;
    final id = await _insert(
      database,
      'sales',
      sale.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await logModification(
      actionType: 'عملية بيع',
      itemType: 'مبيعات',
      itemName: sale.customerName ?? 'عميل نقدي',
      details:
          'القيمة النهائية: ${sale.finalAmount} ج.م، طريقة الدفع: ${sale.paymentMethod == 'cash' ? 'نقدي' : 'آجل'}',
    );
    await syncDatabase();
    return id;
  }

  static Future<List<Sale>> loadSales() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'sales',
      orderBy: 'id DESC',
    );
    return maps.map((map) => Sale.fromJson(map)).toList();
  }

  // --- Returns ---
  static Future<int> saveReturn(ReturnTransaction ret) async {
    final database = await db;
    final id = await _insert(
      database,
      'returns',
      ret.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await logModification(
      actionType: 'عملية مرتجع',
      itemType: 'مرتجع',
      itemName: ret.customerName ?? 'عميل مرتجع',
      details:
          'القيمة المستردة: ${ret.totalAmount} ج.م، طريقة الدفع: ${ret.paymentMethod == 'cash' ? 'نقدي' : ret.paymentMethod}',
    );
    await syncDatabase();
    return id;
  }

  static Future<List<ReturnTransaction>> loadReturns() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'returns',
      orderBy: 'id DESC',
    );
    return maps.map((map) => ReturnTransaction.fromJson(map)).toList();
  }

  // --- Technicians ---
  static Future<List<Map<String, String>>> loadTechnicians() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query('technicians');
    final list = maps.map((map) {
      return {
        'name': (map['name'] as String?) ?? '',
        'phone': (map['phone'] as String?) ?? '',
        'mobilePasswordHash': (map['mobilePasswordHash'] as String?) ?? '',
        'email': (map['email'] as String?) ?? '',
      };
    }).toList();
    _loadedTechnicianNames = list.map((t) => t['name']!).toSet();
    return list;
  }

  static Future<void> saveTechnicians(List<Map<String, String>> techs) async {
    final database = await db;
    await database.transaction((txn) async {
      final inputNames = techs.map((t) => t['name']!).toSet();
      final deletedNames = _loadedTechnicianNames.difference(inputNames);

      for (var name in deletedNames) {
        await txn.delete('technicians', where: 'name = ?', whereArgs: [name]);
      }

      for (var t in techs) {
        final List<Map<String, dynamic>> existing = await txn.query(
          'technicians',
          where: 'name = ?',
          whereArgs: [t['name']],
        );
        if (existing.isNotEmpty) {
          final updateData = <String, dynamic>{'phone': t['phone']};
          if (t['mobilePasswordHash'] != null &&
              t['mobilePasswordHash']!.isNotEmpty) {
            updateData['mobilePasswordHash'] = t['mobilePasswordHash'];
          }
          if (t['email'] != null && t['email']!.isNotEmpty) {
            updateData['email'] = t['email'];
          }
          await txn.update(
            'technicians',
            updateData,
            where: 'name = ?',
            whereArgs: [t['name']],
          );
        } else {
          final nextId = await _generateNextId(txn, 'technicians');
          await txn.insert('technicians', {
            'id': nextId,
            'name': t['name'],
            'phone': t['phone'],
            if (t['mobilePasswordHash'] != null &&
                t['mobilePasswordHash']!.isNotEmpty)
              'mobilePasswordHash': t['mobilePasswordHash'],
            if (t['email'] != null && t['email']!.isNotEmpty)
              'email': t['email'],
          });
        }
      }
      _loadedTechnicianNames = inputNames;
    });
    await syncDatabase();
  }

  /// Add a single technician with optional mobile password and email
  static Future<void> addTechnician(
    String name,
    String phone, {
    String? mobilePasswordHash,
    String? email,
  }) async {
    final database = await db;
    final nextId = await _generateNextId(database, 'technicians');
    await database.insert('technicians', {
      'id': nextId,
      'name': name.trim(),
      'phone': phone.trim(),
      if (mobilePasswordHash != null && mobilePasswordHash.isNotEmpty)
        'mobilePasswordHash': mobilePasswordHash,
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    _loadedTechnicianNames.add(name.trim());

    // Also create/update a user login entry for mobile access
    if (email != null &&
        email.trim().isNotEmpty &&
        mobilePasswordHash != null &&
        mobilePasswordHash.isNotEmpty) {
      try {
        final existingUser = await getUserByEmail(email.trim());
        if (existingUser != null) {
          existingUser.passwordHash = mobilePasswordHash;
          await saveUser(existingUser);
        } else {
          await saveUser(
            AppUser(
              email: email.trim(),
              passwordHash: mobilePasswordHash,
              role: 'technician',
            ),
          );
        }
      } catch (e) {
        debugPrint('Error creating user for technician: $e');
      }
    }

    await syncDatabase();
  }

  /// Delete a technician by id
  static Future<void> deleteTechnician(int id, String name) async {
    final database = await db;
    // First get the technician's email to also delete the user account
    final List<Map<String, dynamic>> techs = await database.query(
      'technicians',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (techs.isNotEmpty) {
      final email = techs.first['email'] as String?;
      if (email != null && email.isNotEmpty) {
        await database.delete('users', where: 'email = ?', whereArgs: [email]);
      }
    }
    await database.delete('technicians', where: 'id = ?', whereArgs: [id]);
    _loadedTechnicianNames.remove(name);
    await syncDatabase();
  }

  /// Update technician details (name, phone, email)
  static Future<void> updateTechnician(
    int id,
    String name,
    String phone, {
    String? email,
    String? mobilePasswordHash,
  }) async {
    final database = await db;
    // Get old data first
    final List<Map<String, dynamic>> oldTechs = await database.query(
      'technicians',
      where: 'id = ?',
      whereArgs: [id],
    );
    final oldEmail = oldTechs.isNotEmpty
        ? oldTechs.first['email'] as String?
        : null;
    final oldName = oldTechs.isNotEmpty
        ? oldTechs.first['name'] as String?
        : null;
    final oldPasswordHash = oldTechs.isNotEmpty
        ? oldTechs.first['mobilePasswordHash'] as String?
        : null;

    if (oldName != null) {
      _loadedTechnicianNames.remove(oldName);
    }

    final updateData = <String, dynamic>{
      'name': name.trim(),
      'phone': phone.trim(),
    };
    if (email != null) {
      updateData['email'] = email.trim();
    }
    if (mobilePasswordHash != null && mobilePasswordHash.isNotEmpty) {
      updateData['mobilePasswordHash'] = mobilePasswordHash;
    }

    await database.update(
      'technicians',
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
    _loadedTechnicianNames.add(name.trim());

    // Update corresponding user account
    final activeEmail = email?.trim() ?? oldEmail?.trim();
    final activePasswordHash =
        (mobilePasswordHash != null && mobilePasswordHash.isNotEmpty)
        ? mobilePasswordHash
        : oldPasswordHash;

    if (activeEmail != null && activeEmail.isNotEmpty) {
      try {
        // Delete old user if email changed
        if (oldEmail != null && oldEmail.trim() != activeEmail) {
          await database.delete(
            'users',
            where: 'email = ?',
            whereArgs: [oldEmail.trim()],
          );
        }

        // Only save to users table if we have a password hash
        if (activePasswordHash != null && activePasswordHash.isNotEmpty) {
          final existingUser = await getUserByEmail(activeEmail);
          if (existingUser != null) {
            existingUser.passwordHash = activePasswordHash;
            await saveUser(existingUser);
          } else {
            await saveUser(
              AppUser(
                email: activeEmail,
                passwordHash: activePasswordHash,
                role: 'technician',
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error updating user for technician: $e');
      }
    }

    await syncDatabase();
  }

  /// Set / update the mobile password hash for a technician
  static Future<void> setTechnicianMobilePassword(
    int id,
    String passwordHash,
  ) async {
    final database = await db;
    await database.update(
      'technicians',
      {'mobilePasswordHash': passwordHash},
      where: 'id = ?',
      whereArgs: [id],
    );

    // Also update/create the user account in users table for mobile login
    try {
      final List<Map<String, dynamic>> techs = await database.query(
        'technicians',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (techs.isNotEmpty) {
        final String? email = techs.first['email'] as String?;
        if (email != null && email.trim().isNotEmpty) {
          final existingUser = await getUserByEmail(email.trim());
          if (existingUser != null) {
            existingUser.passwordHash = passwordHash;
            await saveUser(existingUser);
          } else {
            await saveUser(
              AppUser(
                email: email.trim(),
                passwordHash: passwordHash,
                role: 'technician',
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error syncing user password for technician $id: $e');
    }

    await syncDatabase();
  }

  /// Load technicians with full row data (for management UI)
  static Future<List<Map<String, dynamic>>> loadTechniciansRaw() async {
    final database = await db;
    return await database.query('technicians', orderBy: 'id ASC');
  }

  // --- Accessories (ELATTAR 2.0) ---
  static Future<List<Accessory>> loadAccessories() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.rawQuery('''
      SELECT a.*, c.name as category_name
      FROM accessories a
      LEFT JOIN categories c ON a.category_id = c.id
      ORDER BY a.id DESC
    ''');
    return maps.map((map) {
      final acc = Accessory.fromJson(map);
      acc.categoryName = map['category_name'] as String?;
      return acc;
    }).toList();
  }

  static Future<int> saveAccessory(Accessory accessory) async {
    final database = await db;
    String actionType = 'إضافة';
    String details =
        'الكمية: ${accessory.quantity}، السعر: ${accessory.price}، التكلفة: ${accessory.cost}، المخزن: ${accessory.warehouse}';

    if (accessory.id != null) {
      final List<Map<String, dynamic>> existing = await database.query(
        'accessories',
        where: 'id = ?',
        whereArgs: [accessory.id],
      );
      if (existing.isNotEmpty) {
        actionType = 'تعديل';
        final oldAcc = existing.first;
        List<String> changes = [];
        if (oldAcc['name'] != accessory.name)
          changes.add('الاسم من "${oldAcc['name']}" إلى "${accessory.name}"');
        if (oldAcc['quantity'] != accessory.quantity)
          changes.add(
            'الكمية من ${oldAcc['quantity']} إلى ${accessory.quantity}',
          );
        if (oldAcc['price'] != accessory.price)
          changes.add('السعر من ${oldAcc['price']} إلى ${accessory.price}');
        if (oldAcc['cost'] != accessory.cost)
          changes.add('التكلفة من ${oldAcc['cost']} إلى ${accessory.cost}');
        if (oldAcc['warehouse'] != accessory.warehouse)
          changes.add(
            'المخزن من "${oldAcc['warehouse']}" إلى "${accessory.warehouse}"',
          );
        details = changes.isEmpty
            ? 'تعديل البيانات العامة'
            : changes.join('، ');
      }
    }

    final id = await _insert(
      database,
      'accessories',
      accessory.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await logModification(
      actionType: actionType,
      itemType: 'إكسسوار',
      itemName: accessory.name,
      details: details,
    );

    await syncDatabase();
    return id;
  }

  static Future<void> deleteAccessory(int id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'accessories',
      where: 'id = ?',
      whereArgs: [id],
    );
    String name = 'غير معروف';
    if (maps.isNotEmpty) name = maps.first['name'] as String;

    await database.delete('accessories', where: 'id = ?', whereArgs: [id]);

    await logModification(
      actionType: 'حذف',
      itemType: 'إكسسوار',
      itemName: name,
      details: 'تم حذف الإكسسوار نهائياً من النظام',
    );
    await syncDatabase();
  }

  // --- Devices (ELATTAR 2.0) ---
  static Future<List<Device>> loadDevices() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.rawQuery('''
      SELECT d.*, c.name as category_name
      FROM devices d
      LEFT JOIN categories c ON d.category_id = c.id
      ORDER BY d.id DESC
    ''');
    return maps.map((map) {
      final dev = Device.fromJson(map);
      dev.categoryName = map['category_name'] as String?;
      return dev;
    }).toList();
  }

  static Future<int> saveDevice(Device device) async {
    final database = await db;
    String actionType = 'إضافة';
    String details =
        'الكمية: ${device.quantity}، السعر: ${device.price}، التكلفة: ${device.cost}، المخزن: ${device.warehouse}';

    if (device.id != null) {
      final List<Map<String, dynamic>> existing = await database.query(
        'devices',
        where: 'id = ?',
        whereArgs: [device.id],
      );
      if (existing.isNotEmpty) {
        actionType = 'تعديل';
        final oldDev = existing.first;
        List<String> changes = [];
        if (oldDev['model'] != device.model)
          changes.add('الموديل من "${oldDev['model']}" إلى "${device.model}"');
        if (oldDev['quantity'] != device.quantity)
          changes.add('الكمية من ${oldDev['quantity']} إلى ${device.quantity}');
        if (oldDev['price'] != device.price)
          changes.add('السعر من ${oldDev['price']} إلى ${device.price}');
        if (oldDev['cost'] != device.cost)
          changes.add('التكلفة من ${oldDev['cost']} إلى ${device.cost}');
        if (oldDev['warehouse'] != device.warehouse)
          changes.add(
            'المخزن من "${oldDev['warehouse']}" إلى "${device.warehouse}"',
          );
        details = changes.isEmpty
            ? 'تعديل البيانات العامة'
            : changes.join('، ');
      }
    }

    final id = await _insert(
      database,
      'devices',
      device.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await logModification(
      actionType: actionType,
      itemType: 'جهاز',
      itemName: device.model,
      details: details,
    );

    await syncDatabase();
    return id;
  }

  static Future<void> deleteDevice(int id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'devices',
      where: 'id = ?',
      whereArgs: [id],
    );
    String model = 'غير معروف';
    if (maps.isNotEmpty) model = maps.first['model'] as String;

    await database.delete('devices', where: 'id = ?', whereArgs: [id]);

    await logModification(
      actionType: 'حذف',
      itemType: 'جهاز',
      itemName: model,
      details: 'تم حذف الجهاز نهائياً من النظام',
    );
    await syncDatabase();
  }

  // --- Customers Deferred Payments (ELATTAR 2.0) ---
  static Future<List<DeferredPayment>> loadDeferredPayments() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'deferred_payments',
      orderBy: 'id DESC',
    );
    return maps.map((map) => DeferredPayment.fromJson(map)).toList();
  }

  static Future<int> saveDeferredPayment(DeferredPayment dp) async {
    final database = await db;
    final id = await _insert(
      database,
      'deferred_payments',
      dp.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await syncDatabase();
    return id;
  }

  static Future<void> deleteDeferredPayment(int id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'deferred_payments',
      where: 'id = ?',
      whereArgs: [id],
    );
    String name = 'غير معروف';
    double amount = 0.0;
    if (maps.isNotEmpty) {
      name = maps.first['customerName'] as String;
      amount = (maps.first['remainingAmount'] as num).toDouble();
    }

    await database.delete(
      'deferred_payments',
      where: 'id = ?',
      whereArgs: [id],
    );
    await database.delete(
      'deferred_payments_history',
      where: 'deferredId = ?',
      whereArgs: [id],
    );

    await logModification(
      actionType: 'حذف مديونية',
      itemType: 'حساب آجل عميل',
      itemName: name,
      details: 'تم حذف حساب مديونية بقيمة $amount ج.م',
    );
    await syncDatabase();
  }

  static Future<List<DeferredPaymentHistory>> loadDeferredPaymentHistory(
    int deferredId,
  ) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'deferred_payments_history',
      where: 'deferredId = ?',
      whereArgs: [deferredId],
      orderBy: 'id DESC',
    );
    return maps.map((map) => DeferredPaymentHistory.fromJson(map)).toList();
  }

  static Future<int> addDeferredPaymentHistory(
    DeferredPaymentHistory history,
  ) async {
    final database = await db;
    final id = await _insert(
      database,
      'deferred_payments_history',
      history.toJson(),
    );
    // Update the parent remaining and paid amounts
    final List<Map<String, dynamic>> dpMaps = await database.query(
      'deferred_payments',
      where: 'id = ?',
      whereArgs: [history.deferredId],
    );
    String customerName = 'غير معروف';
    if (dpMaps.isNotEmpty) {
      final dp = DeferredPayment.fromJson(dpMaps.first);
      customerName = dp.customerName;
      final newPaid = dp.paidAmount + history.amountPaid;
      final newRemaining = dp.totalAmount - newPaid;
      await database.update(
        'deferred_payments',
        {'paidAmount': newPaid, 'remainingAmount': newRemaining},
        where: 'id = ?',
        whereArgs: [history.deferredId],
      );
    }

    await logModification(
      actionType: 'سداد دفعة',
      itemType: 'حساب آجل عميل',
      itemName: customerName,
      details:
          'تم سداد دفعة بقيمة ${history.amountPaid} ج.م. ملاحظات: ${history.notes ?? 'لا يوجد'}',
    );

    await syncDatabase();
    return id;
  }

  // --- Suppliers CRUD (ELATTAR 2.0) ---
  static Future<List<Supplier>> loadSuppliers() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'suppliers',
      orderBy: 'id DESC',
    );
    return maps.map((map) => Supplier.fromJson(map)).toList();
  }

  static Future<int> saveSupplier(Supplier supplier) async {
    final database = await db;
    final id = await _insert(
      database,
      'suppliers',
      supplier.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await syncDatabase();
    return id;
  }

  static Future<void> deleteSupplier(int id) async {
    final database = await db;
    await database.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    await syncDatabase();
  }

  // --- Supplier Debts CRUD (ELATTAR 2.0) ---
  static Future<List<SupplierDebt>> loadSupplierDebts() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'supplier_debts',
      orderBy: 'id DESC',
    );
    return maps.map((map) => SupplierDebt.fromJson(map)).toList();
  }

  static Future<int> saveSupplierDebt(SupplierDebt sd) async {
    final database = await db;
    final id = await _insert(
      database,
      'supplier_debts',
      sd.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await syncDatabase();
    return id;
  }

  static Future<void> deleteSupplierDebt(int id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'supplier_debts',
      where: 'id = ?',
      whereArgs: [id],
    );
    String name = 'غير معروف';
    double amount = 0.0;
    if (maps.isNotEmpty) {
      name = maps.first['supplierName'] as String;
      amount = (maps.first['remainingAmount'] as num).toDouble();
    }

    await database.delete('supplier_debts', where: 'id = ?', whereArgs: [id]);
    await database.delete(
      'supplier_payments_history',
      where: 'debtId = ?',
      whereArgs: [id],
    );

    await logModification(
      actionType: 'حذف مديونية مورد',
      itemType: 'حساب آجل مورد',
      itemName: name,
      details: 'تم حذف حساب مديونية مورد بقيمة $amount ج.م',
    );
    await syncDatabase();
  }

  static Future<List<SupplierPaymentHistory>> loadSupplierPaymentHistory(
    int debtId,
  ) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'supplier_payments_history',
      where: 'debtId = ?',
      whereArgs: [debtId],
      orderBy: 'id DESC',
    );
    return maps.map((map) => SupplierPaymentHistory.fromJson(map)).toList();
  }

  static Future<int> addSupplierPaymentHistory(
    SupplierPaymentHistory history,
  ) async {
    final database = await db;
    final id = await _insert(
      database,
      'supplier_payments_history',
      history.toJson(),
    );
    // Update parent SupplierDebt amounts
    final List<Map<String, dynamic>> sdMaps = await database.query(
      'supplier_debts',
      where: 'id = ?',
      whereArgs: [history.debtId],
    );
    String supplierName = 'غير معروف';
    if (sdMaps.isNotEmpty) {
      final sd = SupplierDebt.fromJson(sdMaps.first);
      supplierName = sd.supplierName;
      final newPaid = sd.paidAmount + history.amountPaid;
      final newRemaining = sd.totalAmount - newPaid;
      await database.update(
        'supplier_debts',
        {'paidAmount': newPaid, 'remainingAmount': newRemaining},
        where: 'id = ?',
        whereArgs: [history.debtId],
      );
    }

    await logModification(
      actionType: 'سداد دفعة مورد',
      itemType: 'حساب آجل مورد',
      itemName: supplierName,
      details:
          'تم سداد دفعة للمورد بقيمة ${history.amountPaid} ج.م. ملاحظات: ${history.notes ?? 'لا يوجد'}',
    );

    await syncDatabase();
    return id;
  }

  // --- Goods Receipts (ELATTAR 2.0) ---
  static Future<List<GoodsReceipt>> loadGoodsReceipts() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'goods_receipts',
      orderBy: 'id DESC',
    );
    return maps.map((map) => GoodsReceipt.fromJson(map)).toList();
  }

  static Future<int> saveGoodsReceipt(
    GoodsReceipt receipt, {
    bool isDeferred = false,
    double initialPayment = 0.0,
    String? dueDate,
  }) async {
    final database = await db;
    final id = await _insert(database, 'goods_receipts', receipt.toJson());

    // Increment inventory quantity based on itemType
    if (receipt.itemType == 'spare_part') {
      final List<Map<String, dynamic>> parts = await database.query(
        'spare_parts',
        where: 'name = ?',
        whereArgs: [receipt.itemName],
      );
      if (parts.isNotEmpty) {
        final existingQty = parts.first['quantity'] as int;
        await database.update(
          'spare_parts',
          {'quantity': existingQty + receipt.quantity, 'price': receipt.price},
          where: 'id = ?',
          whereArgs: [parts.first['id']],
        );
      } else {
        // Find next id
        final maxIdResult = await database.rawQuery(
          'SELECT MAX(id) FROM spare_parts',
        );
        int nextId = (maxIdResult.first.values.first as int? ?? 0) + 1;
        await _insert(database, 'spare_parts', {
          'id': nextId,
          'name': receipt.itemName,
          'quantity': receipt.quantity,
          'price': receipt.price,
          'supplier': receipt.supplier,
        });
      }
    } else if (receipt.itemType == 'accessory') {
      final List<Map<String, dynamic>> accs = await database.query(
        'accessories',
        where: 'name = ? AND warehouse = ?',
        whereArgs: [receipt.itemName, receipt.warehouse],
      );
      if (accs.isNotEmpty) {
        final existingQty = accs.first['quantity'] as int;
        await database.update(
          'accessories',
          {
            'quantity': existingQty + receipt.quantity,
            'price': receipt.price,
            'cost': receipt.cost,
            'supplier': receipt.supplier,
          },
          where: 'id = ?',
          whereArgs: [accs.first['id']],
        );
      } else {
        await _insert(database, 'accessories', {
          'name': receipt.itemName,
          'quantity': receipt.quantity,
          'price': receipt.price,
          'cost': receipt.cost,
          'supplier': receipt.supplier,
          'warehouse': receipt.warehouse,
        });
      }
    } else if (receipt.itemType == 'device') {
      final List<Map<String, dynamic>> devs = await database.query(
        'devices',
        where: 'model = ? AND warehouse = ? AND condition = ?',
        whereArgs: [receipt.itemName, receipt.warehouse, 'new'],
      );
      if (devs.isNotEmpty) {
        final existingQty = devs.first['quantity'] as int;
        await database.update(
          'devices',
          {
            'quantity': existingQty + receipt.quantity,
            'price': receipt.price,
            'cost': receipt.cost,
            'supplier': receipt.supplier,
          },
          where: 'id = ?',
          whereArgs: [devs.first['id']],
        );
      } else {
        await _insert(database, 'devices', {
          'model': receipt.itemName,
          'imei': '',
          'condition': 'new',
          'quantity': receipt.quantity,
          'price': receipt.price,
          'cost': receipt.cost,
          'supplier': receipt.supplier,
          'warehouse': receipt.warehouse,
        });
      }
    }

    // Handle Supplier Debt if it is deferred payment
    if (isDeferred &&
        receipt.supplier != null &&
        receipt.supplier!.trim().isNotEmpty) {
      final supplierName = receipt.supplier!.trim();
      final totalDebtVal = receipt.cost * receipt.quantity;
      final remainingDebtVal = totalDebtVal - initialPayment;

      // Find or create supplier
      final List<Map<String, dynamic>> supCheck = await database.query(
        'suppliers',
        where: 'name = ?',
        whereArgs: [supplierName],
      );
      int supId = 0;
      if (supCheck.isEmpty) {
        supId = await _insert(database, 'suppliers', {'name': supplierName});
      } else {
        supId = supCheck.first['id'] as int;
      }

      // Record Supplier Debt
      final debtId = await _insert(database, 'supplier_debts', {
        'supplierId': supId,
        'supplierName': supplierName,
        'totalAmount': totalDebtVal,
        'paidAmount': initialPayment,
        'remainingAmount': remainingDebtVal,
        'dueDate': dueDate,
        'notes':
            'فاتورة توريد تلقائية: ${receipt.itemName} x ${receipt.quantity}',
        'createdDate': receipt.receiptDate,
      });

      if (initialPayment > 0.0) {
        await _insert(database, 'supplier_payments_history', {
          'debtId': debtId,
          'amountPaid': initialPayment,
          'paymentDate': receipt.receiptDate,
          'notes': 'دفعة مقدمة عند التوريد',
        });
      }
    }

    await logModification(
      actionType: 'استلام بضاعة',
      itemType: 'مخزن',
      itemName: receipt.itemName,
      details:
          'استلام كمية ${receipt.quantity} من ${receipt.supplier ?? 'مورد غير معروف'}، تكلفة القطعة: ${receipt.cost} ج.م',
    );
    await syncDatabase();
    return id;
  }

  // --- Inventory Transfers (ELATTAR 2.0) ---
  static Future<List<InventoryTransfer>> loadInventoryTransfers() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'inventory_transfers',
      orderBy: 'id DESC',
    );
    return maps.map((map) => InventoryTransfer.fromJson(map)).toList();
  }

  static Future<int> saveInventoryTransfer(
    InventoryTransfer transfer,
    int sourceItemId,
  ) async {
    final database = await db;

    // 1. Deduct from source warehouse item
    if (transfer.itemType == 'spare_part') {
      // Spare parts are global in original code, so we only update the spare_parts table directly.
      final List<Map<String, dynamic>> parts = await database.query(
        'spare_parts',
        where: 'id = ?',
        whereArgs: [sourceItemId],
      );
      if (parts.isNotEmpty) {
        final existingQty = parts.first['quantity'] as int;
        await database.update(
          'spare_parts',
          {'quantity': existingQty - transfer.quantity},
          where: 'id = ?',
          whereArgs: [sourceItemId],
        );
      }
    } else if (transfer.itemType == 'accessory') {
      final List<Map<String, dynamic>> accs = await database.query(
        'accessories',
        where: 'id = ?',
        whereArgs: [sourceItemId],
      );
      if (accs.isNotEmpty) {
        final srcAcc = Accessory.fromJson(accs.first);
        await database.update(
          'accessories',
          {'quantity': srcAcc.quantity - transfer.quantity},
          where: 'id = ?',
          whereArgs: [sourceItemId],
        );

        // Add to target warehouse
        final List<Map<String, dynamic>> targetAccs = await database.query(
          'accessories',
          where: 'name = ? AND warehouse = ?',
          whereArgs: [srcAcc.name, transfer.toWarehouse],
        );
        if (targetAccs.isNotEmpty) {
          final existingQty = targetAccs.first['quantity'] as int;
          await database.update(
            'accessories',
            {'quantity': existingQty + transfer.quantity},
            where: 'id = ?',
            whereArgs: [targetAccs.first['id']],
          );
        } else {
          await _insert(database, 'accessories', {
            'name': srcAcc.name,
            'quantity': transfer.quantity,
            'price': srcAcc.price,
            'cost': srcAcc.cost,
            'supplier': srcAcc.supplier,
            'warehouse': transfer.toWarehouse,
          });
        }
      }
    } else if (transfer.itemType == 'device') {
      final List<Map<String, dynamic>> devs = await database.query(
        'devices',
        where: 'id = ?',
        whereArgs: [sourceItemId],
      );
      if (devs.isNotEmpty) {
        final srcDev = Device.fromJson(devs.first);
        await database.update(
          'devices',
          {'quantity': srcDev.quantity - transfer.quantity},
          where: 'id = ?',
          whereArgs: [sourceItemId],
        );

        // Add to target warehouse
        final List<Map<String, dynamic>> targetDevs = await database.query(
          'devices',
          where: 'model = ? AND warehouse = ? AND condition = ?',
          whereArgs: [srcDev.model, transfer.toWarehouse, srcDev.condition],
        );
        if (targetDevs.isNotEmpty) {
          final existingQty = targetDevs.first['quantity'] as int;
          await database.update(
            'devices',
            {'quantity': existingQty + transfer.quantity},
            where: 'id = ?',
            whereArgs: [targetDevs.first['id']],
          );
        } else {
          await _insert(database, 'devices', {
            'model': srcDev.model,
            'imei': srcDev.imei,
            'condition': srcDev.condition,
            'quantity': transfer.quantity,
            'price': srcDev.price,
            'cost': srcDev.cost,
            'supplier': srcDev.supplier,
            'warehouse': transfer.toWarehouse,
          });
        }
      }
    }

    final id = await _insert(
      database,
      'inventory_transfers',
      transfer.toJson(),
    );
    await logModification(
      actionType: 'تحويل مخزني',
      itemType: 'مخزن',
      itemName: transfer.itemName,
      details:
          'تحويل ${transfer.quantity} من ${transfer.fromWarehouse} إلى ${transfer.toWarehouse}',
    );
    await syncDatabase();
    return id;
  }

  // --- Inventory Audits CRUD (ELATTAR 2.0) ---
  static Future<List<InventoryAudit>> loadInventoryAudits() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'inventory_audits',
      orderBy: 'id DESC',
    );
    return maps.map((map) => InventoryAudit.fromJson(map)).toList();
  }

  static Future<int> saveInventoryAudit(InventoryAudit audit) async {
    final database = await db;
    final id = await _insert(database, 'inventory_audits', audit.toJson());

    // Adjust actual inventory quantity in db based on the audit
    if (audit.itemType == 'spare_part') {
      await database.rawUpdate(
        'UPDATE spare_parts SET quantity = ? WHERE name = ?',
        [audit.actualQty, audit.itemName],
      );
    } else if (audit.itemType == 'accessory') {
      await database.rawUpdate(
        'UPDATE accessories SET quantity = ? WHERE name = ?',
        [audit.actualQty, audit.itemName],
      );
    } else if (audit.itemType == 'device') {
      await database.rawUpdate(
        'UPDATE devices SET quantity = ? WHERE model = ?',
        [audit.actualQty, audit.itemName],
      );
    }

    await logModification(
      actionType: 'جرد مخزني',
      itemType: 'مخزن',
      itemName: audit.itemName,
      details:
          'المتوقع: ${audit.expectedQty}، الفعلي: ${audit.actualQty}، الفرق: ${audit.difference}',
    );
    await syncDatabase();
    return id;
  }

  // --- Warehouses CRUD (ELATTAR 2.0) ---
  static Future<List<Warehouse>> loadWarehouses() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'warehouses',
      orderBy: 'name ASC',
    );
    return maps.map((map) => Warehouse.fromJson(map)).toList();
  }

  static Future<int> addWarehouse(String name) async {
    final database = await db;
    final id = await _insert(database, 'warehouses', {
      'name': name.trim(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await syncDatabase();
    return id;
  }

  static Future<void> deleteWarehouse(int id) async {
    final database = await db;
    await database.delete('warehouses', where: 'id = ?', whereArgs: [id]);
    await syncDatabase();
  }

  // --- Settings helpers (Theme, Keys, etc.) ---
  static Future<bool?> getIsDarkSetting() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['isDark'],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] == 'true';
    }
    return null;
  }

  static Future<void> saveIsDarkSetting(bool isDark) async {
    final database = await db;
    await database.insert('settings', {
      'key': 'isDark',
      'value': isDark ? 'true' : 'false',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await syncDatabase();
  }

  static Future<String?> getActivationKey() async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['activationKey'],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String?;
      }
    } catch (e) {
      debugPrint('Error getting activation key: $e');
    }
    return null;
  }

  static Future<void> saveActivationKey(String key) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': 'activationKey',
        'value': key,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await syncDatabase();
    } catch (e) {
      debugPrint('Error saving activation key: $e');
    }
  }

  static Future<String?> getClientName() async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['clientName'],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String?;
      }
    } catch (e) {
      debugPrint('Error getting client name: $e');
    }
    return null;
  }

  static Future<void> saveClientName(String name) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': 'clientName',
        'value': name,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await syncDatabase();
    } catch (e) {
      debugPrint('Error saving client name: $e');
    }
  }

  static Future<String?> getClientHwid() async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['clientHwid'],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String?;
      }
    } catch (e) {
      debugPrint('Error getting client HWID: $e');
    }
    return null;
  }

  static Future<void> saveClientHwid(String hwid) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': 'clientHwid',
        'value': hwid,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await syncDatabase();
    } catch (e) {
      debugPrint('Error saving client HWID: $e');
    }
  }

  static Future<String?> getClientEmail() async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['clientEmail'],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String?;
      }
    } catch (e) {
      debugPrint('Error getting client email: $e');
    }
    return null;
  }

  static Future<void> saveClientEmail(String email) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': 'clientEmail',
        'value': email,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await syncDatabase();
    } catch (e) {
      debugPrint('Error saving client email: $e');
    }
  }

  static Future<String?> getClientPasswordHash() async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['clientPasswordHash'],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String?;
      }
    } catch (e) {
      debugPrint('Error getting client password hash: $e');
    }
    return null;
  }

  static Future<void> saveClientPasswordHash(String hash) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': 'clientPasswordHash',
        'value': hash,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await syncDatabase();
    } catch (e) {
      debugPrint('Error saving client password hash: $e');
    }
  }

  static Future<String?> getSetting(String key) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String?;
      }
    } catch (e) {
      debugPrint('Error getting setting $key: $e');
    }
    return null;
  }

  static Future<void> saveSetting(String key, String value) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await syncDatabase();
    } catch (e) {
      debugPrint('Error saving setting $key: $e');
    }
  }

  // --- Categories (ELATTAR 2.0) ---
  static Future<List<Category>> loadCategories(String type) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'categories',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'id ASC',
    );
    return maps.map((map) => Category.fromJson(map)).toList();
  }

  static Future<int> saveCategory(Category category) async {
    final database = await db;
    String actionType = 'إضافة';
    if (category.id != null) {
      actionType = 'تعديل';
    }
    final id = await _insert(
      database,
      'categories',
      category.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await logModification(
      actionType: actionType,
      itemType: 'تصنيف',
      itemName: category.name,
      details:
          'النوع: ${category.type == 'accessory'
              ? 'إكسسوار'
              : category.type == 'spare_part'
              ? 'قطعة غيار'
              : category.type == 'device_brand'
              ? 'ماركة جهاز'
              : 'حالة جهاز'}',
    );
    await syncDatabase();
    return id;
  }

  static Future<void> deleteCategory(int id) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
    String name = 'غير معروف';
    if (maps.isNotEmpty) name = maps.first['name'] as String;

    await database.delete('categories', where: 'id = ?', whereArgs: [id]);
    await logModification(
      actionType: 'حذف',
      itemType: 'تصنيف',
      itemName: name,
      details: 'تم حذف التصنيف نهائياً',
    );
    await syncDatabase();
  }

  // --- Modification Logs ---
  static Future<int> logModification({
    required String actionType,
    required String itemType,
    required String itemName,
    String? details,
  }) async {
    try {
      final database = await db;
      final id = await _insert(database, 'modification_logs', {
        'actionDate': DateTime.now().toIso8601String(),
        'actionType': actionType,
        'itemType': itemType,
        'itemName': itemName,
        'details': details,
      });
      return id;
    } catch (e) {
      debugPrint('Error saving modification log: $e');
      return 0;
    }
  }

  static Future<List<ModificationLog>> loadModificationLogs({
    int limit = 5,
  }) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'modification_logs',
        orderBy: 'id DESC',
        limit: limit,
      );
      return maps.map((map) => ModificationLog.fromJson(map)).toList();
    } catch (e) {
      debugPrint('Error loading modification logs: $e');
      return [];
    }
  }

  /// Check for new attendance logs that haven't been notified yet
  static Future<List<ModificationLog>> checkUnseenAttendanceLogs() async {
    try {
      final database = await db;
      // Get last seen log id from settings
      final lastSeenStr = await getSetting('lastSeenAttendanceLogId');
      final lastSeenId = int.tryParse(lastSeenStr ?? '0') ?? 0;

      final List<Map<String, dynamic>> maps = await database.query(
        'modification_logs',
        where: 'actionType = ? AND id > ?',
        whereArgs: ['attendance', lastSeenId],
        orderBy: 'id ASC',
      );
      return maps.map((map) => ModificationLog.fromJson(map)).toList();
    } catch (e) {
      debugPrint('Error checking unseen attendance logs: $e');
      return [];
    }
  }

  /// Update the last seen attendance log id (marks notifications as seen)
  static Future<void> updateLastSeenAttendanceLogId(int id) async {
    try {
      await saveSetting('lastSeenAttendanceLogId', id.toString());
    } catch (e) {
      debugPrint('Error updating last seen attendance log id: $e');
    }
  }

  // --- AppUsers CRUD ---
  static Future<int> getUsersCount() async {
    try {
      final database = await db;
      final count = _firstIntValue(
        await database.rawQuery('SELECT COUNT(*) FROM users'),
      );
      return count ?? 0;
    } catch (e) {
      debugPrint('Error getting users count: $e');
      return 0;
    }
  }

  static Future<int> saveUser(AppUser user) async {
    try {
      final database = await db;
      user.email = user.email.trim();
      final id = await _insert(
        database,
        'users',
        user.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await syncDatabase();
      return id;
    } catch (e) {
      debugPrint('Error saving user: $e');
      return 0;
    }
  }

  static Future<void> saveRegistrationDetails({
    required String name,
    required String hwid,
    required String email,
    required String passwordHash,
    required AppUser user,
  }) async {
    try {
      final database = await db;
      await database.transaction((txn) async {
        await txn.insert('settings', {
          'key': 'clientName',
          'value': name,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('settings', {
          'key': 'clientHwid',
          'value': hwid,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('settings', {
          'key': 'clientEmail',
          'value': email,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('settings', {
          'key': 'clientPasswordHash',
          'value': passwordHash,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // Save user
        user.email = user.email.trim();
        final mutableValues = Map<String, dynamic>.from(user.toJson());
        if (mutableValues['id'] == null) {
          final result = await txn.rawQuery(
            'SELECT MAX(id) as max_id FROM users',
          );
          int maxId = 0;
          if (result.isNotEmpty && result.first['max_id'] != null) {
            maxId = result.first['max_id'] as int;
          }
          mutableValues['id'] = generateNextIdFromMax(maxId);
        }
        await txn.insert(
          'users',
          mutableValues,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
      await syncDatabase();
      debugPrint(
        'Atomic save and sync of registration details completed successfully.',
      );
    } catch (e) {
      debugPrint('Error saving registration details: $e');
      rethrow;
    }
  }

  static Future<void> saveClientCredentials({
    required String email,
    required String passwordHash,
    required String name,
  }) async {
    try {
      final database = await db;
      await database.transaction((txn) async {
        await txn.insert('settings', {
          'key': 'clientEmail',
          'value': email,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('settings', {
          'key': 'clientPasswordHash',
          'value': passwordHash,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('settings', {
          'key': 'clientName',
          'value': name,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
      await syncDatabase();
      debugPrint(
        'Atomic save and sync of client credentials completed successfully.',
      );
    } catch (e) {
      debugPrint('Error saving client credentials: $e');
    }
  }

  static Future<AppUser?> getUserByEmail(String email) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'users',
        where: 'email = ?',
        whereArgs: [email.trim()],
      );
      if (maps.isNotEmpty) {
        return AppUser.fromJson(maps.first);
      }
    } catch (e) {
      debugPrint('Error getting user by email: $e');
    }
    return null;
  }

  static Future<List<AppUser>> loadUsers() async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'users',
        orderBy: 'id ASC',
      );
      return maps.map((map) => AppUser.fromJson(map)).toList();
    } catch (e) {
      debugPrint('Error loading users: $e');
      return [];
    }
  }

  static Future<void> deleteUser(int id) async {
    try {
      final database = await db;
      await database.delete('users', where: 'id = ?', whereArgs: [id]);
      await syncDatabase();
    } catch (e) {
      debugPrint('Error deleting user: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ATTENDANCE CRUD (Check-in/Check-out)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check-in a user for today
  static Future<Attendance?> checkIn(
    String userName,
    String userRole, {
    int? userId,
    String? notes,
  }) async {
    try {
      final database = await db;
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final nowStr = now.toIso8601String();

      // Check if already checked in today
      final existing = await database.query(
        'attendance',
        where: 'userName = ? AND date = ?',
        whereArgs: [userName, today],
      );
      if (existing.isNotEmpty) {
        final record = Attendance.fromJson(existing.first);
        if (record.checkOut != null) {
          // If they checked out but want to check in again:
          // Reset checkOut to null, update checkIn to now, and update status
          final hour = now.hour;
          final minute = now.minute;
          final status = (hour > 9 || (hour == 9 && minute > 30))
              ? 'late'
              : 'present';

          await database.update(
            'attendance',
            {'checkIn': nowStr, 'checkOut': null, 'status': status},
            where: 'id = ?',
            whereArgs: [record.id],
          );

          await syncDatabase();

          // Log the re-checkin
          await logModification(
            actionType: 'attendance',
            itemType: 'حضور',
            itemName: userName,
            details: 'إعادة تسجيل حضور للمستخدم: $userName',
          );

          return Attendance(
            id: record.id,
            userId: userId ?? record.userId,
            userName: userName,
            userRole: userRole,
            date: today,
            checkIn: nowStr,
            checkOut: null,
            status: status,
            notes: record.notes,
          );
        }
        return record;
      }

      // Determine status based on check-in time (after 9:30 AM = late)
      final hour = now.hour;
      final minute = now.minute;
      final status = (hour > 9 || (hour == 9 && minute > 30))
          ? 'late'
          : 'present';

      final id = await database.insert('attendance', {
        if (userId != null) 'userId': userId,
        'userName': userName,
        'userRole': userRole,
        'date': today,
        'checkIn': nowStr,
        'status': status,
        if (notes != null) 'notes': notes,
      });
      await syncDatabase();

      // Log the check-in
      await logModification(
        actionType: 'attendance',
        itemType: 'حضور',
        itemName: userName,
        details: 'تسجيل حضور للمستخدم: $userName',
      );

      return Attendance(
        id: id,
        userId: userId,
        userName: userName,
        userRole: userRole,
        date: today,
        checkIn: nowStr,
        status: status,
        notes: notes,
      );
    } catch (e) {
      debugPrint('Error checking in: $e');
      return null;
    }
  }

  /// Check-out a user for today
  static Future<bool> checkOut(String userName) async {
    try {
      final database = await db;
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final nowStr = now.toIso8601String();

      final count = await database.update(
        'attendance',
        {'checkOut': nowStr},
        where: 'userName = ? AND date = ? AND checkOut IS NULL',
        whereArgs: [userName, today],
      );
      await syncDatabase();

      if (count > 0) {
        // Log the check-out
        await logModification(
          actionType: 'attendance',
          itemType: 'انصراف',
          itemName: userName,
          details: 'تسجيل انصراف للمستخدم: $userName',
        );
      }

      return count > 0;
    } catch (e) {
      debugPrint('Error checking out: $e');
      return false;
    }
  }

  /// Get today's attendance records
  static Future<List<Attendance>> getTodayAttendance() async {
    try {
      final database = await db;
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final List<Map<String, dynamic>> maps = await database.query(
        'attendance',
        where: 'date = ?',
        whereArgs: [today],
        orderBy: 'checkIn ASC',
      );
      return maps.map((map) => Attendance.fromJson(map)).toList();
    } catch (e) {
      debugPrint('Error getting today attendance: $e');
      return [];
    }
  }

  /// Get attendance records by date range
  static Future<List<Attendance>> getAttendanceByDateRange(
    String startDate,
    String endDate,
  ) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'attendance',
        where: 'date >= ? AND date <= ?',
        whereArgs: [startDate, endDate],
        orderBy: 'date DESC, checkIn ASC',
      );
      return maps.map((map) => Attendance.fromJson(map)).toList();
    } catch (e) {
      debugPrint('Error getting attendance by date range: $e');
      return [];
    }
  }

  /// Get all attendance records for a specific user
  static Future<List<Attendance>> getAttendanceByUser(String userName) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'attendance',
        where: 'userName = ?',
        whereArgs: [userName],
        orderBy: 'date DESC',
      );
      return maps.map((map) => Attendance.fromJson(map)).toList();
    } catch (e) {
      debugPrint('Error getting attendance by user: $e');
      return [];
    }
  }

  /// Get attendance record for a specific user on a specific date (with email/name fallback)
  static Future<Attendance?> getAttendanceByUserAndDate(
    String userName,
    String date,
  ) async {
    try {
      final database = await db;

      // 1. Try direct match
      final List<Map<String, dynamic>> maps = await database.query(
        'attendance',
        where: 'userName = ? AND date = ?',
        whereArgs: [userName, date],
      );
      if (maps.isNotEmpty) {
        return Attendance.fromJson(maps.first);
      }

      // 2. Fallback: If no direct match, check if there is a match under the other signature (email vs name)
      // Look up in the technicians table
      final List<Map<String, dynamic>> techMaps = await database.query(
        'technicians',
        where: 'LOWER(name) = ? OR LOWER(email) = ?',
        whereArgs: [
          userName.trim().toLowerCase(),
          userName.trim().toLowerCase(),
        ],
      );

      if (techMaps.isNotEmpty) {
        final tech = techMaps.first;
        final name = tech['name'] as String?;
        final email = tech['email'] as String?;

        final List<String> searchNames = [];
        if (name != null && name.isNotEmpty)
          searchNames.add(name.trim().toLowerCase());
        if (email != null && email.isNotEmpty)
          searchNames.add(email.trim().toLowerCase());

        if (searchNames.isNotEmpty) {
          final List<Map<String, dynamic>> fallbackMaps = await database.query(
            'attendance',
            where: 'date = ? AND (LOWER(userName) = ? OR LOWER(userName) = ?)',
            whereArgs: [
              date,
              searchNames.first,
              searchNames.length > 1 ? searchNames[1] : searchNames.first,
            ],
          );
          if (fallbackMaps.isNotEmpty) {
            return Attendance.fromJson(fallbackMaps.first);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting attendance by user and date: $e');
      return null;
    }
  }

  /// Update an attendance record (admin edit)
  static Future<bool> updateAttendance(Attendance record) async {
    try {
      final database = await db;
      await database.update(
        'attendance',
        record.toJson(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
      await syncDatabase();
      return true;
    } catch (e) {
      debugPrint('Error updating attendance: $e');
      return false;
    }
  }

  /// Delete an attendance record
  static Future<bool> deleteAttendance(int id) async {
    try {
      final database = await db;
      await database.delete('attendance', where: 'id = ?', whereArgs: [id]);
      await syncDatabase();
      return true;
    } catch (e) {
      debugPrint('Error deleting attendance: $e');
      return false;
    }
  }

  /// Get attendance summary/stats for a date range
  static Future<Map<String, dynamic>> getAttendanceStats(
    String startDate,
    String endDate,
  ) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> records = await database.query(
        'attendance',
        where: 'date >= ? AND date <= ?',
        whereArgs: [startDate, endDate],
      );
      int present = 0, late = 0, absent = 0, halfDay = 0;
      final uniqueDays = <String>{};
      final uniqueUsers = <String>{};
      for (var r in records) {
        uniqueDays.add(r['date'] as String);
        uniqueUsers.add(r['userName'] as String);
        switch (r['status'] as String) {
          case 'present':
            present++;
            break;
          case 'late':
            late++;
            break;
          case 'absent':
            absent++;
            break;
          case 'half_day':
            halfDay++;
            break;
        }
      }
      return {
        'totalDays': uniqueDays.length,
        'totalUsers': uniqueUsers.length,
        'totalRecords': records.length,
        'present': present,
        'late': late,
        'absent': absent,
        'halfDay': halfDay,
      };
    } catch (e) {
      debugPrint('Error getting attendance stats: $e');
      return {
        'totalDays': 0,
        'totalUsers': 0,
        'totalRecords': 0,
        'present': 0,
        'late': 0,
        'absent': 0,
        'halfDay': 0,
      };
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  MULTI-BRANCH MANAGEMENT (branches_config.json)
  // ═══════════════════════════════════════════════════════════════════════════

  static BranchesConfig? _branchesConfig;
  static const String _branchesConfigName = 'branches_config.json';

  /// Path to branches_config.json (same directory as the database)
  static String get _branchesConfigPath {
    return '${getDbDir()}\\$_branchesConfigName';
  }

  /// Initialize the branches configuration.
  /// Called once at startup from [init]. Idempotent.
  static Future<void> initBranches() async {
    if (_branchesConfig != null) return;

    final configFile = File(_branchesConfigPath);
    final dbDir = getDbDir();
    await Directory(dbDir).create(recursive: true);

    if (configFile.existsSync()) {
      try {
        final content = configFile.readAsStringSync();
        final json = jsonDecode(content);
        _branchesConfig = BranchesConfig.fromJson(json);
        if (_branchesConfig!.branches.isEmpty) {
          _branchesConfig = await _createDefaultBranchConfig();
        }
      } catch (e) {
        debugPrint('Error reading branches_config.json: $e');
        _branchesConfig = await _createDefaultBranchConfig();
      }
    } else {
      _branchesConfig = await _createDefaultBranchConfig();
    }

    // Auto-update from sync_config.json if anything has changed
    try {
      final syncConfig = await _loadSyncConfig();
      if (syncConfig != null && _branchesConfig != null) {
        final syncRepoUrl = syncConfig['repo_url'];
        final syncBranchCode = syncConfig['branch_name'] ?? 'main';
        final syncStoreName = syncConfig['store_name'] ?? 'ELATTAR Store';
        final syncStoreEmail = syncConfig['store_email'] ?? 'store@example.com';
        final syncMachineId = int.tryParse(syncConfig['machine_id'] ?? '') ?? 1;

        if (syncRepoUrl != null && syncRepoUrl.isNotEmpty) {
          StoreBranch? targetBranch;
          final matchingBranches = _branchesConfig!.branches
              .where((b) => b.code == syncBranchCode)
              .toList();
          if (matchingBranches.isNotEmpty) {
            targetBranch = matchingBranches.first;
          } else {
            targetBranch =
                _branchesConfig!.currentBranch ??
                (_branchesConfig!.branches.isNotEmpty
                    ? _branchesConfig!.branches.first
                    : null);
          }

          if (targetBranch != null) {
            bool hasChanges = false;
            String? newRepoUrl = targetBranch.repoUrl;
            String? newGitBranchName = targetBranch.gitBranchName;
            String? newStoreName = targetBranch.storeName;
            String? newStoreEmail = targetBranch.storeEmail;
            int newMachineId = targetBranch.machineId;

            if (targetBranch.repoUrl != syncRepoUrl) {
              newRepoUrl = syncRepoUrl;
              hasChanges = true;
            }
            if (targetBranch.gitBranchName != syncBranchCode) {
              newGitBranchName = syncBranchCode;
              hasChanges = true;
            }
            if (targetBranch.storeName != syncStoreName) {
              newStoreName = syncStoreName;
              hasChanges = true;
            }
            if (targetBranch.storeEmail != syncStoreEmail) {
              newStoreEmail = syncStoreEmail;
              hasChanges = true;
            }
            if (targetBranch.machineId != syncMachineId) {
              newMachineId = syncMachineId;
              hasChanges = true;
            }

            if (hasChanges) {
              debugPrint(
                'DatabaseHelper: Detected updated config in sync_config.json. Updating branches_config.json...',
              );
              final updatedBranch = targetBranch.copyWith(
                repoUrl: newRepoUrl,
                gitBranchName: newGitBranchName,
                storeName: newStoreName,
                storeEmail: newStoreEmail,
                machineId: newMachineId,
              );

              final index = _branchesConfig!.branches.indexWhere(
                (b) => b.id == targetBranch!.id,
              );
              if (index != -1) {
                _branchesConfig!.branches[index] = updatedBranch;
                await _saveBranchesConfig();
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint(
        'Error auto-updating branches config from sync_config.json: $e',
      );
    }

    // Set machineId from current branch
    final branch = _branchesConfig!.currentBranch;
    if (branch != null) {
      machineId = branch.machineId;
    }
  }

  /// Create a default BranchesConfig from sync_config.json (backward compat).
  static Future<BranchesConfig> _createDefaultBranchConfig() async {
    final syncConfig = await _loadSyncConfig();

    if (syncConfig != null) {
      final defaultBranch = StoreBranch(
        id: 1,
        name: syncConfig['store_name'] ?? 'ELATTAR Store',
        code: syncConfig['branch_name'] ?? 'main',
        machineId: int.tryParse(syncConfig['machine_id'] ?? '') ?? 1,
        dbFileName: _dbName,
        repoUrl: syncConfig['repo_url'],
        gitBranchName: syncConfig['branch_name'],
        storeName: syncConfig['store_name'],
        storeEmail: syncConfig['store_email'],
      );
      final config = BranchesConfig(
        currentBranchId: 1,
        branches: [defaultBranch],
      );
      await _saveBranchesConfig(config);
      return config;
    }

    // No sync_config.json either → create a single default branch
    final defaultBranch = StoreBranch(
      id: 1,
      name: 'الفرع الرئيسي',
      code: 'main',
      machineId: 1,
      dbFileName: _dbName,
    );
    final config = BranchesConfig(
      currentBranchId: 1,
      branches: [defaultBranch],
    );
    await _saveBranchesConfig(config);
    return config;
  }

  /// Persist the current (or given) branches config to disk.
  static Future<void> _saveBranchesConfig([BranchesConfig? config]) async {
    config ??= _branchesConfig;
    if (config == null) return;
    final file = File(_branchesConfigPath);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  /// Return the currently configured BranchesConfig.
  static Future<BranchesConfig> getBranchesConfig() async {
    if (_branchesConfig == null) await initBranches();
    return _branchesConfig!;
  }

  /// The currently active StoreBranch, or null if not initialised.
  static StoreBranch? get currentBranch => _branchesConfig?.currentBranch;

  /// Load the list of all registered branches.
  static Future<List<StoreBranch>> loadBranches() async {
    final config = await getBranchesConfig();
    return List.from(config.branches);
  }

  /// Add a new branch to the configuration.
  static Future<void> addBranch(StoreBranch branch) async {
    final config = await getBranchesConfig();
    config.branches.add(branch);
    await _saveBranchesConfig(config);
  }

  /// Update an existing branch's metadata.
  static Future<void> updateBranch(StoreBranch branch) async {
    final config = await getBranchesConfig();
    final index = config.branches.indexWhere((b) => b.id == branch.id);
    if (index != -1) {
      config.branches[index] = branch;
      await _saveBranchesConfig(config);
    }
  }

  /// Remove a branch. If it is the current branch, switches to the first
  /// remaining branch.
  static Future<void> deleteBranch(int branchId) async {
    final config = await getBranchesConfig();
    config.branches.removeWhere((b) => b.id == branchId);
    if (config.currentBranchId == branchId) {
      config.currentBranchId = config.branches.isNotEmpty
          ? config.branches.first.id
          : 1;
    }
    await _saveBranchesConfig(config);

    // If the deleted branch was the current one, reload
    if (_branchesConfig?.currentBranchId == branchId) {
      _branchesConfig = config;
    }
  }

  /// Switch to a different branch.
  /// Closes the current database connection and opens the new branch's DB.
  static Future<void> switchBranch(int branchId) async {
    final config = await getBranchesConfig();
    final branch = config.branches.firstWhere(
      (b) => b.id == branchId,
      orElse: () => throw Exception('Branch #$branchId not found'),
    );

    // Close current DB
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
    dbConnectionError = null;

    // Update config
    config.currentBranchId = branchId;
    _branchesConfig = config;
    machineId = branch.machineId;
    await _saveBranchesConfig(config);

    // Re-initialise with the new branch's database
    _db = await init();
  }

  /// Generate the next available branch ID (max existing + 1).
  static Future<int> nextBranchId() async {
    final config = await getBranchesConfig();
    if (config.branches.isEmpty) return 1;
    return config.branches.map((b) => b.id).reduce((a, b) => a > b ? a : b) + 1;
  }
}
