import 'dart:io';
import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';

void main() async {
  final url = 'https://raw.githubusercontent.com/mojlinux58/ELATTAR/DB_SUB/keygen/subscribers.db';
  final client = HttpClient();
  
  try {
    print('Downloading from $url ...');
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    
    if (response.statusCode != 200) {
      print('Failed to download: ${response.statusCode}');
      return;
    }
    
    final bytes = <int>[];
    await for (var chunk in response) {
      bytes.addAll(chunk);
    }
    
    final tempFile = File('temp_github_subscribers.db');
    await tempFile.writeAsBytes(bytes);
    print('Downloaded ${bytes.length} bytes to ${tempFile.path}');
    
    final db = sqlite3.open(tempFile.path);
    final results = db.select('SELECT name FROM sqlite_master WHERE type="table"');
    print('Tables:');
    for (final row in results) {
      print(row['name']);
    }
    
    final subscribers = db.select('SELECT * FROM subscribers');
    print('\nSubscribers (${subscribers.length}):');
    for (final row in subscribers) {
      print('HWID: ${row['hwid']}, Name: ${row['clientName']}, Email: ${row['registeredEmail']}, Status: ${row['status']}, Expiry: ${row['expiryDate']}');
    }
    
    db.dispose();
    await tempFile.delete();
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
