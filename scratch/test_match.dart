import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Mimic the models and matching logic from the app
class Attendance {
  final int? id;
  final int? userId;
  final String userName;
  final String userRole;
  final String date;
  final String? checkIn;
  final String? checkOut;
  final String status;
  final String? notes;

  Attendance({
    this.id,
    this.userId,
    required this.userName,
    required this.userRole,
    required this.date,
    this.checkIn,
    this.checkOut,
    required this.status,
    this.notes,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
        id: json['id'] as int?,
        userId: json['userId'] as int?,
        userName: json['userName'] as String? ?? '',
        userRole: json['userRole'] as String? ?? '',
        date: json['date'] as String? ?? '',
        checkIn: json['checkIn'] as String?,
        checkOut: json['checkOut'] as String?,
        status: json['status'] as String? ?? 'present',
        notes: json['notes'] as String?,
      );
}

void main() async {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;
  
  final dbPath = 'C:\\Users\\BELAL\\AppData\\Local\\Microsoft\\Windows\\Shell\\ELATTAR_STORE.db';
  if (!File(dbPath).existsSync()) {
    print('Database file not found!');
    return;
  }
  
  final db = await databaseFactory.openDatabase(dbPath);
  
  try {
    // Load technicians
    final List<Map<String, dynamic>> techMaps = await db.query('technicians');
    final List<Map<String, String>> technicians = techMaps.map((map) {
      return {
        'name': map['name'] as String,
        'phone': map['phone'] as String,
        'email': (map['email'] as String?) ?? '',
      };
    }).toList();
    
    // Load today attendance
    final List<Map<String, dynamic>> attMaps = await db.query('attendance', where: "date = '2026-06-24'");
    final List<Attendance> todayRecords = attMaps.map((map) => Attendance.fromJson(map)).toList();
    
    print('Loaded ${technicians.length} technicians:');
    for (var t in technicians) {
      print('  - Name: "${t['name']}", Email: "${t['email']}"');
    }
    
    print('\nLoaded ${todayRecords.length} today attendance records:');
    for (var r in todayRecords) {
      print('  - User: "${r.userName}", CheckIn: "${r.checkIn}"');
    }
    
    // Test matching for "الحناوي"
    final testName = 'الحناوي';
    print('\nTesting match for "$testName":');
    
    Attendance? matchedRecord;
    
    // 1. Try direct match
    try {
      matchedRecord = todayRecords.firstWhere(
        (r) => r.userName.trim().toLowerCase() == testName.trim().toLowerCase()
      );
      print('Direct match succeeded: found username "${matchedRecord.userName}"');
    } catch (_) {
      print('Direct match failed.');
      // 2. Fallback
      try {
        final tech = technicians.firstWhere(
          (t) => (t['name'] ?? '').trim().toLowerCase() == testName.trim().toLowerCase(),
          orElse: () => {},
        );
        print('Found technician in fallback: name="${tech['name']}", email="${tech['email']}"');
        if (tech.isNotEmpty && tech['email'] != null && tech['email']!.isNotEmpty) {
          final email = tech['email']!.trim().toLowerCase();
          matchedRecord = todayRecords.firstWhere(
            (r) => r.userName.trim().toLowerCase() == email
          );
          print('Fallback match succeeded: found username "${matchedRecord.userName}"');
        } else {
          print('Technician fallback failed because email is empty or tech map is empty.');
        }
      } catch (e) {
        print('Fallback match threw exception: $e');
      }
    }
    
    if (matchedRecord != null) {
      print('RESULT: Match FOUND! Status: ${matchedRecord.status}, CheckIn: ${matchedRecord.checkIn}');
    } else {
      print('RESULT: Match NOT FOUND!');
    }
    
  } catch (e) {
    print('Error: $e');
  } finally {
    await db.close();
  }
}
