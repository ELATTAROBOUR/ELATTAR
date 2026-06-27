import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  // ⚠️ Replace with your actual GitHub token (kept in environment variables in production)
  final token = 'YOUR_GITHUB_TOKEN';
  final repo = 'ELATTAROBOUR/OBOURDIST';
  final dbName = 'ELATTAR_STORE.db';
  final branch = 'elobour';

  print('Fetching file info from GitHub...');
  final url = Uri.parse(
    'https://api.github.com/repos/$repo/contents/$dbName?ref=$branch',
  );
  final headers = {
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'Flutter-MobileApp-Sync',
    'Authorization': 'token $token',
  };

  final response = await http.get(url, headers: headers);
  if (response.statusCode != 200) {
    print(
      'Failed to get GitHub file info: ${response.statusCode} - ${response.body}',
    );
    return;
  }

  final data = jsonDecode(response.body);
  final sha = data['sha'];
  final size = data['size'];
  print('Remote file size: $size bytes, SHA: $sha');

  print('Downloading remote database from GitHub...');
  final downloadHeaders = Map<String, String>.from(headers);
  downloadHeaders['Accept'] = 'application/vnd.github.v3.raw';

  final downloadResponse = await http.get(url, headers: downloadHeaders);
  if (downloadResponse.statusCode != 200) {
    print('Failed to download database: ${downloadResponse.statusCode}');
    return;
  }

  final tempDbFile = File(
    '${Directory.current.path}/scratch/temp_github_remote.db',
  );
  await tempDbFile.writeAsBytes(downloadResponse.bodyBytes);
  print('Downloaded database saved to ${tempDbFile.path}.');

  sqfliteFfiInit();
  var dbFactory = databaseFactoryFfi;
  var db = await dbFactory.openDatabase(tempDbFile.absolute.path);

  print('\n--- REMOTE ATTENDANCE TABLE (LAST 5 ROWS) ---');
  try {
    final attResult = await db.rawQuery(
      'SELECT * FROM attendance ORDER BY id DESC LIMIT 5',
    );
    if (attResult.isEmpty) {
      print('No records found.');
    }
    for (var row in attResult) {
      print(row);
    }
  } catch (e) {
    print('Error querying attendance: $e');
  }

  print('\n--- REMOTE MODIFICATION LOGS (LAST 5 ROWS) ---');
  try {
    final logsResult = await db.rawQuery(
      'SELECT * FROM modification_logs ORDER BY id DESC LIMIT 5',
    );
    if (logsResult.isEmpty) {
      print('No records found.');
    }
    for (var row in logsResult) {
      print(row);
    }
  } catch (e) {
    print('Error querying modification_logs: $e');
  }

  await db.close();
  await tempDbFile.delete();
}
