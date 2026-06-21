import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';
import 'database.dart';

// Custom CORS middleware (shelf_cors doesn't support null safety)
Handler corsMiddleware(Handler innerHandler) {
  return (Request request) async {
    if (request.method == 'OPTIONS') {
      return Response.ok(
        '',
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      );
    }
    final response = await innerHandler(request);
    return response.change(
      headers: {'Access-Control-Allow-Origin': '*', ...response.headers},
    );
  };
}

Map<String, dynamic> _rowToMap(Row row) {
  final map = <String, dynamic>{};
  for (final col in row.keys) {
    final val = row[col];
    map[col] = val;
  }
  return map;
}

Future<Response> _handleList(Request request, String table) async {
  try {
    final params = request.url.queryParameters;
    final search = params['search'];
    final sort = params['sort'];
    final order = params['order'] ?? 'ASC';
    final limit = params['limit'];
    final filterField = params['filterField'];
    final filterValue = params['filterValue'];

    final db = getDatabase();

    String sql = 'SELECT * FROM $table';
    final List<dynamic> whereArgs = [];

    if (search != null && search.isNotEmpty) {
      if (table == 'tickets') {
        sql +=
            " WHERE customerName LIKE ? OR customerPhone LIKE ? OR deviceModel LIKE ?";
        final q = '%$search%';
        whereArgs.addAll([q, q, q]);
      } else if (table == 'spare_parts' || table == 'accessories') {
        sql += " WHERE name LIKE ?";
        whereArgs.add('%$search%');
      } else if (table == 'devices') {
        sql += " WHERE model LIKE ? OR imei LIKE ?";
        final q = '%$search%';
        whereArgs.addAll([q, q]);
      } else if (table == 'suppliers') {
        sql += " WHERE name LIKE ?";
        whereArgs.add('%$search%');
      }
    }

    if (filterField != null && filterValue != null) {
      if (whereArgs.isEmpty) {
        sql += ' WHERE ';
      } else {
        sql += ' AND ';
      }
      sql += '$filterField = ?';
      whereArgs.add(filterValue);
    }

    if (sort != null) {
      sql += ' ORDER BY $sort ${order == 'desc' ? 'DESC' : 'ASC'}';
    }

    if (limit != null) {
      sql += ' LIMIT ?';
      whereArgs.add(int.parse(limit));
    }

    final rows = db.select(sql, whereArgs);
    final results = rows.map(_rowToMap).toList();

    return Response.ok(
      jsonEncode(results),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleGet(Request request, String table, String idStr) async {
  try {
    final id = int.parse(idStr);
    final db = getDatabase();
    final rows = db.select('SELECT * FROM $table WHERE id = ?', [id]);
    if (rows.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'Not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode(_rowToMap(rows.first)),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleCreate(Request request, String table) async {
  try {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;

    // Remove id if present to let auto-increment work
    data.remove('id');

    final db = getDatabase();
    final columns = data.keys.join(', ');
    final placeholders = data.keys.map((_) => '?').join(', ');
    final values = data.values.toList();

    db.execute('INSERT INTO $table ($columns) VALUES ($placeholders)', values);

    // Get the last inserted row
    final lastId = db.lastInsertRowId;
    final rows = db.select('SELECT * FROM $table WHERE rowid = ?', [lastId]);

    if (rows.isNotEmpty) {
      return Response.ok(
        jsonEncode(_rowToMap(rows.first)),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'id': lastId}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleUpdate(
  Request request,
  String table,
  String idStr,
) async {
  try {
    final id = int.parse(idStr);
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;

    data.remove('id'); // Don't update primary key

    final db = getDatabase();
    final setClause = data.keys.map((k) => '$k = ?').join(', ');
    final values = [...data.values, id];

    db.execute('UPDATE $table SET $setClause WHERE id = ?', values);

    final rows = db.select('SELECT * FROM $table WHERE id = ?', [id]);
    if (rows.isNotEmpty) {
      return Response.ok(
        jsonEncode(_rowToMap(rows.first)),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleDelete(
  Request request,
  String table,
  String idStr,
) async {
  try {
    final id = int.parse(idStr);
    final db = getDatabase();
    db.execute('DELETE FROM $table WHERE id = ?', [id]);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleCount(Request request, String table) async {
  try {
    final db = getDatabase();
    final result = db.select('SELECT COUNT(*) as count FROM $table');
    final count = result.first['count'] as int;
    return Response.ok(
      jsonEncode({'count': count}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleTicketSearch(Request request) async {
  try {
    final query = request.url.queryParameters['q'] ?? '';
    final db = getDatabase();
    final q = '%$query%';
    final rows = db.select(
      'SELECT * FROM tickets WHERE customerName LIKE ? OR customerPhone LIKE ? OR deviceModel LIKE ? OR technicianName LIKE ? ORDER BY receivedDate DESC',
      [q, q, q, q],
    );
    return Response.ok(
      jsonEncode(rows.map(_rowToMap).toList()),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleLogin(Request request) async {
  try {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final email = data['email'] as String;
    final passwordHash = data['passwordHash'] as String;

    final db = getDatabase();
    final rows = db.select(
      'SELECT * FROM users WHERE email = ? AND passwordHash = ?',
      [email, passwordHash],
    );
    if (rows.isEmpty) {
      return Response.ok(
        jsonEncode({'error': 'Invalid credentials'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode(_rowToMap(rows.first)),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleDashboardCounts(Request request) async {
  try {
    final db = getDatabase();
    final tables = [
      'tickets',
      'spare_parts',
      'accessories',
      'devices',
      'suppliers',
      'sales',
    ];
    final counts = <String, int>{};
    for (final table in tables) {
      final result = db.select('SELECT COUNT(*) as count FROM $table');
      counts[table] = result.first['count'] as int;
    }
    return Response.ok(
      jsonEncode(counts),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> _handleRegister(Request request) async {
  try {
    final body = await request.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    final email = data['email'] as String;
    final passwordHash = data['passwordHash'] as String;
    final role = data['role'] as String? ?? 'admin';
    final name = data['name'] as String?;

    final db = getDatabase();

    // Check if email already exists
    final existing = db.select('SELECT id FROM users WHERE email = ?', [email]);
    if (existing.isNotEmpty) {
      return Response.ok(
        jsonEncode({'error': 'Email already registered'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    db.execute(
      'INSERT INTO users (email, passwordHash, role, name) VALUES (?, ?, ?, ?)',
      [email, passwordHash, role, name],
    );

    final lastId = db.lastInsertRowId;
    final rows = db.select('SELECT * FROM users WHERE id = ?', [lastId]);
    if (rows.isNotEmpty) {
      return Response.ok(
        jsonEncode(_rowToMap(rows.first)),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': e.toString()}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

// Allowed table names for security (tables with integer primary keys)
const allowedTables = [
  'tickets',
  'spare_parts',
  'technicians',
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
  'modification_logs',
  'users',
];

Future<void> runServer(List<String> args) async {
  // Initialize database
  getDatabase();
  print('Database initialized.');

  final app = Router();

  // Special endpoints
  app.get('/api/tickets/search', _handleTicketSearch);
  app.post('/api/auth/login', _handleLogin);
  app.post('/api/auth/register', _handleRegister);
  app.get('/api/dashboard/counts', _handleDashboardCounts);

  // Settings endpoints (string keys — passed as second arg by shelf_router)
  app.get('/api/settings/count', (req) => _handleCount(req, 'settings'));
  app.get('/api/settings', (req) => _handleList(req, 'settings'));
  app.post('/api/settings', (req) => _handleCreate(req, 'settings'));
  app.get('/api/settings/<key>', (Request req, String key) async {
    final db = getDatabase();
    final rows = db.select('SELECT * FROM settings WHERE key = ?', [key]);
    if (rows.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'Not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode(_rowToMap(rows.first)),
      headers: {'Content-Type': 'application/json'},
    );
  });
  app.put('/api/settings/<key>', (Request req, String key) async {
    final body = await req.readAsString();
    final data = jsonDecode(body) as Map<String, dynamic>;
    data.remove('key'); // Don't update primary key
    final db = getDatabase();
    final setClause = data.keys.map((k) => '$k = ?').join(', ');
    final values = [...data.values, key];
    db.execute('UPDATE settings SET $setClause WHERE key = ?', values);
    final rows = db.select('SELECT * FROM settings WHERE key = ?', [key]);
    if (rows.isNotEmpty) {
      return Response.ok(
        jsonEncode(_rowToMap(rows.first)),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  });
  app.delete('/api/settings/<key>', (Request req, String key) async {
    final db = getDatabase();
    db.execute('DELETE FROM settings WHERE key = ?', [key]);
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // Generic CRUD routes for all tables
  for (final table in allowedTables) {
    app.get('/api/$table/count', (req) => _handleCount(req, table));
    app.get('/api/$table', (req) => _handleList(req, table));
    app.get(
      '/api/$table/<id>',
      (Request req, String id) => _handleGet(req, table, id),
    );
    app.post('/api/$table', (req) => _handleCreate(req, table));
    app.put(
      '/api/$table/<id>',
      (Request req, String id) => _handleUpdate(req, table, id),
    );
    app.delete(
      '/api/$table/<id>',
      (Request req, String id) => _handleDelete(req, table, id),
    );
  }

  // Health check
  app.get('/health', (req) => Response.ok('OK'));

  final handler = corsMiddleware(app);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, '0.0.0.0', port);
  print('Server running on http://0.0.0.0:${server.port}');
}
