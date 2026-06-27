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
    'c:\\Users\\BELAL\\Desktop\\ELATTAROBOUR\\temp_github_remote.db',
  );
  await tempDbFile.writeAsBytes(downloadResponse.bodyBytes);
  print('Downloaded database saved to temp_github_remote.db.');

  sqfliteFfiInit();
  var dbFactory = databaseFactoryFfi;
  var db = await dbFactory.openDatabase(tempDbFile.path);

  try {
    var users = await db.query('users');
    print('=== REMOTE USERS ===');
    for (var u in users) {
      print('ID: ${u['id']}, Email: "${u['email']}", Role: "${u['role']}"');
    }
  } catch (e) {
    print('Error querying remote users: $e');
  }

  try {
    var techs = await db.query('technicians');
    print('=== REMOTE TECHS ===');
    for (var t in techs) {
      print('ID: ${t['id']}, Name: "${t['name']}", Email: "${t['email']}"');
    }
  } catch (e) {
    print('Error querying remote techs: $e');
  }

  await db.close();
  await tempDbFile.delete();
}
