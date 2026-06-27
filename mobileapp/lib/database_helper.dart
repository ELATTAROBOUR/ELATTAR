import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

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

  static bool _isSyncing = false;
  static bool _syncPending = false;

  static Set<int> _loadedTicketIds = {};
  static Set<int> _loadedSparePartIds = {};
  static Set<String> _loadedTechnicianNames = {};

  static String complaintNumber = '01000361006';
  static int machineId = 2; // Default to 2 for mobile app

  static Map<String, String>? _cachedConfig;

  static Future<Map<String, String>?> loadSyncConfig() async {
    if (_cachedConfig != null) return _cachedConfig;
    try {
      final jsonStr = await rootBundle.loadString('assets/sync_config.json');
      final data = jsonDecode(jsonStr);
      _cachedConfig = {
        'repo_url': data['repo_url']?.toString() ?? '',
        'branch_name': data['branch_name']?.toString() ?? 'main',
        'store_email': data['store_email']?.toString() ?? 'store@example.com',
        'store_name': data['store_name']?.toString() ?? 'ELATTAR Store',
        'machine_id': data['machine_id']?.toString() ?? '2',
        'supabase_url': data['supabase_url']?.toString() ?? '',
        'supabase_anon_key': data['supabase_anon_key']?.toString() ?? '',
      };
      return _cachedConfig;
    } catch (e) {
      debugPrint('Error loading sync_config.json from assets: $e');
      return null;
    }
  }

  static Future<Map<String, String>?> _loadSyncConfig() => loadSyncConfig();

  static Future<void> loadMachineId() async {
    try {
      final config = await _loadSyncConfig();
      if (config != null && config['machine_id'] != null) {
        machineId = int.tryParse(config['machine_id']!) ?? 2;
        debugPrint('Loaded Machine ID: $machineId');
      } else {
        machineId = 2;
        debugPrint('Using default Machine ID: $machineId');
      }
    } catch (e) {
      debugPrint('Error loading machine ID: $e');
      machineId = 2;
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

  static Future<String> getDbDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await init();
    return _db!;
  }

  static Future<void> reset() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
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

  // Startup Sync: Initialize Supabase and run sync
  static Future<void> performStartupSync() async {
    debugPrint('Startup Sync: Starting Supabase synchronization...');
    await syncDatabase();
  }

  // Runtime Sync: Bidirectional offline-first Supabase sync
  static Future<void> syncDatabase() async {
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
        Future.delayed(const Duration(seconds: 3), syncDatabase);
      }
    }
  }

  /// Directly update a ticket's status in Supabase (primary source of truth).
  /// Returns true on success, false if offline or any error occurs.
  static Future<bool> updateTicketStatusInSupabase(
    int ticketId,
    String newStatus,
    int updatedAt,
  ) async {
    try {
      final config = await loadSyncConfig();
      if (config == null) return false;
      final url = config['supabase_url'];
      final anonKey = config['supabase_anon_key'];
      if (url == null ||
          url.isEmpty ||
          url == 'YOUR_SUPABASE_URL' ||
          anonKey == null ||
          anonKey.isEmpty ||
          anonKey == 'YOUR_SUPABASE_ANON_KEY') {
        return false;
      }

      // Initialize Supabase client if not already initialized
      try {
        Supabase.instance.client;
      } catch (_) {
        await Supabase.initialize(url: url, anonKey: anonKey);
      }

      final client = Supabase.instance.client;

      // Direct update in Supabase (primary source of truth for status)
      await client
          .from('tickets')
          .update({'status': newStatus, 'updatedAt': updatedAt})
          .eq('id', ticketId);

      debugPrint(
        'Direct Supabase update: Ticket $ticketId status -> $newStatus',
      );
      return true;
    } catch (e) {
      debugPrint('Direct Supabase update failed (offline?): $e');
      return false;
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

  static Future<void> _publishSyncPing() async {
    try {
      final response = await http
          .post(
            Uri.parse('https://ntfy.sh/elattar_sync_obourdist_9f70cb7a'),
            headers: {'Title': 'Sync', 'Priority': 'min'},
            body: 'mobile',
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        debugPrint('Sync Ping: Successfully sent mobile sync ping.');
      } else {
        debugPrint('Sync Ping: Failed to send ping: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Sync Ping: Error sending ping: $e');
    }
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

  static Future<bool> importDatabase(String sourcePath) async {
    try {
      final file = File(sourcePath);
      if (await file.exists()) {
        final dbDir = await getDbDir();
        final dbFile = File('$dbDir\\$_dbName');
        await file.copy(dbFile.path);
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
    final dbDir = await getDbDir();
    final dbPath = p.join(dbDir, _dbName);

    final databaseInstance = await openDatabase(
      dbPath,
      version: 17,
      onOpen: (db) async {
        try {
          // Disable WAL mode so that all writes go directly to the .db file.
          // This is critical because our file-based sync reads the .db file directly.
          await db.execute('PRAGMA journal_mode = DELETE');
          debugPrint('SQLite journal mode set to DELETE successfully');
        } catch (e) {
          debugPrint('Error disabling WAL mode: $e');
        }

        // Self-Healing: Ensure returns table exists in SQLite on mobile
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
          await db.execute('ALTER TABLE tickets ADD COLUMN updatedAt INTEGER');
          debugPrint('Self-Healing: Added updatedAt column to tickets');
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
        if (oldVersion < 12) {
          try {
            await db.execute(
              'ALTER TABLE technicians ADD COLUMN mobilePasswordHash TEXT',
            );
          } catch (e) {
            // Column may already exist (e.g. from desktop database)
            debugPrint('Migration 12 (mobilePasswordHash) maybe skipped: $e');
          }
        }
        if (oldVersion < 13) {
          try {
            await db.execute("ALTER TABLE technicians ADD COLUMN email TEXT");
          } catch (e) {
            debugPrint('Migration 13 (email) maybe skipped: $e');
          }
        }
        if (oldVersion < 14) {
          try {
            await db.execute("ALTER TABLE users ADD COLUMN name TEXT");
          } catch (e) {
            debugPrint('Migration 14 (name) maybe skipped: $e');
          }
        }
        if (oldVersion < 15) {
          try {
            await db.execute("ALTER TABLE tickets ADD COLUMN agent TEXT");
          } catch (e) {
            debugPrint('Migration 15 (agent) maybe skipped: $e');
          }
        }
        if (oldVersion < 16) {
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
            debugPrint('Migration 16 (attendance table) failed/skipped: $e');
          }
        }
        if (oldVersion < 17) {
          try {
            await db.execute(
              'ALTER TABLE tickets ADD COLUMN updatedAt INTEGER',
            );
            debugPrint('Migration 17: Added updatedAt column to tickets');
          } catch (e) {
            debugPrint('Migration 17 (updatedAt) maybe skipped: $e');
          }
        }
      },
    );
    _db = databaseInstance;
    Future.microtask(() => performStartupSync());
    return databaseInstance;
  }

  // --- Tickets ---
  static Future<List<Ticket>> loadTickets() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'tickets',
      orderBy: 'id DESC',
    );
    return maps.map((map) => Ticket.fromJson(map)).toList();
  }

  static Future<void> saveTicket(Ticket ticket) async {
    final database = await db;
    final map = ticket.toJson();
    await database.insert(
      'tickets',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await syncDatabase();
  }

  static Future<void> saveTickets(List<Ticket> ticketsList) async {
    final database = await db;
    final batch = database.batch();

    // 1. Get existing tickets currently in the database to detect deletions
    final existingTickets = await loadTickets();
    final existingIds = existingTickets.map((t) => t.id).toSet();
    final listIds = ticketsList.map((t) => t.id).toSet();

    // Deletes: items in existingIds but not in listIds and belong to loaded partition
    final toDelete = existingIds
        .difference(listIds)
        .intersection(_loadedTicketIds);

    for (var id in toDelete) {
      batch.delete('tickets', where: 'id = ?', whereArgs: [id]);
    }

    // 2. Perform insert/update for items in list
    for (var ticket in ticketsList) {
      batch.insert(
        'tickets',
        ticket.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);

    // Refresh tracking set
    _loadedTicketIds = listIds;

    await syncDatabase();
  }

  static Future<void> deleteTicket(int id) async {
    final database = await db;
    await database.delete('tickets', where: 'id = ?', whereArgs: [id]);
    _loadedTicketIds.remove(id);
    await syncDatabase();
  }

  // --- Spare Parts ---
  static Future<List<SparePart>> loadSpareParts() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'spare_parts',
      orderBy: 'id DESC',
    );

    final List<Map<String, dynamic>> categories = await database.query(
      'categories',
    );
    final Map<int, String> categoryMap = {
      for (var cat in categories) cat['id'] as int: cat['name'] as String,
    };

    final list = maps.map((map) {
      final part = SparePart.fromJson(map);
      if (part.categoryId != null) {
        part.categoryName = categoryMap[part.categoryId];
      }
      return part;
    }).toList();

    _loadedSparePartIds = list.map((p) => p.id).toSet();
    return list;
  }

  static Future<void> saveSparePart(SparePart part) async {
    final database = await db;
    await _insert(
      database,
      'spare_parts',
      part.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await syncDatabase();
  }

  static Future<void> saveSpareParts(List<SparePart> list) async {
    final database = await db;
    final batch = database.batch();

    final existingParts = await loadSpareParts();
    final existingIds = existingParts.map((p) => p.id).toSet();
    final listIds = list.map((p) => p.id).toSet();

    final toDelete = existingIds
        .difference(listIds)
        .intersection(_loadedSparePartIds);

    for (var id in toDelete) {
      batch.delete('spare_parts', where: 'id = ?', whereArgs: [id]);
    }

    for (var part in list) {
      final map = part.toJson();
      if (map['id'] == null) {
        final generatedId = await _generateNextId(database, 'spare_parts');
        map['id'] = generatedId;
        part.id = generatedId;
      }
      batch.insert(
        'spare_parts',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    _loadedSparePartIds = listIds;
    await syncDatabase();
  }

  static Future<void> deleteSparePart(int id) async {
    final database = await db;
    await database.delete('spare_parts', where: 'id = ?', whereArgs: [id]);
    _loadedSparePartIds.remove(id);
    await syncDatabase();
  }

  // --- Technicians ---
  static Future<List<Map<String, String>>> loadTechnicians() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query('technicians');
    final list = maps
        .map(
          (map) => {
            'name': (map['name'] as String?) ?? '',
            'phone': (map['phone'] as String?) ?? '',
            'email': (map['email'] as String?) ?? '',
            'mobilePasswordHash': (map['mobilePasswordHash'] as String?) ?? '',
          },
        )
        .toList();
    _loadedTechnicianNames = list.map((t) => t['name']!).toSet();
    return list;
  }

  static Future<void> saveTechnicians(List<Map<String, String>> list) async {
    final database = await db;
    final batch = database.batch();

    final existingTechs = await loadTechnicians();
    final existingNames = existingTechs.map((t) => t['name']!).toSet();
    final listNames = list.map((t) => t['name']!).toSet();

    final toDelete = existingNames
        .difference(listNames)
        .intersection(_loadedTechnicianNames);

    for (var name in toDelete) {
      batch.delete('technicians', where: 'name = ?', whereArgs: [name]);
    }

    for (var tech in list) {
      final insertData = <String, dynamic>{
        'name': tech['name'],
        'phone': tech['phone'],
      };
      if (tech['email'] != null && tech['email']!.isNotEmpty) {
        insertData['email'] = tech['email'];
      }
      if (tech['mobilePasswordHash'] != null &&
          tech['mobilePasswordHash']!.isNotEmpty) {
        insertData['mobilePasswordHash'] = tech['mobilePasswordHash'];
      }
      batch.insert(
        'technicians',
        insertData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    _loadedTechnicianNames = listNames;
    await syncDatabase();
  }

  // --- Categories ---
  static Future<List<Category>> loadCategories(String type) async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'categories',
      where: 'type = ?',
      whereArgs: [type],
    );
    return maps.map((m) => Category.fromJson(m)).toList();
  }

  // --- Warehouses (for repairs and used device intake) ---
  static Future<List<Warehouse>> loadWarehouses() async {
    final database = await db;
    final List<Map<String, dynamic>> maps = await database.query(
      'warehouses',
      orderBy: 'name ASC',
    );
    return maps.map((map) => Warehouse.fromJson(map)).toList();
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

  // --- Modification Logs ---
  static Future<void> logModification({
    required String actionType,
    required String itemType,
    required String itemName,
    String? details,
  }) async {
    try {
      final database = await db;
      final log = ModificationLog(
        actionDate: DateTime.now().toIso8601String(),
        actionType: actionType,
        itemType: itemType,
        itemName: itemName,
        details: details,
      );
      await _insert(database, 'modification_logs', log.toJson());
    } catch (e) {
      debugPrint('Error writing modification log: $e');
    }
  }

  // --- Settings ---
  static Future<String?> getSetting(String key) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'settings',
        where: 'key = ?',
        whereArgs: [key],
      );
      if (maps.isNotEmpty) {
        return maps.first['value'] as String;
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveSetting(String key, String value) async {
    try {
      final database = await db;
      await database.insert('settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('Error saving setting $key: $e');
    }
  }

  // --- Activation Keys & License Gate settings ---

  /// Returns a File reference to the persistent license backup file.
  /// Tries external storage first (survives uninstall on many devices),
  /// then falls back to app documents directory (covered by Auto Backup).
  static Future<File?> _getLicenseFile() async {
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return File('${externalDir.path}/.elattar_license');
      }
    } catch (_) {}
    try {
      final docDir = await getApplicationDocumentsDirectory();
      return File('${docDir.path}/.elattar_license');
    } catch (_) {}
    try {
      return File('/storage/emulated/0/Android/.elattar_license');
    } catch (_) {}
    return null;
  }

  static Future<String?> getActivationKey() async {
    var key = await getSetting('activationKey');
    if (key == null || key.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        key = prefs.getString('activationKey');
      } catch (_) {}
    }

    // If still not found, check the persistent external file backup
    if (key == null || key.isEmpty) {
      try {
        final file = await _getLicenseFile();
        if (file != null && await file.exists()) {
          key = await file.readAsString();
          key = key.trim();
          if (key.isNotEmpty) {
            // Restore to DB and SharedPreferences
            await saveSetting('activationKey', key);
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('activationKey', key);
            } catch (_) {}
          } else {
            key = null;
          }
        }
      } catch (_) {}
    }

    return key;
  }

  static Future<void> saveActivationKey(String key) async {
    await saveSetting('activationKey', key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('activationKey', key);
    } catch (_) {}

    // Also save to persistent external file for backup across reinstalls
    try {
      final file = await _getLicenseFile();
      if (file != null) {
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        await file.writeAsString(key);
      }
    } catch (_) {}
  }

  static Future<String?> getClientEmail() async {
    return await getSetting('clientEmail');
  }

  static Future<void> saveClientEmail(String email) async {
    await saveSetting('clientEmail', email);
  }

  static Future<String?> getClientPasswordHash() async {
    return await getSetting('clientPasswordHash');
  }

  static Future<void> saveClientPasswordHash(String hash) async {
    await saveSetting('clientPasswordHash', hash);
  }

  static Future<void> saveClientName(String name) async {
    await saveSetting('clientName', name);
  }

  static Future<String?> getClientName() async {
    return await getSetting('clientName');
  }

  static Future<void> saveClientHwid(String hwid) async {
    await saveSetting('clientHwid', hwid);
  }

  static Future<AppUser?> authenticateUser(
    String email,
    String passwordHash,
  ) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'users',
        where: 'email = ? AND passwordHash = ?',
        whereArgs: [email, passwordHash],
      );
      if (maps.isNotEmpty) {
        return AppUser.fromJson(maps.first);
      }
    } catch (e) {
      debugPrint('Error authenticating user: $e');
    }
    return null;
  }

  static Future<void> saveUser(AppUser user) async {
    try {
      final database = await db;
      await database.insert(
        'users',
        user.toJson(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Error saving user: $e');
    }
  }

  static Future<AppUser?> getUserByEmail(String email) async {
    try {
      final database = await db;
      final List<Map<String, dynamic>> maps = await database.query(
        'users',
        where: 'LOWER(email) = ?',
        whereArgs: [email.trim().toLowerCase()],
      );
      if (maps.isNotEmpty) {
        final user = AppUser.fromJson(maps.first);
        if (user.role == 'technician' &&
            (user.name == null || user.name!.trim().isEmpty)) {
          try {
            final List<Map<String, dynamic>> techMaps = await database.query(
              'technicians',
              where: 'LOWER(email) = ?',
              whereArgs: [email.trim().toLowerCase()],
            );
            if (techMaps.isNotEmpty) {
              user.name = techMaps.first['name'] as String?;
            }
          } catch (_) {}
        }
        return user;
      }
    } catch (e) {
      debugPrint('Error getting user by email: $e');
    }
    return null;
  }

  static Future<bool?> getIsDarkSetting() async {
    final val = await getSetting('isDarkTheme');
    if (val != null) {
      return val == 'true';
    }
    return null;
  }

  static Future<void> saveIsDarkSetting(bool isDark) async {
    await saveSetting('isDarkTheme', isDark ? 'true' : 'false');
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

          // Write to modification logs to trigger desktop notification
          await logModification(
            actionType: 'attendance',
            itemType: 'حضور',
            itemName: userName,
            details: 'تسجيل حضور جديد بعد الانصراف من تطبيق الموبايل',
          );

          // Send instant real-time alert via ntfy.sh (sub-second notification)
          try {
            await http
                .post(
                  Uri.parse(
                    'https://ntfy.sh/elattar_attendance_obourdist_9f70cb7a',
                  ),
                  headers: {'Title': 'حضور جديد', 'Priority': 'high'},
                  body: '$userName|حضور',
                )
                .timeout(const Duration(seconds: 3));
            debugPrint(
              'Sent instant ntfy alert for check-in-again of $userName',
            );
          } catch (e) {
            debugPrint('Failed to send instant ntfy alert: $e');
          }

          await syncDatabase();

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

      final id = await _insert(database, 'attendance', {
        if (userId != null) 'userId': userId,
        'userName': userName,
        'userRole': userRole,
        'date': today,
        'checkIn': nowStr,
        'status': status,
        if (notes != null) 'notes': notes,
      });

      // Write to modification logs to trigger desktop notification
      await logModification(
        actionType: 'attendance',
        itemType: 'حضور',
        itemName: userName,
        details: 'تسجيل حضور من تطبيق الموبايل',
      );

      // Send instant real-time alert via ntfy.sh (sub-second notification)
      try {
        await http
            .post(
              Uri.parse(
                'https://ntfy.sh/elattar_attendance_obourdist_9f70cb7a',
              ),
              headers: {'Title': 'حضور', 'Priority': 'high'},
              body: '$userName|حضور',
            )
            .timeout(const Duration(seconds: 3));
        debugPrint('Sent instant ntfy alert for check-in of $userName');
      } catch (e) {
        debugPrint('Failed to send instant ntfy alert: $e');
      }

      await syncDatabase();

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

      if (count > 0) {
        // Write to modification logs to trigger desktop notification
        await logModification(
          actionType: 'attendance',
          itemType: 'انصراف',
          itemName: userName,
          details: 'تسجيل انصراف من تطبيق الموبايل',
        );

        // Send instant real-time alert via ntfy.sh (sub-second notification)
        try {
          await http
              .post(
                Uri.parse(
                  'https://ntfy.sh/elattar_attendance_obourdist_9f70cb7a',
                ),
                headers: {'Title': 'انصراف', 'Priority': 'high'},
                body: '$userName|انصراف',
              )
              .timeout(const Duration(seconds: 3));
          debugPrint('Sent instant ntfy alert for check-out of $userName');
        } catch (e) {
          debugPrint('Failed to send instant ntfy alert: $e');
        }

        await syncDatabase();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error checking out: $e');
      return false;
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
    } catch (e) {
      debugPrint('Error getting attendance by user and date: $e');
    }
    return null;
  }
}
