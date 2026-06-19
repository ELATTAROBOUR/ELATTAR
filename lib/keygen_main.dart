import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:http/http.dart' as http;
import 'hwid_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  runApp(const KeygenApp());
}

class KeygenApp extends StatelessWidget {
  const KeygenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'العطار استور - لوحة التراخيص',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Cairo',
        scaffoldBackgroundColor: const Color(0xFF0D131E),
        primaryColor: const Color(0xFFD4AF37),
        cardColor: const Color(0xFF15202F),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: const Color(0xFF0D131E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(
                fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1C2C3E),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 1.2),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'EG'),
      ],
      locale: const Locale('ar', 'EG'),
      home: const KeygenScreen(),
    );
  }
}

class KeygenScreen extends StatefulWidget {
  const KeygenScreen({super.key});

  @override
  State<KeygenScreen> createState() => _KeygenScreenState();
}

class _KeygenScreenState extends State<KeygenScreen> {
  int _selectedTab = 0; // 0: Keygen, 1: Subscribers

  // --- Keygen State ---
  final TextEditingController _hwidController = TextEditingController();
  String _validationStatus = "أدخل رمز الجهاز للتحقق";
  bool _isValidHwid = false;
  String _decryptedSignature = "";
  String _generatedKey = "";
  String _fileStatus = "";
  String _selectedDuration = "1_YEAR";
  DateTime? _customExpiryDate;

  // --- Subscribers State ---
  List<Map<String, dynamic>> _subscribers = [];
  bool _loadingSubscribers = false;
  String _gitStatus = "";
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _hwidController.addListener(_onHwidChanged);
  }

  @override
  void dispose() {
    _hwidController.dispose();
    super.dispose();
  }

  void _onHwidChanged() {
    final hwid = _hwidController.text.trim();
    if (hwid.isEmpty) {
      setState(() {
        _validationStatus = "أدخل رمز الجهاز للتحقق";
        _isValidHwid = false;
        _decryptedSignature = "";
      });
      return;
    }

    final decrypted = HwidService.verifyAndDecryptHWID(hwid);
    if (decrypted != null) {
      setState(() {
        _validationStatus = "رمز الجهاز صالح ومتطابق ✅";
        _isValidHwid = true;
        _decryptedSignature = decrypted;
      });
    } else {
      setState(() {
        _validationStatus = "رمز جهاز غير صالح أو تم تعديله ❌";
        _isValidHwid = false;
        _decryptedSignature = "";
      });
    }
  }

  Future<void> _generateLicense() async {
    final hwid = _hwidController.text.trim();
    if (!_isValidHwid) return;

    String expiry = "LIFETIME";
    final now = DateTime.now();

    if (_selectedDuration == "5_MINUTES") {
      expiry = _formatDateTime(now.add(const Duration(minutes: 5)));
    } else if (_selectedDuration == "1_DAY") {
      expiry = _formatDate(now.add(const Duration(days: 1)));
    } else if (_selectedDuration == "1_MONTH") {
      expiry = _formatDate(now.add(const Duration(days: 30)));
    } else if (_selectedDuration == "3_MONTHS") {
      expiry = _formatDate(now.add(const Duration(days: 90)));
    } else if (_selectedDuration == "6_MONTHS") {
      expiry = _formatDate(now.add(const Duration(days: 180)));
    } else if (_selectedDuration == "1_YEAR") {
      expiry = _formatDate(now.add(const Duration(days: 365)));
    } else if (_selectedDuration == "CUSTOM") {
      if (_customExpiryDate == null) {
        setState(() {
          _fileStatus = "الرجاء اختيار تاريخ انتهاء التفعيل المخصص ❌";
        });
        return;
      }
      expiry = _formatDate(_customExpiryDate!);
    }

    final key = HwidService.generateKey(hwid, expiry);
    setState(() {
      _generatedKey = key;
      _fileStatus = "جاري حفظ ملف التفعيل...";
    });

    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final file = File("$exeDir/license.lic");
      await file.writeAsString(key);
      setState(() {
        _fileStatus =
            "تم إنشاء ملف التفعيل (license.lic) بنجاح بجوار الكيجين!\nمدة التفعيل: ${expiry == 'LIFETIME' ? 'مدى الحياة ♾️' : expiry} 📂";
      });
    } catch (e) {
      setState(() {
        _fileStatus = "فشل حفظ الملف: $e ❌";
      });
    }
  }

  void _generateResetKey() {
    final hwid = _hwidController.text.trim();
    if (!_isValidHwid) return;

    final key = HwidService.generateResetKey(hwid);
    setState(() {
      _generatedKey = key;
      _fileStatus = "تم توليد كود إعادة التعيين بنجاح! 🔑";
    });
  }

  String _formatDate(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}T${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}";
  }

  // --- Central Database / Subscribers Sync Logics ---
  File getSubscribersDbFile() {
    return File("${Directory.current.path}/subscribers.db");
  }

  Future<void> _loadSubscribersList() async {
    setState(() {
      _loadingSubscribers = true;
    });
    try {
      final dbFile = getSubscribersDbFile();
      final db = await databaseFactory.openDatabase(dbFile.path);
      
      // Create tables if they do not exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS subscribers (
          hwid TEXT PRIMARY KEY,
          clientName TEXT,
          registeredEmail TEXT,
          status TEXT,
          expiryDate TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS created_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subscriber_hwid TEXT,
          email TEXT,
          role TEXT,
          FOREIGN KEY (subscriber_hwid) REFERENCES subscribers (hwid) ON DELETE CASCADE
        )
      ''');

      final List<Map<String, dynamic>> subRows = await db.query('subscribers');
      final List<Map<String, dynamic>> list = [];

      for (var row in subRows) {
        final hwid = row['hwid']?.toString() ?? '';
        final List<Map<String, dynamic>> userRows = await db.query(
          'created_users',
          where: 'subscriber_hwid = ?',
          whereArgs: [hwid],
        );
        final createdUsers = userRows.map((ur) {
          return {
            'email': ur['email']?.toString() ?? '',
            'role': ur['role']?.toString() ?? 'staff',
          };
        }).toList();

        list.add({
          'hwid': hwid,
          'clientName': row['clientName']?.toString() ?? '',
          'registeredEmail': row['registeredEmail']?.toString() ?? '',
          'status': row['status']?.toString() ?? 'active',
          'expiryDate': row['expiryDate']?.toString() ?? 'LIFETIME',
          'createdUsers': createdUsers,
        });
      }

      await db.close();
      setState(() {
        _subscribers = list;
      });
    } catch (e) {
      debugPrint("Error loading subscribers from SQLite: $e");
    } finally {
      setState(() {
        _loadingSubscribers = false;
      });
    }
  }

  Future<void> _saveAndPushSubscribers() async {
    setState(() {
      _loadingSubscribers = true;
      _gitStatus = "جاري حفظ وتحديث قاعدة البيانات محلياً...";
    });

    try {
      final dbFile = getSubscribersDbFile();
      final db = await databaseFactory.openDatabase(dbFile.path);

      await db.execute('''
        CREATE TABLE IF NOT EXISTS subscribers (
          hwid TEXT PRIMARY KEY,
          clientName TEXT,
          registeredEmail TEXT,
          status TEXT,
          expiryDate TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS created_users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          subscriber_hwid TEXT,
          email TEXT,
          role TEXT,
          FOREIGN KEY (subscriber_hwid) REFERENCES subscribers (hwid) ON DELETE CASCADE
        )
      ''');

      await db.transaction((txn) async {
        await txn.delete('subscribers');
        await txn.delete('created_users');

        for (var sub in _subscribers) {
          final hwid = sub['hwid']?.toString() ?? '';
          await txn.insert('subscribers', {
            'hwid': hwid,
            'clientName': sub['clientName']?.toString() ?? '',
            'registeredEmail': sub['registeredEmail']?.toString() ?? '',
            'status': sub['status']?.toString() ?? 'active',
            'expiryDate': sub['expiryDate']?.toString() ?? 'LIFETIME',
          });

          final List<dynamic> users = sub['createdUsers'] ?? [];
          for (var user in users) {
            await txn.insert('created_users', {
              'subscriber_hwid': hwid,
              'email': user['email']?.toString() ?? '',
              'role': user['role']?.toString() ?? 'staff',
            });
          }
        }
      });

      await db.close();

      _gitStatus = "جاري مزامنة التعديلات مع السحابة (Google Sheets)...";

      final List<Map<String, dynamic>> subscribersListToSend = [];
      for (var sub in _subscribers) {
        subscribersListToSend.add({
          "hwid": sub['hwid']?.toString() ?? '',
          "clientName": sub['clientName']?.toString() ?? '',
          "registeredEmail": sub['registeredEmail']?.toString() ?? '',
          "status": sub['status']?.toString() ?? 'active',
          "expiryDate": sub['expiryDate']?.toString() ?? 'LIFETIME',
        });
      }

      const scriptUrlStr = 'https://script.google.com/macros/s/AKfycbwOST4D39vRmr06OIbESCtZal0QSpDE4JoFCf1bBg3LiSf3XW0AFALRCuMnQrcNyxScYw/exec';
      final response = await http.post(
        Uri.parse(scriptUrlStr),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "sync",
          "subscribers": subscribersListToSend
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception("فشل الاتصال بالخادم السحابي: كود الاستجابة ${response.statusCode}");
      }

      final resData = jsonDecode(response.body);
      if (resData['status'] != 'success') {
        throw Exception("فشل حفظ التحديثات سحابياً: ${resData['message']}");
      }

      setState(() {
        _gitStatus = "تم حفظ التعديلات ومزامنتها مع Google Sheet بنجاح! ✅";
      });
    } catch (e) {
      setState(() {
        _gitStatus = "حدث خطأ أثناء الرفع: $e ❌";
      });
    } finally {
      setState(() {
        _loadingSubscribers = false;
      });
    }
  }

  Future<void> _scanClientBranches() async {
    setState(() {
      _loadingSubscribers = true;
      _gitStatus = "جاري جلب فروع GitHub المتوفرة...";
    });

    try {
      final fetchRes = await Process.run('git', ['fetch', '--all']);
      if (fetchRes.exitCode != 0) {
        throw Exception("فشل git fetch: ${fetchRes.stderr}");
      }

      final branchRes = await Process.run('git', ['branch', '-r']);
      if (branchRes.exitCode != 0) {
        throw Exception("فشل قراءة قائمة الفروع: ${branchRes.stderr}");
      }

      final output = branchRes.stdout.toString();
      final lines = output.split(RegExp(r'[\r\n]+'));

      int scannedCount = 0;
      for (var line in lines) {
        final cleanBranch = line.trim();
        if (cleanBranch.isEmpty || cleanBranch.contains('origin/HEAD') || cleanBranch.contains('origin/main')) {
          continue;
        }

        final branchName = cleanBranch.replaceAll('origin/', '');
        setState(() {
          _gitStatus = "جاري استخراج قاعدة بيانات الفرع: $branchName...";
        });

        final tempDbFile = File("${Directory.current.path}/temp_$branchName.db");
        
        // Extract database file from that branch
        final showRes = await Process.run('git', ['show', '$cleanBranch:ELATTAR_STORE.db'], stdoutEncoding: null);
        if (showRes.exitCode == 0) {
          final bytes = showRes.stdout as List<int>;
          await tempDbFile.writeAsBytes(bytes);

          // Open the database in read-only mode to extract info
          final db = await databaseFactory.openDatabase(tempDbFile.path);
          try {
            String? clientName;
            String? clientEmail;
            String? clientHwid;

            final List<Map<String, dynamic>> settingsList = await db.query('settings');
            for (var row in settingsList) {
              final key = row['key']?.toString();
              final val = row['value']?.toString();
              if (key == 'clientName') clientName = val;
              if (key == 'clientEmail') clientEmail = val;
              if (key == 'clientHwid') clientHwid = val;
            }

            final List<Map<String, dynamic>> usersList = await db.query('users');
            final createdUsers = usersList.map((row) {
              return {
                'email': row['email']?.toString() ?? '',
                'role': row['role']?.toString() ?? 'staff',
              };
            }).toList();

            // Try to extract HWID from activationKey if not stored explicitly
            if (clientHwid == null || clientHwid.isEmpty) {
              final actKeyRow = settingsList.firstWhere(
                (r) => r['key'] == 'activationKey',
                orElse: () => {},
              );
              final actKey = actKeyRow['value']?.toString();
              if (actKey != null && actKey.isNotEmpty) {
                try {
                  final cleanKey = actKey.replaceAll('-', '').toUpperCase();
                  final decryptedBytes = _decryptBytes(Base32.decode(cleanKey)!, "ELATTAR_STORE_SECURE_SALT_2026");
                  final decryptedStr = utf8.decode(decryptedBytes);
                  clientHwid = decryptedStr.split('|')[0];
                } catch (_) {}
              }
            }

            if (clientEmail != null && clientEmail.isNotEmpty) {
              clientHwid ??= "UNKNOWN-$branchName";

              int existingIndex = _subscribers.indexWhere((sub) {
                final subH = sub['hwid']?.toString().replaceAll('-', '').toUpperCase();
                final curH = clientHwid?.replaceAll('-', '').toUpperCase();
                return subH == curH;
              });

              if (existingIndex != -1) {
                _subscribers[existingIndex]['clientName'] = clientName ?? _subscribers[existingIndex]['clientName'] ?? branchName;
                _subscribers[existingIndex]['registeredEmail'] = clientEmail;
                _subscribers[existingIndex]['createdUsers'] = createdUsers;
              } else {
                _subscribers.add({
                  'hwid': clientHwid,
                  'clientName': clientName ?? branchName,
                  'registeredEmail': clientEmail,
                  'status': 'active',
                  'expiryDate': 'LIFETIME',
                  'createdUsers': createdUsers,
                });
              }
              scannedCount++;
            }
          } catch (e) {
            debugPrint("Error parsing data for branch $branchName: $e");
          } finally {
            await db.close();
            try {
              await tempDbFile.delete();
            } catch (_) {}
          }
        }
      }

      setState(() {
        _gitStatus = "تم استيراد وتحديث $scannedCount مشتركين من الفروع بنجاح! 🚀";
      });
    } catch (e) {
      setState(() {
        _gitStatus = "حدث خطأ أثناء فحص الفروع: $e ❌";
      });
    } finally {
      setState(() {
        _loadingSubscribers = false;
      });
    }
  }

  List<int> _decryptBytes(List<int> bytes, String key) {
    final keyBytes = utf8.encode(key);
    final result = List<int>.filled(bytes.length, 0);
    for (int i = 0; i < bytes.length; i++) {
      result[i] = bytes[i] ^ keyBytes[i % keyBytes.length] ^ ((i * 47 + 139) % 256);
    }
    return result;
  }

  // --- UI Elements ---
  Widget _buildSidebarItem({required int index, required String title, required IconData icon}) {
    final primaryColor = const Color(0xFFD4AF37);
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
        if (index == 1) {
          _loadSubscribersList();
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? primaryColor.withValues(alpha: 0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? primaryColor : Colors.white70,
              size: 22,
            ),
            const SizedBox(width: 14),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? primaryColor : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSubscriberDialog() {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final hwidCtrl = TextEditingController();
    String status = "active";
    String expiryDateStr = "LIFETIME";
    String selectedDuration = "LIFETIME";
    DateTime selectedExp = DateTime.now().add(const Duration(days: 365));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final primaryColor = const Color(0xFFD4AF37);
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF15202F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Row(
                children: [
                  Icon(Icons.person_add_rounded, color: primaryColor),
                  const SizedBox(width: 10),
                  const Text("إضافة مشترك جديد يدوياً", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: "اسم العميل / المحل *"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(labelText: "البريد الإلكتروني المسجل *"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: hwidCtrl,
                        decoration: const InputDecoration(labelText: "رمز جهاز العميل (HWID) *", hintText: "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX"),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: status,
                        decoration: const InputDecoration(labelText: "حالة الاشتراك"),
                        dropdownColor: const Color(0xFF15202F),
                        items: const [
                          DropdownMenuItem(value: "active", child: Text("نشط / متفعل")),
                          DropdownMenuItem(value: "inactive", child: Text("غير نشط")),
                          DropdownMenuItem(value: "blocked", child: Text("محظور")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              status = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedDuration,
                        decoration: const InputDecoration(labelText: "تاريخ انتهاء التفعيل"),
                        dropdownColor: const Color(0xFF15202F),
                        items: const [
                          DropdownMenuItem(value: "5_MINUTES", child: Text("5 دقائق (للتجريب) ⏳")),
                          DropdownMenuItem(value: "1_DAY", child: Text("يوم واحد (24 ساعة) 🗓️")),
                          DropdownMenuItem(value: "1_MONTH", child: Text("شهر واحد (30 يوم) 🗓️")),
                          DropdownMenuItem(value: "3_MONTHS", child: Text("3 أشهر (90 يوم) 🗓️")),
                          DropdownMenuItem(value: "6_MONTHS", child: Text("6 أشهر (180 يوم) 🗓️")),
                          DropdownMenuItem(value: "1_YEAR", child: Text("سنة واحدة (365 يوم) 🗓️")),
                          DropdownMenuItem(value: "LIFETIME", child: Text("مدى الحياة ♾️")),
                          DropdownMenuItem(value: "CUSTOM", child: Text("تحديد تاريخ مخصص... 🛠️")),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            selectedDuration = val ?? "LIFETIME";
                            final now = DateTime.now();
                            if (selectedDuration == "LIFETIME") {
                              expiryDateStr = "LIFETIME";
                            } else if (selectedDuration == "5_MINUTES") {
                              expiryDateStr = _formatDateTime(now.add(const Duration(minutes: 5)));
                            } else if (selectedDuration == "1_DAY") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 1)));
                            } else if (selectedDuration == "1_MONTH") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 30)));
                            } else if (selectedDuration == "3_MONTHS") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 90)));
                            } else if (selectedDuration == "6_MONTHS") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 180)));
                            } else if (selectedDuration == "1_YEAR") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 365)));
                            } else if (selectedDuration == "CUSTOM") {
                              expiryDateStr = _formatDate(selectedExp);
                            }
                          });
                        },
                      ),
                      if (selectedDuration == "CUSTOM") ...[
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedExp,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 3650)),
                              locale: const Locale('ar', 'EG'),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedExp = picked;
                                expiryDateStr = _formatDate(picked);
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C2C3E),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: primaryColor),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month, color: primaryColor),
                                const SizedBox(width: 10),
                                Text("تاريخ الانتهاء: $expiryDateStr"),
                              ],
                            ),
                          ),
                        ),
                      ] else if (selectedDuration != "LIFETIME") ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2C3E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined, color: Colors.greenAccent),
                              const SizedBox(width: 10),
                              Text("محسوب تلقائياً: $expiryDateStr", style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final email = emailCtrl.text.trim();
                    final hwid = hwidCtrl.text.trim();

                    if (name.isEmpty || email.isEmpty || hwid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("الرجاء ملء جميع الحقول المطلوبة ⚠️"), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }

                    setState(() {
                      _subscribers.add({
                        'hwid': hwid,
                        'clientName': name,
                        'registeredEmail': email,
                        'status': status,
                        'expiryDate': expiryDateStr,
                        'createdUsers': [],
                      });
                    });

                    Navigator.pop(context);
                  },
                  child: const Text("حفظ", style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditSubscriberDialog(Map<String, dynamic> subscriber, int index) {
    final nameCtrl = TextEditingController(text: subscriber['clientName']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: subscriber['registeredEmail']?.toString() ?? '');
    final hwidCtrl = TextEditingController(text: subscriber['hwid']?.toString() ?? '');
    String status = subscriber['status']?.toString() ?? 'active';
    String expiryDateStr = subscriber['expiryDate']?.toString() ?? 'LIFETIME';
    
    String selectedDuration = "LIFETIME";
    if (expiryDateStr != "LIFETIME") {
      selectedDuration = "CUSTOM";
    }
    
    DateTime selectedExp = expiryDateStr == "LIFETIME" 
        ? DateTime.now().add(const Duration(days: 365))
        : DateTime.tryParse(expiryDateStr) ?? DateTime.now().add(const Duration(days: 365));

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final primaryColor = const Color(0xFFD4AF37);
          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFF15202F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Row(
                children: [
                  Icon(Icons.edit_rounded, color: primaryColor),
                  const SizedBox(width: 10),
                  const Text("تعديل بيانات المشترك", style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 450,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: "اسم العميل / المحل"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(labelText: "البريد الإلكتروني المسجل"),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: hwidCtrl,
                        decoration: const InputDecoration(labelText: "رمز جهاز العميل (HWID)", enabled: false),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: status,
                        decoration: const InputDecoration(labelText: "حالة الاشتراك"),
                        dropdownColor: const Color(0xFF15202F),
                        items: const [
                          DropdownMenuItem(value: "active", child: Text("نشط / متفعل")),
                          DropdownMenuItem(value: "inactive", child: Text("غير نشط")),
                          DropdownMenuItem(value: "blocked", child: Text("محظور")),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              status = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedDuration,
                        decoration: const InputDecoration(labelText: "تاريخ انتهاء التفعيل"),
                        dropdownColor: const Color(0xFF15202F),
                        items: const [
                          DropdownMenuItem(value: "5_MINUTES", child: Text("5 دقائق (للتجريب) ⏳")),
                          DropdownMenuItem(value: "1_DAY", child: Text("يوم واحد (24 ساعة) 🗓️")),
                          DropdownMenuItem(value: "1_MONTH", child: Text("شهر واحد (30 يوم) 🗓️")),
                          DropdownMenuItem(value: "3_MONTHS", child: Text("3 أشهر (90 يوم) 🗓️")),
                          DropdownMenuItem(value: "6_MONTHS", child: Text("6 أشهر (180 يوم) 🗓️")),
                          DropdownMenuItem(value: "1_YEAR", child: Text("سنة واحدة (365 يوم) 🗓️")),
                          DropdownMenuItem(value: "LIFETIME", child: Text("مدى الحياة ♾️")),
                          DropdownMenuItem(value: "CUSTOM", child: Text("تحديد تاريخ مخصص... 🛠️")),
                        ],
                        onChanged: (val) {
                          setDialogState(() {
                            selectedDuration = val ?? "LIFETIME";
                            final now = DateTime.now();
                            if (selectedDuration == "LIFETIME") {
                              expiryDateStr = "LIFETIME";
                            } else if (selectedDuration == "5_MINUTES") {
                              expiryDateStr = _formatDateTime(now.add(const Duration(minutes: 5)));
                            } else if (selectedDuration == "1_DAY") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 1)));
                            } else if (selectedDuration == "1_MONTH") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 30)));
                            } else if (selectedDuration == "3_MONTHS") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 90)));
                            } else if (selectedDuration == "6_MONTHS") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 180)));
                            } else if (selectedDuration == "1_YEAR") {
                              expiryDateStr = _formatDate(now.add(const Duration(days: 365)));
                            } else if (selectedDuration == "CUSTOM") {
                              expiryDateStr = _formatDate(selectedExp);
                            }
                          });
                        },
                      ),
                      if (selectedDuration == "CUSTOM") ...[
                        const SizedBox(height: 12),
                        InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedExp,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 3650)),
                              locale: const Locale('ar', 'EG'),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedExp = picked;
                                expiryDateStr = _formatDate(picked);
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C2C3E),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: primaryColor),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_month, color: primaryColor),
                                const SizedBox(width: 10),
                                Text("تاريخ الانتهاء: $expiryDateStr"),
                              ],
                            ),
                          ),
                        ),
                      ] else if (selectedDuration != "LIFETIME") ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2C3E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined, color: Colors.greenAccent),
                              const SizedBox(width: 10),
                              Text("محسوب تلقائياً: $expiryDateStr", style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("إلغاء", style: TextStyle(fontFamily: 'Cairo')),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final email = emailCtrl.text.trim();

                    if (name.isEmpty || email.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("الرجاء ملء جميع الحقول المطلوبة ⚠️"), backgroundColor: Colors.redAccent),
                      );
                      return;
                    }

                    setState(() {
                      _subscribers[index]['clientName'] = name;
                      _subscribers[index]['registeredEmail'] = email;
                      _subscribers[index]['status'] = status;
                      _subscribers[index]['expiryDate'] = expiryDateStr;
                    });

                    Navigator.pop(context);
                  },
                  child: const Text("حفظ التعديلات", style: TextStyle(fontFamily: 'Cairo')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubscribersView() {
    final primaryColor = const Color(0xFFD4AF37);
    final cardColor = const Color(0xFF15202F);

    // Filter subscribers by search query
    final filtered = _subscribers.where((sub) {
      final query = _searchQuery.toLowerCase();
      final name = (sub['clientName'] ?? '').toString().toLowerCase();
      final email = (sub['registeredEmail'] ?? '').toString().toLowerCase();
      final hwid = (sub['hwid'] ?? '').toString().toLowerCase();
      return name.contains(query) || email.contains(query) || hwid.contains(query);
    }).toList();

    int activeCount = _subscribers.where((s) => s['status'] == 'active').length;
    int blockedCount = _subscribers.where((s) => s['status'] == 'blocked').length;
    int inactiveCount = _subscribers.where((s) => s['status'] == 'inactive').length;

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "👥 إدارة المشتركين",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "قاعدة البيانات المشتركة مع جميع فروع العملاء للتحقق من تفعيل التراخيص.",
                    style: TextStyle(fontSize: 14, color: Colors.white60),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _showAddSubscriberDialog,
                icon: const Icon(Icons.person_add_rounded, size: 20),
                label: const Text("إضافة مشترك جديد"),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Statistics Row
          Row(
            children: [
              _buildStatCard(title: "إجمالي المشتركين", count: _subscribers.length, color: Colors.blueAccent),
              const SizedBox(width: 16),
              _buildStatCard(title: "نشط ومتفعل", count: activeCount, color: Colors.greenAccent),
              const SizedBox(width: 16),
              _buildStatCard(title: "غير نشط", count: inactiveCount, color: Colors.grey),
              const SizedBox(width: 16),
              _buildStatCard(title: "محظور", count: blockedCount, color: Colors.redAccent),
            ],
          ),
          const SizedBox(height: 24),

          // Search and Git Actions Control Panel
          Card(
            color: cardColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: "البحث باسم العميل، البريد الإلكتروني، أو رمز الجهاز...",
                        prefixIcon: Icon(Icons.search_rounded),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2F41), foregroundColor: Colors.blueAccent),
                    onPressed: _loadingSubscribers ? null : _scanClientBranches,
                    icon: const Icon(Icons.sync_rounded),
                    label: const Text("تحديث من فروع Git"),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: const Color(0xFF0D131E)),
                    onPressed: _loadingSubscribers ? null : _saveAndPushSubscribers,
                    icon: const Icon(Icons.cloud_upload_rounded),
                    label: const Text("حفظ ورفع لـ GitHub"),
                  ),
                ],
              ),
            ),
          ),

          if (_gitStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
              ),
              child: Text(
                _gitStatus,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Subscribers List
          Expanded(
            child: _loadingSubscribers
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(primaryColor)),
                        const SizedBox(height: 16),
                        const Text("جاري جلب وتجهيز البيانات...", style: TextStyle(fontFamily: 'Cairo')),
                      ],
                    ),
                  )
                : filtered.isEmpty
                    ? const Center(
                        child: Text("لا يوجد أي مشتركين مطابقين للبحث 📂", style: TextStyle(fontFamily: 'Cairo', fontSize: 16)),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final sub = filtered[index];
                          final name = sub['clientName']?.toString() ?? 'مشترك غير معروف';
                          final email = sub['registeredEmail']?.toString() ?? 'لا يوجد بريد مسجل';
                          final hwid = sub['hwid']?.toString() ?? 'لا يوجد HWID';
                          final status = sub['status']?.toString() ?? 'active';
                          final expiry = sub['expiryDate']?.toString() ?? 'LIFETIME';
                          final List<dynamic> users = sub['createdUsers'] ?? [];

                          Color statusColor = Colors.green;
                          String statusText = "نشط";
                          if (status == 'blocked') {
                            statusColor = Colors.redAccent;
                            statusText = "محظور";
                          } else if (status == 'inactive') {
                            statusColor = Colors.grey;
                            statusText = "غير نشط";
                          }

                          return Card(
                            color: cardColor,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ExpansionTile(
                              iconColor: primaryColor,
                              collapsedIconColor: Colors.white54,
                              title: Row(
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Cairo'),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: statusColor),
                                    ),
                                    child: Text(
                                      statusText,
                                      style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      email,
                                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    expiry == 'LIFETIME' ? "تفعيل مدى الحياة" : "تاريخ الانتهاء: $expiry",
                                    style: TextStyle(color: primaryColor, fontSize: 13),
                                  ),
                                ],
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(20.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              const Text("رمز الجهاز (HWID): ", style: TextStyle(color: Colors.white70)),
                                              SelectableText(hwid, style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.copy, size: 16, color: Colors.white54),
                                                onPressed: () {
                                                  Clipboard.setData(ClipboardData(text: hwid));
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text("📋 تم نسخ رمز الجهاز")),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E2F41), foregroundColor: primaryColor),
                                                onPressed: () => _showEditSubscriberDialog(sub, _subscribers.indexOf(sub)),
                                                icon: const Icon(Icons.edit_rounded, size: 16),
                                                label: const Text("تعديل الاشتراك"),
                                              ),
                                              const SizedBox(width: 10),
                                              ElevatedButton.icon(
                                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.withValues(alpha: 0.15), foregroundColor: Colors.redAccent),
                                                onPressed: () {
                                                  setState(() {
                                                    _subscribers.remove(sub);
                                                  });
                                                },
                                                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                                                label: const Text("حذف المشترك"),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 30, thickness: 1, color: Colors.white10),
                                      Text(
                                        "👤 الحسابات المنشأة على جهاز العميل (${users.length} حساب):",
                                        style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: primaryColor),
                                      ),
                                      const SizedBox(height: 12),
                                      users.isEmpty
                                          ? const Text("لا يوجد حسابات منشأة مسجلة حالياً.", style: TextStyle(color: Colors.white30, fontSize: 13))
                                          : Wrap(
                                              spacing: 12,
                                              runSpacing: 12,
                                              children: users.map((u) {
                                                final uEmail = u['email']?.toString() ?? 'غير معروف';
                                                final uRole = u['role']?.toString() ?? 'staff';
                                                String uRoleText = "بائع/فني";
                                                Color rColor = Colors.blueAccent;
                                                if (uRole == 'manager') {
                                                  uRoleText = "مدير";
                                                  rColor = Colors.green;
                                                } else if (uRole == 'technician') {
                                                  uRoleText = "فني صيانة";
                                                  rColor = Colors.orange;
                                                }

                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF16222F),
                                                    borderRadius: BorderRadius.circular(8),
                                                    border: Border.all(color: Colors.white10),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Text(uEmail, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: rColor.withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(uRoleText, style: TextStyle(color: rColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({required String title, required int count, required Color color}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF15202F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.white60, fontFamily: 'Cairo'),
            ),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeygenView() {
    final primaryColor = const Color(0xFFD4AF37);
    final cardColor = const Color(0xFF15202F);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: 600,
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.2),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(36.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "توليد تراخيص العميل",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "توليد ملفات ومفاتيح التفعيل بناءً على رمز جهاز العميل (HWID)",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const Divider(height: 30, thickness: 1, color: Colors.white12),

                // HWID Input
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "رمز الجهاز الخاص بالعميل (Hardware ID):",
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _hwidController,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX",
                    suffixIcon: Icon(Icons.computer, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 12),

                // HWID Validation Status Box
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: _isValidHwid
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isValidHwid
                          ? Colors.green.withValues(alpha: 0.3)
                          : Colors.red.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isValidHwid
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                        color: _isValidHwid
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _validationStatus,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _isValidHwid
                                ? Colors.greenAccent
                                : Colors.redAccent,
                          ),
                        ),
                      ),
                      if (_decryptedSignature.isNotEmpty) ...[
                        Text(
                          "مُعرف الجهاز: ${_decryptedSignature.substring(0, 8)}...",
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Expiration Duration Selection
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    "مدة تفعيل البرنامج:",
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedDuration,
                  dropdownColor: const Color(0xFF15202F),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.timer_rounded,
                        color: Colors.white54),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: "5_MINUTES",
                        child: Text("5 دقائق (للتجريب) ⏳")),
                    DropdownMenuItem(
                        value: "1_DAY",
                        child: Text("يوم واحد (24 ساعة) 🗓️")),
                    DropdownMenuItem(
                        value: "1_MONTH",
                        child: Text("شهر واحد (30 يوم) 🗓️")),
                    DropdownMenuItem(
                        value: "3_MONTHS",
                        child: Text("3 أشهر (90 يوم) 🗓️")),
                    DropdownMenuItem(
                        value: "6_MONTHS",
                        child: Text("6 أشهر (180 يوم) 🗓️")),
                    DropdownMenuItem(
                        value: "1_YEAR",
                        child: Text("سنة واحدة (365 يوم) 🗓️")),
                    DropdownMenuItem(
                        value: "CUSTOM",
                        child: Text("تحديد تاريخ مخصص... 🛠️")),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedDuration = val ?? "1_YEAR";
                    });
                  },
                ),
                if (_selectedDuration == "CUSTOM") ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _customExpiryDate ??
                            DateTime.now().add(const Duration(days: 1)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                            const Duration(days: 3650)), // up to 10 years
                        locale: const Locale('ar', 'EG'),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.dark(
                                primary: primaryColor,
                                onPrimary: const Color(0xFF0D131E),
                                surface: const Color(0xFF15202F),
                                onSurface: Colors.white,
                              ),
                              dialogTheme: const DialogThemeData(
                                backgroundColor: Color(0xFF0D131E),
                              ),
                              textButtonTheme: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                  foregroundColor: primaryColor,
                                  textStyle: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() {
                          _customExpiryDate = picked;
                        });
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C2C3E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: primaryColor.withValues(
                              alpha:
                                  _customExpiryDate == null ? 0.3 : 0.8),
                          width: _customExpiryDate == null ? 1 : 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            color: _customExpiryDate == null
                                ? Colors.white54
                                : primaryColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _customExpiryDate == null
                                  ? "اختر تاريخ انتهاء التفعيل المخصص..."
                                  : "تاريخ الانتهاء المختار: ${_formatDate(_customExpiryDate!)}",
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 14,
                                fontWeight: _customExpiryDate == null
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                color: _customExpiryDate == null
                                    ? Colors.white54
                                    : Colors.white,
                              ),
                            ),
                          ),
                          if (_customExpiryDate != null)
                            const Icon(Icons.check_circle_outline_rounded,
                                color: Colors.greenAccent, size: 20),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Generate Actions
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.file_present_rounded, size: 22),
                    label: const Text(
                        "توليد ملف التفعيل وتصديره (license.lic)",
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 15)),
                    onPressed: _isValidHwid ? _generateLicense : null,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(
                          color: primaryColor.withValues(alpha: 0.6),
                          width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    icon: const Icon(Icons.lock_open_rounded, size: 22),
                    label: const Text(
                        "توليد كود إعادة تعيين بيانات الحماية (Reset Key)"),
                    onPressed: _isValidHwid ? _generateResetKey : null,
                  ),
                ),

                // Result Statuses
                if (_generatedKey.isNotEmpty) ...[
                  const Divider(
                      height: 30, thickness: 1, color: Colors.white12),
                  if (_fileStatus.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: primaryColor.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        _fileStatus,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          color: primaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      "مفتاح التفعيل النصي (Activation Key):",
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D131E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _generatedKey,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.copy, color: Colors.white70, size: 20),
                          onPressed: () {
                            Clipboard.setData(
                                ClipboardData(text: _generatedKey));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "📋 تم نسخ مفتاح التفعيل إلى الحافظة",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Color(0xFF15202F),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = const Color(0xFFD4AF37);
    final cardColor = const Color(0xFF15202F);
    final backgroundColor = const Color(0xFF0D131E);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            // Sidebar Navigation (Right Aligned)
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: cardColor,
                border: Border(
                  left: BorderSide(
                    color: primaryColor.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  // Logo / Header
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(Icons.vpn_key_rounded, color: primaryColor, size: 40),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "العطار استور",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  Text(
                    "نظام إدارة التراخيص",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 40),
                  // Sidebar Items
                  _buildSidebarItem(
                    index: 0,
                    title: "توليد كود التفعيل",
                    icon: Icons.vpn_key_rounded,
                  ),
                  _buildSidebarItem(
                    index: 1,
                    title: "إدارة المشتركين",
                    icon: Icons.supervised_user_circle_rounded,
                  ),
                  const Spacer(),
                  // Info Footer
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      "الإصدار 2.3",
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            
            // Main Content Area
            Expanded(
              child: _selectedTab == 0
                  ? _buildKeygenView()
                  : _buildSubscribersView(),
            ),
          ],
        ),
      ),
    );
  }
}
