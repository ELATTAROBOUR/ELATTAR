import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'printer_settings_service.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database_helper.dart';
import 'hwid_service.dart';
import 'package:file_picker/file_picker.dart';

import 'views/accessories_view.dart';
import 'views/dashboard_overview_view.dart';
import 'views/sales_view.dart';
import 'views/deferred_payments_view.dart';
import 'views/devices_view.dart';
import 'views/goods_receipt_view.dart';
import 'views/inventory_transfer_view.dart';
import 'views/inventory_view.dart';
import 'views/repairs_view.dart';
import 'views/spare_parts_view.dart';
import 'views/suppliers_view.dart';
import 'views/categories_view.dart';
import 'views/add_product_view.dart';
import 'views/users_view.dart';
import 'views/returns_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for Windows Desktop
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Migrate JSON data to SQLite if necessary (ignore if database is missing for now)
  try {
    await DatabaseHelper.checkAndMigrate();
    await DatabaseHelper.loadComplaintNumber();
  } on DatabaseMissingException {
    debugPrint(
        'Database is missing, migration deferred until user creates/restores database.');
  } catch (e) {
    debugPrint('Migration checking failed: $e');
  }

  ThemeMode initialTheme = ThemeMode.dark;
  try {
    initialTheme = await ThemeSettingsService.load();
  } catch (e) {
    debugPrint('Error loading initial theme: $e');
  }
  themeNotifier.value = initialTheme;
  runApp(const MobileRepairApp());
}

AppUser? currentLoggedInUser;

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

class ThemeSettingsService {
  static Future<ThemeMode> load() async {
    try {
      final isDark = await DatabaseHelper.getIsDarkSetting();
      if (isDark != null) {
        return isDark ? ThemeMode.dark : ThemeMode.light;
      }
    } catch (e) {
      debugPrint('ThemeSettingsService load error: $e');
    }
    return ThemeMode.dark;
  }

  static Future<void> save(ThemeMode mode) async {
    try {
      await DatabaseHelper.saveIsDarkSetting(mode == ThemeMode.dark);
    } catch (e) {
      debugPrint('ThemeSettingsService save error: $e');
    }
  }
}

class AppTheme {
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color scaffoldBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF121B26) : const Color(0xFFF0F4F8);
  static Color cardBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A2A3A) : Colors.white;
  static Color text(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF1A2A3A);
  static Color textMuted(BuildContext context) =>
      isDark(context) ? Colors.white70 : const Color(0xFF4A5D6E);
  static Color textDisabled(BuildContext context) =>
      isDark(context) ? Colors.white38 : Colors.black38;
  static Color border(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.black.withValues(alpha: 0.08);
  static Color surfaceTint(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.black.withValues(alpha: 0.04);

  static Color searchBarBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF16222F) : const Color(0xFFE2E8F0);
  static Color searchFieldBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF1C2C3E) : Colors.white;

  static Color getHoverColor(BuildContext context, String status) {
    if (isDark(context)) {
      switch (status) {
        case 'pending':
          return const Color(0xFF242F3D);
        case 'in_progress':
          return const Color(0xFF1D2B3A);
        case 'repaired':
          return const Color(0xFF1D3327);
        case 'delivered':
          return const Color(0xFF242A31);
        case 'rejected':
          return const Color(0xFF3D2424);
        case 'bought_from_customer':
          return const Color(0xFF2D1F35);
        default:
          return const Color(0xFF1A2A3A);
      }
    } else {
      switch (status) {
        case 'pending':
          return const Color(0xFFFFF7ED);
        case 'in_progress':
          return const Color(0xFFEFF6FF);
        case 'repaired':
          return const Color(0xFFF0FDF4);
        case 'delivered':
          return const Color(0xFFF8FAFC);
        case 'rejected':
          return const Color(0xFFFEF2F2);
        case 'bought_from_customer':
          return const Color(0xFFFAF5FF);
        default:
          return Colors.white;
      }
    }
  }
}

class MobileRepairApp extends StatelessWidget {
  const MobileRepairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, ThemeMode currentMode, __) {
        return MaterialApp(
          title: 'العطار استور - نظام صيانة الموبايلات',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            fontFamily: 'Cairo',
            scaffoldBackgroundColor: const Color(0xFFF0F4F8),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFFD4AF37),
              titleTextStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD4AF37),
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: Colors.white,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1A2A3A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.black12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFD4AF37), width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              labelStyle: const TextStyle(color: Color(0xFF4A5D6E)),
              hintStyle: const TextStyle(color: Colors.black38),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blue,
            fontFamily: 'Cairo',
            scaffoldBackgroundColor: const Color(0xFF121B26),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: Color(0xFF1A2A3A),
              foregroundColor: Color(0xFFD4AF37),
              titleTextStyle: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD4AF37),
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              color: const Color(0xFF1A2A3A),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1A2A3A),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1A2A3A),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFFD4AF37), width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              labelStyle: const TextStyle(color: Colors.white70),
              hintStyle: const TextStyle(color: Colors.white38),
            ),
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ar', 'EG'),
            Locale('en', 'US'),
          ],
          locale: const Locale('ar', 'EG'),
          home: const LicenseGatePage(),
        );
      },
    );
  }
}

enum LicensePageState {
  checking,
  dbMissing,
  complaintNumberInput,
  notActivated,
  notRegistered,
  login,
  authenticated,
}

String hashPassword(String password) {
  final bytes = utf8.encode(password.trim());
  final digest = sha256.convert(bytes);
  return digest.toString();
}

class LicenseGatePage extends StatefulWidget {
  const LicenseGatePage({super.key});

  @override
  State<LicenseGatePage> createState() => _LicenseGatePageState();
}

class _LicenseGatePageState extends State<LicenseGatePage> {
  LicensePageState _pageState = LicensePageState.checking;
  String _hwid = "";
  final TextEditingController _keyController = TextEditingController();
  String _errorMessage = "";
  bool _activating = false;

  // Registration Controllers
  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regEmailController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regConfirmPasswordController =
      TextEditingController();
  bool _regPasswordVisible = false;
  bool _regConfirmPasswordVisible = false;
  String _regError = "";
  bool _registering = false;

  // Login Controllers
  final TextEditingController _loginEmailController = TextEditingController();
  final TextEditingController _loginPasswordController =
      TextEditingController();
  bool _loginPasswordVisible = false;
  String _loginError = "";
  bool _loggingIn = false;

  // Complaint Number Controller
  final TextEditingController _complaintController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkLicense();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _regUsernameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _complaintController.dispose();
    super.dispose();
  }

  void _showForgotDetailsDialog() async {
    final email = await DatabaseHelper.getClientEmail() ?? "";

    if (!mounted) return;

    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);
    final cardBgColor = isDark ? const Color(0xFF15202F) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMutedColor = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: cardBgColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(
                  color: primaryColor.withValues(alpha: 0.5), width: 1.5),
            ),
            title: Row(
              children: [
                Icon(Icons.security_rounded, color: primaryColor, size: 28),
                const SizedBox(width: 10),
                Text(
                  "بيانات استعادة الحماية",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "للإستعادة، يرجى إرسال رمز الجهاز (Hardware ID) التالي إلى الدعم الفني لتوليد كود إعادة التعيين الخاص بك.",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "البريد الإلكتروني المسجل:",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textMutedColor,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D131E)
                        : const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: textColor.withValues(alpha: 0.1)),
                  ),
                  child: SelectableText(
                    email.isNotEmpty ? email : "لا يوجد بريد مسجل",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "رمز الجهاز الخاص بك (Hardware ID):",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textMutedColor,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF0D131E)
                        : const Color(0xFFF0F4F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: textColor.withValues(alpha: 0.1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          _hwid,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: primaryColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.copy, color: primaryColor, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _hwid));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                "📋 تم نسخ رمز الجهاز إلى الحافظة",
                                textAlign: TextAlign.center,
                                style: TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: Color(0xFF1A2A3A),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  "إغلاق",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _clearLocalLicense() async {
    try {
      await DatabaseHelper.saveActivationKey("");
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      if (localAppData.isNotEmpty) {
        final hiddenFile = File("$localAppData/Microsoft/Windows/Shell/wincheck.dat");
        if (await hiddenFile.exists()) {
          await hiddenFile.delete();
        }
      }
    } catch (e) {
      debugPrint("Error clearing local license: $e");
    }
  }

  Future<void> _checkLicense() async {
    setState(() {
      _pageState = LicensePageState.checking;
    });

    final hwid = await HwidService.getHWID();
    setState(() {
      _hwid = hwid;
    });

    // Check if database exists
    bool dbExists = true;
    try {
      await DatabaseHelper.db;
    } on DatabaseMissingException {
      dbExists = false;
    } catch (e) {
      if (e.toString().contains('Database is missing')) {
        dbExists = false;
      }
    }

    if (!dbExists) {
      setState(() {
        _pageState = LicensePageState.dbMissing;
      });
      return;
    }

    await DatabaseHelper.loadComplaintNumber();

    bool isLicenseValid = false;
    bool githubCheckAttempted = false;
    bool hwidFoundInCentral = false;
    String? centralError;

    // Fetch central subscribers.db from GitHub if internet is available
    try {
      final url = Uri.parse('https://raw.githubusercontent.com/mojlinux58/ELATTAR/DB_SUB/subscribers.db');
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        githubCheckAttempted = true;
        final tempDir = await getTemporaryDirectory();
        final tempDbFile = File('${tempDir.path}/temp_subscribers.db');
        await tempDbFile.writeAsBytes(response.bodyBytes);

        // Open central SQLite database
        final db = await databaseFactory.openDatabase(tempDbFile.path);
        
        final cleanHwid = _hwid.replaceAll('-', '').toUpperCase();
        final List<Map<String, dynamic>> results = await db.query(
          'subscribers',
          where: 'UPPER(REPLACE(hwid, "-", "")) = ?',
          whereArgs: [cleanHwid],
        );

        if (results.isNotEmpty) {
          hwidFoundInCentral = true;
          final clientData = results.first;
          final status = clientData['status']?.toString().toLowerCase();
          final expiry = clientData['expiryDate']?.toString();

          if (status == 'blocked' || status == 'محظور') {
            centralError = "تم حظر هذا الاشتراك لعدم سداد المستحقات أو لمخالفة الشروط. يرجى التواصل مع الدعم الفني.";
            await _clearLocalLicense();
          } else if (status == 'inactive' || status == 'غير نشط' || status == 'غير متفعل') {
            centralError = "هذا الاشتراك غير نشط حالياً. يرجى التواصل مع الدعم الفني لتفعيل الخدمة.";
            await _clearLocalLicense();
          } else if (expiry != null) {
            if (expiry == 'LIFETIME') {
              final newKey = HwidService.generateKey(_hwid, 'LIFETIME');
              await DatabaseHelper.saveActivationKey(newKey);
              HwidService.expiryDate = 'LIFETIME';
              final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
              if (localAppData.isNotEmpty) {
                final hiddenFile = File("$localAppData/Microsoft/Windows/Shell/wincheck.dat");
                await hiddenFile.parent.create(recursive: true);
                await hiddenFile.writeAsString(newKey);
              }
              isLicenseValid = true;
            } else {
              final expDate = DateTime.parse(expiry);
              final currentDate = DateTime.now();
              final diff = expDate.difference(DateTime(currentDate.year, currentDate.month, currentDate.day)).inDays;
              if (diff < 0) {
                centralError = "انتهت فترة الاشتراك الخاصة بك ($expiry). يرجى التجديد للاستمرار.";
                await _clearLocalLicense();
              } else {
                // Automatically generate/update local license key
                final newKey = HwidService.generateKey(_hwid, expiry);
                await DatabaseHelper.saveActivationKey(newKey);
                HwidService.expiryDate = expiry;
                final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
                if (localAppData.isNotEmpty) {
                  final hiddenFile = File("$localAppData/Microsoft/Windows/Shell/wincheck.dat");
                  await hiddenFile.parent.create(recursive: true);
                  await hiddenFile.writeAsString(newKey);
                }
                isLicenseValid = true;
              }
            }
          }
        }
        await db.close();
        try {
          await tempDbFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Central subscription check failed/timed out: $e");
    }

    if (githubCheckAttempted && hwidFoundInCentral) {
      if (centralError != null) {
        setState(() {
          _pageState = LicensePageState.notActivated;
          _errorMessage = centralError ?? "الاشتراك غير صالح.";
        });
        return;
      }
    } else {
      // Fallback to local validation if offline or not registered on central database
      
      // 1. Check for local license.lic file
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final licenseFile = File("$exeDir/license.lic");
        if (await licenseFile.exists()) {
          final content = (await licenseFile.readAsString()).trim();
          final isValid = await HwidService.verifyLicense(content);
          if (isValid) {
            await DatabaseHelper.saveActivationKey(content);

            final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
            if (localAppData.isNotEmpty) {
              final hiddenFile =
                  File("$localAppData/Microsoft/Windows/Shell/wincheck.dat");
              await hiddenFile.parent.create(recursive: true);
              await hiddenFile.writeAsString(content);
            }

            try {
              await licenseFile.delete();
            } catch (e) {
              debugPrint("Failed to delete local license file: $e");
            }

            isLicenseValid = true;
          }
        }
      } catch (e) {
        debugPrint("Error checking license.lic: $e");
      }

      // 2. Check stealth AppData file
      if (!isLicenseValid) {
        String? hiddenKey;
        try {
          final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
          if (localAppData.isNotEmpty) {
            final hiddenFile =
                File("$localAppData/Microsoft/Windows/Shell/wincheck.dat");
            if (await hiddenFile.exists()) {
              hiddenKey = (await hiddenFile.readAsString()).trim();
            }
          }
        } catch (e) {
          debugPrint("Error reading stealth appdata key: $e");
        }

        if (hiddenKey != null) {
          final isValid = await HwidService.verifyLicense(hiddenKey);
          if (isValid) {
            await DatabaseHelper.saveActivationKey(hiddenKey);
            isLicenseValid = true;
          }
        }
      }

      // 3. Check SQLite settings table
      if (!isLicenseValid) {
        final savedKey = await DatabaseHelper.getActivationKey();
        if (savedKey != null) {
          final isValid = await HwidService.verifyLicense(savedKey);
          if (isValid) {
            try {
              final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
              if (localAppData.isNotEmpty) {
                final hiddenFile =
                    File("$localAppData/Microsoft/Windows/Shell/wincheck.dat");
                await hiddenFile.parent.create(recursive: true);
                await hiddenFile.writeAsString(savedKey);
              }
            } catch (e) {
              debugPrint("Error writing stealth appdata backup: $e");
            }
            isLicenseValid = true;
          }
        }
      }
    }

    if (isLicenseValid) {
      final email = await DatabaseHelper.getClientEmail();
      final passHash = await DatabaseHelper.getClientPasswordHash();

      if (email == null ||
          email.isEmpty ||
          passHash == null ||
          passHash.isEmpty) {
        setState(() {
          _pageState = LicensePageState.notRegistered;
        });
      } else {
        setState(() {
          _pageState = LicensePageState.login;
        });
      }
    } else {
      setState(() {
        _pageState = LicensePageState.notActivated;
        if (githubCheckAttempted && hwidFoundInCentral && centralError != null) {
          _errorMessage = centralError;
        } else {
          _errorMessage = "";
        }
      });
    }
  }

  Future<void> _activate() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _errorMessage = "الرجاء إدخال مفتاح التفعيل";
      });
      return;
    }

    setState(() {
      _activating = true;
      _errorMessage = "";
    });

    await Future.delayed(const Duration(milliseconds: 800));

    final isValid = await HwidService.verifyLicense(key);
    if (isValid) {
      await DatabaseHelper.saveActivationKey(key);

      try {
        final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
        if (localAppData.isNotEmpty) {
          final hiddenFile =
              File("$localAppData/Microsoft/Windows/Shell/wincheck.dat");
          await hiddenFile.parent.create(recursive: true);
          await hiddenFile.writeAsString(key);
        }
      } catch (e) {
        debugPrint("Error writing stealth appdata: $e");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "✅ تم تفعيل البرنامج بنجاح! شكراً لك.",
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }

      final email = await DatabaseHelper.getClientEmail();
      final passHash = await DatabaseHelper.getClientPasswordHash();

      setState(() {
        _activating = false;
        if (email == null ||
            email.isEmpty ||
            passHash == null ||
            passHash.isEmpty) {
          _pageState = LicensePageState.notRegistered;
        } else {
          _pageState = LicensePageState.login;
        }
      });
    } else {
      setState(() {
        _activating = false;
        _errorMessage =
            "مفتاح التفعيل غير صحيح! يرجى التحقق والتجربة مرة أخرى.";
      });
    }
  }

  Widget _buildDbMissingScreen() {
    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMutedColor = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    return _buildCard(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.storage_rounded,
            color: Colors.orange,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "قاعدة البيانات غير موجودة",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.orange,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "لم يتم العثور على قاعدة بيانات البرنامج على هذا الجهاز.\nيرجى اختيار أحد الخيارين التاليين:",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            color: textColor,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: const Color(0xFF1A2A3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 3,
            ),
            onPressed: _handleCreateNewDatabase,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
            label: const Text(
              "إنشاء قاعدة بيانات جديدة (فارغة)",
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 55,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF1A2A3A) : Colors.white,
              foregroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
              ),
              elevation: 1,
            ),
            onPressed: _handleRestoreDatabase,
            icon: const Icon(Icons.file_open_rounded, size: 22),
            label: const Text(
              "استرداد قاعدة بيانات من ملف",
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: primaryColor.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: primaryColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "ملف قاعدة البيانات بصيغة ELATTAR_STORE.db يمكن استيراده من أي نسخة احتياطية سابقة.",
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    color: textMutedColor,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleCreateNewDatabase() async {
    setState(() {
      _pageState = LicensePageState.checking;
    });

    bool success = false;
    try {
      await DatabaseHelper.reset();
      DatabaseHelper.forceCreate = true;
      await DatabaseHelper.db;
      await DatabaseHelper.checkAndMigrate();
      success = true;
    } catch (e) {
      debugPrint("Error creating new database: $e");
    }

    if (success) {
      setState(() {
        _pageState = LicensePageState.complaintNumberInput;
      });
    } else {
      _checkLicense();
    }
  }

  Future<void> _handleRestoreDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        dialogTitle: "اختر ملف قاعدة البيانات (ELATTAR_STORE.db)",
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        setState(() {
          _pageState = LicensePageState.checking;
        });

        final success = await DatabaseHelper.importDatabase(filePath);
        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "✅ تم استيراد قاعدة البيانات بنجاح!",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "فشل استيراد قاعدة البيانات! تأكد من صحة الملف.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
                ),
                backgroundColor: Colors.redAccent,
                duration: Duration(seconds: 3),
              ),
            );
          }
          setState(() {
            _pageState = LicensePageState.dbMissing;
          });
          return;
        }
      } else {
        return;
      }
    } catch (e) {
      debugPrint("Error restoring database: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "حدث خطأ: $e",
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 16),
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() {
        _pageState = LicensePageState.dbMissing;
      });
      return;
    }

    _checkLicense();
  }

  Widget _buildComplaintNumberInputScreen() {
    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMutedColor = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    return _buildCard(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.contact_phone_rounded,
            color: primaryColor,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "تهيئة رقم الشكاوى",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "يرجى إدخال رقم الشكاوى والاتصال الخاص بالمحل لاعتماده في فواتير الصيانة والرسائل النصية.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            color: textMutedColor,
            height: 1.5,
          ),
        ),
        const Divider(height: 30, thickness: 1, color: Colors.grey),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "رقم الشكاوى:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _complaintController,
          keyboardType: TextInputType.phone,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: "مثال: 01552199854",
            prefixIcon: Icon(Icons.phone_android_rounded,
                color: primaryColor.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: const Color(0xFF1A2A3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 3,
            ),
            onPressed: _handleSaveComplaintNumber,
            child: const Text(
              "حفظ ومتابعة",
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleSaveComplaintNumber() async {
    final number = _complaintController.text.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "الرجاء إدخال رقم شكاوى صالح",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    try {
      await DatabaseHelper.saveSetting('complaintNumber', number);
      DatabaseHelper.complaintNumber = number;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "✅ تم حفظ رقم الشكاوى الجديد بنجاح!",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("Error saving complaint number setting: $e");
    }

    if (!mounted) return;
    _checkLicense();
  }

  Widget _buildCard({required List<Widget> children}) {
    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);
    final cardBgColor = isDark ? const Color(0xFF1A2A3A) : Colors.white;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 550,
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(36.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isValidGmail(String email) {
    final regExp = RegExp(r'^[a-zA-Z0-9\._%+-]+@gmail\.com$');
    return regExp.hasMatch(email.trim().toLowerCase());
  }

  Future<void> _handleRegister() async {
    final username = _regUsernameController.text.trim();
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text.trim();
    final confirmPassword = _regConfirmPasswordController.text.trim();

    if (username.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      setState(() {
        _regError = "الرجاء ملء جميع الحقول المطلوبة";
      });
      return;
    }

    if (!_isValidGmail(email)) {
      setState(() {
        _regError =
            "يجب أن يكون البريد الإلكتروني حساب Gmail صالحاً (ينتهي بـ @gmail.com)";
      });
      return;
    }

    if (password.length < 8) {
      setState(() {
        _regError = "يجب ألا تقل كلمة المرور عن 8 أحرف أو أرقام";
      });
      return;
    }

    if (password != confirmPassword) {
      setState(() {
        _regError = "كلمتا المرور غير متطابقتين";
      });
      return;
    }

    setState(() {
      _registering = true;
      _regError = "";
    });

    await Future.delayed(const Duration(milliseconds: 600));

    try {
      final hashed = hashPassword(password);
      await DatabaseHelper.saveClientName(username);
      await DatabaseHelper.saveClientHwid(_hwid);
      await DatabaseHelper.saveClientEmail(email);
      await DatabaseHelper.saveClientPasswordHash(hashed);

      final newUser = AppUser(
        email: email,
        passwordHash: hashed,
        role: 'manager',
      );
      await DatabaseHelper.saveUser(newUser);
      currentLoggedInUser = newUser;

      setState(() {
        _registering = false;
        _pageState = LicensePageState.authenticated;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "✅ تم إنشاء حساب حماية النظام بنجاح!",
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _registering = false;
        _regError = "حدث خطأ أثناء حفظ البيانات: $e";
      });
    }
  }

  Future<void> _handleLogin() async {
    final email = _loginEmailController.text.trim();
    final password = _loginPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _loginError = "الرجاء إدخال البريد الإلكتروني وكلمة المرور";
      });
      return;
    }

    setState(() {
      _loggingIn = true;
      _loginError = "";
    });

    await Future.delayed(const Duration(milliseconds: 500));

    // Check if the entered password is a password reset key for this device
    final isResetKey = await HwidService.verifyResetKey(password);
    if (isResetKey) {
      await DatabaseHelper.saveClientEmail("");
      await DatabaseHelper.saveClientPasswordHash("");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "⚙️ تم إعادة تعيين بيانات الحماية بنجاح! يرجى إنشاء حساب جديد.",
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
            ),
            backgroundColor: Colors.blueAccent,
            duration: Duration(seconds: 4),
          ),
        );
      }

      setState(() {
        _loggingIn = false;
        _pageState = LicensePageState.notRegistered;
        _regEmailController.clear();
        _regPasswordController.clear();
        _regConfirmPasswordController.clear();
        _loginPasswordController.clear();
      });
      return;
    }

    final enteredHash = hashPassword(password);
    
    // Find user by email
    AppUser? user = await DatabaseHelper.getUserByEmail(email);
    
    // If not found by email, see if the entered 'email' (username) matches the clientName
    if (user == null) {
      final storedName = await DatabaseHelper.getClientName();
      final storedEmail = await DatabaseHelper.getClientEmail();
      if (storedName != null && storedName.trim().toLowerCase() == email.toLowerCase() && storedEmail != null) {
        user = await DatabaseHelper.getUserByEmail(storedEmail);
      }
    }

    bool isLoginValid = false;
    if (user != null) {
      if (user.passwordHash == enteredHash) {
        currentLoggedInUser = user;
        isLoginValid = true;
      }
    } else {
      // Fallback/backward compatibility for first client settings user
      final storedEmail = await DatabaseHelper.getClientEmail();
      final storedHash = await DatabaseHelper.getClientPasswordHash();
      final storedName = await DatabaseHelper.getClientName();
      if (((storedEmail?.trim().toLowerCase() == email.toLowerCase()) || 
           (storedName?.trim().toLowerCase() == email.toLowerCase())) &&
          storedHash == enteredHash && storedEmail != null) {
        final newMgr =
            AppUser(email: storedEmail, passwordHash: enteredHash, role: 'manager');
        await DatabaseHelper.saveUser(newMgr);
        currentLoggedInUser = newMgr;
        isLoginValid = true;
      }
    }

    if (isLoginValid) {
      setState(() {
        _loggingIn = false;
        _pageState = LicensePageState.authenticated;
      });
    } else {
      setState(() {
        _loggingIn = false;
        _loginError = "البريد الإلكتروني أو كلمة المرور غير صحيحة!";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pageState == LicensePageState.checking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37)),
              ),
              SizedBox(height: 20),
              Text(
                "جاري التحقق من ترخيص وأمان البرنامج...",
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD4AF37),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_pageState == LicensePageState.authenticated) {
      return MainScreen(
        onLogout: () {
          setState(() {
            _pageState = LicensePageState.login;
            _loginPasswordController.clear();
          });
        },
      );
    }

    switch (_pageState) {
      case LicensePageState.notActivated:
        return _buildActivationScreen();
      case LicensePageState.notRegistered:
        return _buildRegistrationScreen();
      case LicensePageState.login:
        return _buildLoginScreen();
      case LicensePageState.dbMissing:
        return _buildDbMissingScreen();
      case LicensePageState.complaintNumberInput:
        return _buildComplaintNumberInputScreen();
      default:
        return _buildActivationScreen();
    }
  }

  Widget _buildActivationScreen() {
    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMutedColor = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    return _buildCard(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.vpn_key_rounded,
            color: primaryColor,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "تفعيل نظام العطار استور",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "نسخة مرخصة ومحمية برمز الجهاز (Hardware ID)",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            color: textMutedColor,
          ),
        ),
        const Divider(height: 40, thickness: 1, color: Colors.grey),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "رمز الجهاز الخاص بك (Hardware ID):",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121B26) : const Color(0xFFF0F4F8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: textColor.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _hwid,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: "نسخ رمز الجهاز",
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor.withValues(alpha: 0.2),
                    foregroundColor: primaryColor,
                    elevation: 0,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _hwid));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "📋 تم نسخ رمز الجهاز إلى الحافظة",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                        backgroundColor: Color(0xFF1A2A3A),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text(
                    "نسخ",
                    style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "أدخل مفتاح التفعيل:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _keyController,
          style: TextStyle(color: textColor, fontSize: 16, letterSpacing: 1.2),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: "XXXXX-XXXXX-XXXXX-XXXXX",
            hintStyle: TextStyle(
              color: isDark ? Colors.white30 : Colors.black38,
              letterSpacing: 1.2,
            ),
            suffixIcon:
                Icon(Icons.key, color: primaryColor.withValues(alpha: 0.7)),
          ),
          onChanged: (_) {
            if (_errorMessage.isNotEmpty) {
              setState(() {
                _errorMessage = "";
              });
            }
          },
        ),
        if (_errorMessage.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Colors.redAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: const Color(0xFF1A2A3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 3,
            ),
            onPressed: _activating ? null : _activate,
            child: _activating
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF1A2A3A)),
                    ),
                  )
                : const Text(
                    "تفعيل البرنامج الآن",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.headset_mic_rounded,
                      color: primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    "للحصول على مفتاح التفعيل، يرجى التواصل مع الدعم الفني:",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textMutedColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                "المهندس المسؤول: 01552199854",
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRegistrationScreen() {
    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMutedColor = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    return _buildCard(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.security_rounded,
            color: primaryColor,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "حماية نظام العطار استور",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "قم بإنشاء حساب لحماية تطبيقك وبيانات الصيانة الخاصة بك.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            color: textMutedColor,
          ),
        ),
        const Divider(height: 30, thickness: 1, color: Colors.grey),

        // Username Field
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "اسم المستخدم / اسم المحل:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _regUsernameController,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: "أدخل اسم المستخدم أو اسم المحل",
            prefixIcon: Icon(Icons.person_outline_rounded,
                color: primaryColor.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(height: 16),

        // Gmail Field
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "البريد الإلكتروني (يجب أن يكون حساب Gmail):",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _regEmailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: "example@gmail.com",
            prefixIcon: Icon(Icons.mail_outline_rounded,
                color: primaryColor.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(height: 16),

        // Password Field
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "كلمة المرور:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _regPasswordController,
          obscureText: !_regPasswordVisible,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: "أدخل كلمة المرور (8 أحرف على الأقل)",
            prefixIcon: Icon(Icons.lock_outline_rounded,
                color: primaryColor.withValues(alpha: 0.7)),
            suffixIcon: IconButton(
              icon: Icon(
                _regPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: textColor.withValues(alpha: 0.6),
              ),
              onPressed: () {
                setState(() {
                  _regPasswordVisible = !_regPasswordVisible;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Confirm Password Field
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "تأكيد كلمة المرور:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _regConfirmPasswordController,
          obscureText: !_regConfirmPasswordVisible,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: "أعد إدخال كلمة المرور للتأكيد",
            prefixIcon: Icon(Icons.lock_clock_outlined,
                color: primaryColor.withValues(alpha: 0.7)),
            suffixIcon: IconButton(
              icon: Icon(
                _regConfirmPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: textColor.withValues(alpha: 0.6),
              ),
              onPressed: () {
                setState(() {
                  _regConfirmPasswordVisible = !_regConfirmPasswordVisible;
                });
              },
            ),
          ),
          onSubmitted: (_) {
            if (!_registering) {
              _handleRegister();
            }
          },
        ),

        if (_regError.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _regError,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Colors.redAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 32),

        // Submit Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: const Color(0xFF1A2A3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 3,
            ),
            onPressed: _registering ? null : _handleRegister,
            child: _registering
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF1A2A3A)),
                    ),
                  )
                : const Text(
                    "إنشاء الحساب وتفعيل الحماية",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginScreen() {
    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMutedColor = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    // Auto prepopulate registered email if controller is empty
    if (_loginEmailController.text.isEmpty) {
      DatabaseHelper.getClientEmail().then((email) {
        if (email != null && email.isNotEmpty && mounted) {
          setState(() {
            _loginEmailController.text = email;
          });
        }
      });
    }

    return _buildCard(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(
              color: primaryColor.withValues(alpha: 0.5),
              width: 2,
            ),
          ),
          child: Icon(
            Icons.lock_person_rounded,
            color: primaryColor,
            size: 48,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          "تسجيل الدخول للنظام",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "الرجاء إدخال بيانات الحماية للوصول للوحة التحكم.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            color: textMutedColor,
          ),
        ),
        const Divider(height: 30, thickness: 1, color: Colors.grey),

        // Email field
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "البريد الإلكتروني أو اسم المستخدم:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _loginEmailController,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: "أدخل البريد الإلكتروني أو اسم المستخدم",
            prefixIcon: Icon(Icons.mail_outline_rounded,
                color: primaryColor.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(height: 16),

        // Password field
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "كلمة المرور:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _loginPasswordController,
          obscureText: !_loginPasswordVisible,
          style: TextStyle(color: textColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: "أدخل كلمة المرور الخاصة بك",
            prefixIcon: Icon(Icons.lock_outline_rounded,
                color: primaryColor.withValues(alpha: 0.7)),
            suffixIcon: IconButton(
              icon: Icon(
                _loginPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: textColor.withValues(alpha: 0.6),
              ),
              onPressed: () {
                setState(() {
                  _loginPasswordVisible = !_loginPasswordVisible;
                });
              },
            ),
          ),
          onSubmitted: (_) {
            if (!_loggingIn) {
              _handleLogin();
            }
          },
        ),
        if (_loginError.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            _loginError,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Colors.redAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Login button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: const Color(0xFF1A2A3A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 3,
            ),
            onPressed: _loggingIn ? null : _handleLogin,
            child: _loggingIn
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF1A2A3A)),
                    ),
                  )
                : const Text(
                    "تسجيل الدخول",
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _showForgotDetailsDialog,
            child: Text(
              "هل نسيت بيانات الحماية؟",
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13,
                color: primaryColor,
                fontWeight: FontWeight.bold,
                decoration: TextDecoration.underline,
                decorationColor: primaryColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class MenuItemDef {
  final String title;
  final IconData icon;
  final Widget view;
  final List<String> allowedRoles;

  MenuItemDef({
    required this.title,
    required this.icon,
    required this.view,
    required this.allowedRoles,
  });
}

class MainScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const MainScreen({super.key, this.onLogout});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  late final List<MenuItemDef> _filteredMenuItems;

  @override
  void initState() {
    super.initState();

    final allMenuItems = [
      MenuItemDef(
        title: 'لوحة التحكم الإجمالية',
        icon: Icons.grid_view_rounded,
        view: DashboardOverviewView(
          onNavigate: (index) {
            _handleDashboardNavigation(index);
          },
        ),
        allowedRoles: ['manager'],
      ),
      MenuItemDef(
        title: '➕ إضافة منتج جديد',
        icon: Icons.add_circle_outline_rounded,
        view: const AddProductView(),
        allowedRoles: ['manager', 'staff'],
      ),
      MenuItemDef(
        title: '💵 بيع منتج من المحل',
        icon: Icons.point_of_sale_rounded,
        view: const SalesView(),
        allowedRoles: ['manager', 'staff'],
      ),
      MenuItemDef(
        title: '🔄 المرتجعات',
        icon: Icons.assignment_return_rounded,
        view: const ReturnsView(),
        allowedRoles: ['manager', 'staff'],
      ),
      MenuItemDef(
        title: '🔧 الصيانة والإصلاحات',
        icon: Icons.build_circle_rounded,
        view: const RepairsView(),
        allowedRoles: ['manager', 'staff', 'technician'],
      ),
      MenuItemDef(
        title: '🗂️ إدارة التصنيفات',
        icon: Icons.category_rounded,
        view: const CategoriesView(),
        allowedRoles: ['manager', 'staff'],
      ),
      MenuItemDef(
        title: '⚙️ قطع غيار الصيانة',
        icon: Icons.settings_suggest_rounded,
        view: const SparePartsView(),
        allowedRoles: ['manager', 'staff', 'technician'],
      ),
      MenuItemDef(
        title: '🎧 إدارة الاكسسوارات',
        icon: Icons.headset_rounded,
        view: const AccessoriesView(),
        allowedRoles: ['manager', 'staff'],
      ),
      MenuItemDef(
        title: '📱 إدارة الأجهزة',
        icon: Icons.phone_iphone_rounded,
        view: const DevicesView(),
        allowedRoles: ['manager', 'staff'],
      ),
      MenuItemDef(
        title: '📦 المخزن والجرد',
        icon: Icons.inventory_rounded,
        view: const InventoryView(),
        allowedRoles: ['manager'],
      ),
      MenuItemDef(
        title: '📥 استلام بضائع (الموردين)',
        icon: Icons.playlist_add_check_rounded,
        view: const GoodsReceiptView(),
        allowedRoles: ['manager'],
      ),
      MenuItemDef(
        title: '🔄 تحويلات المخازن',
        icon: Icons.swap_horizontal_circle_rounded,
        view: const InventoryTransferView(),
        allowedRoles: ['manager'],
      ),
      MenuItemDef(
        title: '💳 حسابات العملاء الآجلة',
        icon: Icons.account_balance_wallet_rounded,
        view: const DeferredPaymentsView(),
        allowedRoles: ['manager', 'staff'],
      ),
      MenuItemDef(
        title: '🤝 حسابات الموردين',
        icon: Icons.people_rounded,
        view: const SuppliersView(),
        allowedRoles: ['manager'],
      ),
      MenuItemDef(
        title: '👥 إدارة المستخدمين',
        icon: Icons.supervised_user_circle_rounded,
        view: const UsersView(),
        allowedRoles: ['manager'],
      ),
    ];

    final role = currentLoggedInUser?.role ?? 'manager';
    _filteredMenuItems =
        allMenuItems.where((item) => item.allowedRoles.contains(role)).toList();
    _selectedIndex = 0;
  }

  void _handleDashboardNavigation(int originalIndex) {
    String? targetTitle;
    switch (originalIndex) {
      case 2:
        targetTitle = '💵 بيع منتج من المحل';
        break;
      case 3:
        targetTitle = '🔧 الصيانة والإصلاحات';
        break;
      case 8:
        targetTitle = '📦 المخزن والجرد';
        break;
      case 9:
        targetTitle = '📥 استلام بضائع (الموردين)';
        break;
    }
    if (targetTitle != null) {
      final idx =
          _filteredMenuItems.indexWhere((item) => item.title == targetTitle);
      if (idx != -1) {
        setState(() {
          _selectedIndex = idx;
        });
      }
    }
  }

  void _showPrinterSettings() {
    showDialog(
      context: context,
      builder: (context) => _PrinterSettingsDialog(),
    );
  }

  void _toggleTheme() async {
    final current = themeNotifier.value;
    final newMode =
        current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    themeNotifier.value = newMode;
    await ThemeSettingsService.save(newMode);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textColor = AppTheme.text(context);
    final sidebarBg =
        isDark ? const Color(0xFF16222F) : const Color(0xFFEAF0F6);
    final activeBg = isDark ? const Color(0xFF1E2F41) : Colors.white;
    final primaryGold = const Color(0xFFD4AF37);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        body: Row(
          children: [
            // Sidebar Navigation (Right Aligned)
            Container(
              width: 280,
              color: sidebarBg,
              child: Column(
                children: [
                  // App Branding / Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.store_rounded,
                          color: Color(0xFFD4AF37),
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'العطار استور 2.0',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryGold,
                            fontFamily: 'Cairo',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'نظام الإدارة الشامل - أوفلاين',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted(context),
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, thickness: 0.5, color: Colors.grey),
                  const SizedBox(height: 16),

                  // Menu Items
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredMenuItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredMenuItems[index];
                        final isSelected = _selectedIndex == index;
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedIndex = index;
                              });
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 16),
                              decoration: BoxDecoration(
                                color:
                                    isSelected ? activeBg : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                border: isSelected
                                    ? Border.all(
                                        color:
                                            primaryGold.withValues(alpha: 0.5),
                                        width: 1)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    color: isSelected
                                        ? primaryGold
                                        : textColor.withValues(alpha: 0.7),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      item.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected
                                            ? primaryGold
                                            : textColor,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Bottom Settings Bar
                  const Divider(height: 1, thickness: 0.5, color: Colors.grey),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        // Toggle Theme
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            color: primaryGold,
                            size: 20,
                          ),
                          title: Text(
                            isDark ? 'الوضع المضيء' : 'الوضع الداكن',
                            style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontFamily: 'Cairo'),
                          ),
                          onTap: _toggleTheme,
                        ),
                        // Printer Settings
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.print_rounded,
                            color: textColor.withValues(alpha: 0.7),
                            size: 20,
                          ),
                          title: Text(
                            'إعدادات الطابعة',
                            style: TextStyle(
                                color: textColor,
                                fontSize: 14,
                                fontFamily: 'Cairo'),
                          ),
                          onTap: _showPrinterSettings,
                        ),
                        // Logout
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.logout_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          title: const Text(
                            'تسجيل الخروج',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 14,
                                fontFamily: 'Cairo'),
                          ),
                          onTap: widget.onLogout,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 0.5, color: Colors.grey),

            // Main View Area (Left Aligned)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: KeyedSubtree(
                  key: ValueKey<int>(_selectedIndex),
                  child: _filteredMenuItems[_selectedIndex].view,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TicketCard extends StatefulWidget {
  final Ticket ticket;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(Ticket) onPrintLabel;
  final Function(Ticket) onPrintReceipt;
  final Function(Ticket) onPreviewLabel;
  final Function(Ticket) onPreviewReceipt;
  final Function(Ticket, String) onStatusChanged;

  const TicketCard({
    super.key,
    required this.ticket,
    required this.onEdit,
    required this.onDelete,
    required this.onPrintLabel,
    required this.onPrintReceipt,
    required this.onPreviewLabel,
    required this.onPreviewReceipt,
    required this.onStatusChanged,
  });

  @override
  State<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> {
  bool _isHovered = false;

  void _showBuyDeviceDialog(BuildContext context, Ticket ticket) async {
    final costController = TextEditingController(text: '0.0');
    final priceController = TextEditingController(text: '0.0');
    final imeiController =
        TextEditingController(text: ticket.complaintNumber ?? '');

    final warehouses = await DatabaseHelper.loadWarehouses();
    String selectedWarehouse =
        warehouses.isNotEmpty ? warehouses.first.name : 'المحل الرئيسي';

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final primaryGold = const Color(0xFFD4AF37);
          final textColor = AppTheme.text(context);

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: AppTheme.cardBg(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      color: primaryGold, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'شراء جهاز عميل للمستعمل',
                    style: TextStyle(
                        color: primaryGold,
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'جهاز: ${ticket.deviceModel}\nالعميل: ${ticket.customerName}',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: costController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(color: textColor),
                        decoration: const InputDecoration(
                            labelText: 'سعر الشراء من العميل (ج.م) *'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(color: textColor),
                        decoration: const InputDecoration(
                            labelText: 'سعر البيع المقترح للمستعمل (ج.م) *'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: imeiController,
                        style: TextStyle(color: textColor),
                        decoration: const InputDecoration(
                            labelText: 'رقم السيريال / IMEI'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedWarehouse,
                        dropdownColor: AppTheme.cardBg(context),
                        style: TextStyle(color: textColor, fontSize: 16),
                        decoration:
                            const InputDecoration(labelText: 'المخزن *'),
                        items: warehouses
                            .map((w) => DropdownMenuItem(
                                value: w.name, child: Text(w.name)))
                            .toList(),
                        onChanged: (val) {
                          setDialogState(() {
                            selectedWarehouse = val!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('إلغاء',
                      style: TextStyle(
                          color: AppTheme.textMuted(context), fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGold,
                    foregroundColor: const Color(0xFF1A2A3A),
                  ),
                  onPressed: () async {
                    final cost = double.tryParse(costController.text) ?? 0.0;
                    final price = double.tryParse(priceController.text) ?? 0.0;

                    final device = Device(
                      model: ticket.deviceModel,
                      imei: imeiController.text.trim(),
                      condition: 'used',
                      quantity: 1,
                      price: price,
                      cost: cost,
                      supplier: 'العميل: ${ticket.customerName}',
                      warehouse: selectedWarehouse,
                    );

                    await DatabaseHelper.saveDevice(device);

                    widget.onStatusChanged(
                        widget.ticket, 'bought_from_customer');

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '✅ تم شراء الجهاز بمبلغ ${cost.toStringAsFixed(2)} ج.م وتحويله للمستعمل بنجاح!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: const Text('شراء وحفظ',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'repaired':
        return Colors.green;
      case 'delivered':
        return Colors.grey;
      case 'rejected':
        return Colors.red;
      case 'bought_from_customer':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String getStatusText(String status) {
    switch (status) {
      case 'pending':
        return '⏳ قيد الانتظار';
      case 'in_progress':
        return '🔧 تحت الصيانة';
      case 'repaired':
        return '✅ تم الإصلاح';
      case 'delivered':
        return '📦 تم التسليم';
      case 'rejected':
        return '❌ المرفوض';
      case 'bought_from_customer':
        return '💜 تم الشراء من العميل';
      default:
        return status;
    }
  }

  Color getHoverColor(String status) {
    switch (status) {
      case 'pending':
        return const Color(0xFF242F3D);
      case 'in_progress':
        return const Color(0xFF1D2B3A);
      case 'repaired':
        return const Color(0xFF1D3327);
      case 'delivered':
        return const Color(0xFF242A31);
      case 'rejected':
        return const Color(0xFF3D2424);
      case 'bought_from_customer':
        return const Color(0xFF2D1F35);
      default:
        return const Color(0xFF1A2A3A);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _isHovered
              ? AppTheme.getHoverColor(context, widget.ticket.status)
              : AppTheme.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          boxShadow: _isHovered
              ? [
                  BoxShadow(
                    color: getStatusColor(widget.ticket.status)
                        .withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
          border: Border.all(
            color: _isHovered
                ? getStatusColor(widget.ticket.status).withValues(alpha: 0.6)
                : AppTheme.border(context),
            width: 1.5,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(14),
            splashColor:
                getStatusColor(widget.ticket.status).withValues(alpha: 0.15),
            highlightColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: getStatusColor(widget.ticket.status)
                              .withValues(alpha: _isHovered ? 0.25 : 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          widget.ticket.status == 'pending'
                              ? Icons.pending
                              : widget.ticket.status == 'in_progress'
                                  ? Icons.build
                                  : widget.ticket.status == 'repaired'
                                      ? Icons.check_circle
                                      : Icons.delivery_dining,
                          color: getStatusColor(widget.ticket.status),
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.edit,
                                  color: _isHovered
                                      ? getStatusColor(widget.ticket.status)
                                      : const Color(0xFFD4AF37),
                                  size: 24,
                                ),
                                onPressed: widget.onEdit,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'تعديل',
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 44,
                                height: 32,
                                child: _buildMicroButton(
                                  icon: Icons.visibility_outlined,
                                  tooltip: 'معاينة الملصق',
                                  backgroundColor:
                                      Colors.blueAccent.withValues(alpha: 0.15),
                                  foregroundColor: Colors.blueAccent,
                                  onPressed: () =>
                                      widget.onPreviewLabel(widget.ticket),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 44,
                                height: 32,
                                child: _buildMicroButton(
                                  icon: Icons.qr_code_outlined,
                                  tooltip: 'طباعة الملصق',
                                  backgroundColor:
                                      Colors.blue.withValues(alpha: 0.15),
                                  foregroundColor: Colors.blue.shade300,
                                  onPressed: () =>
                                      widget.onPrintLabel(widget.ticket),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 44,
                                height: 32,
                                child: _buildMicroButton(
                                  icon: Icons.visibility_outlined,
                                  tooltip: 'معاينة الإيصال',
                                  backgroundColor:
                                      Colors.teal.withValues(alpha: 0.15),
                                  foregroundColor: Colors.tealAccent,
                                  onPressed: () =>
                                      widget.onPreviewReceipt(widget.ticket),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 44,
                                height: 32,
                                child: _buildMicroButton(
                                  icon: Icons.receipt_long_outlined,
                                  tooltip: 'طباعة الإيصال',
                                  backgroundColor:
                                      Colors.green.withValues(alpha: 0.15),
                                  foregroundColor: Colors.greenAccent.shade400,
                                  onPressed: () =>
                                      widget.onPrintReceipt(widget.ticket),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 44,
                                height: 32,
                                child: _buildMicroButton(
                                  icon: Icons.shopping_bag_outlined,
                                  tooltip: 'شراء الجهاز للمستعمل',
                                  backgroundColor:
                                      Colors.purple.withValues(alpha: 0.15),
                                  foregroundColor: Colors.purpleAccent,
                                  onPressed: () => _showBuyDeviceDialog(
                                      context, widget.ticket),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.redAccent,
                                  size: 24,
                                ),
                                onPressed: widget.onDelete,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'حذف',
                              ),
                              const Spacer(),
                              _buildStatusIconIndicator(
                                icon: Icons.pending,
                                color: Colors.orange,
                                isActive: widget.ticket.status == 'pending',
                                tooltip: 'قيد الانتظار',
                                onTap: () => widget.onStatusChanged(
                                    widget.ticket, 'pending'),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.build,
                                color: Colors.blue,
                                isActive: widget.ticket.status == 'in_progress',
                                tooltip: 'تحت الصيانة',
                                onTap: () => widget.onStatusChanged(
                                    widget.ticket, 'in_progress'),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.check_circle,
                                color: Colors.green,
                                isActive: widget.ticket.status == 'repaired',
                                tooltip: 'تم الإصلاح',
                                onTap: () => widget.onStatusChanged(
                                    widget.ticket, 'repaired'),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.delivery_dining,
                                color: Colors.grey,
                                isActive: widget.ticket.status == 'delivered',
                                tooltip: 'تم التسليم',
                                onTap: () => widget.onStatusChanged(
                                    widget.ticket, 'delivered'),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.cancel,
                                color: Colors.red,
                                isActive: widget.ticket.status == 'rejected',
                                tooltip: 'المرفوض',
                                onTap: () => widget.onStatusChanged(
                                    widget.ticket, 'rejected'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                widget.ticket.customerName,
                                style: TextStyle(
                                  color: AppTheme.text(context),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD4AF37)
                                      .withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFFD4AF37)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  '#${widget.ticket.id}',
                                  style: const TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${widget.ticket.cost.toStringAsFixed(2)} ج.م',
                                style: const TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildInfoChip(
                                  Icons.phone, widget.ticket.customerPhone),
                              _buildInfoChip(Icons.phone_android,
                                  widget.ticket.deviceModel),
                              _buildInfoChip(Icons.build_circle_outlined,
                                  widget.ticket.problem),
                              if (widget.ticket.technicianName != null &&
                                  widget.ticket.technicianName!.isNotEmpty)
                                _buildInfoChip(Icons.person_outline,
                                    widget.ticket.technicianName!),
                              _buildInfoChip(
                                Icons.access_time,
                                DateFormat('yyyy/MM/dd HH:mm')
                                    .format(widget.ticket.receivedDate),
                              ),
                            ],
                          ),
                          if (widget.ticket.notes.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'ملاحظات: ${widget.ticket.notes}',
                              style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                          if (widget.ticket.deviceCondition.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'حالة الجهاز: ${widget.ticket.deviceCondition}',
                              style: TextStyle(
                                  color: AppTheme.textMuted(context),
                                  fontSize: 14),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceTint(context),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppTheme.border(context).withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textDisabled(context)),
          const SizedBox(width: 4),
          Text(text,
              style:
                  TextStyle(color: AppTheme.textMuted(context), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildMicroButton({
    required IconData icon,
    required String tooltip,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      textStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          color: AppTheme.isDark(context)
              ? Colors.white
              : const Color(0xFF1A2A3A)),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? const Color(0xFF1E2D3D)
            : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: foregroundColor.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: foregroundColor,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIconIndicator({
    required IconData icon,
    required Color color,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      textStyle: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 11,
          color: AppTheme.isDark(context)
              ? Colors.white
              : const Color(0xFF1A2A3A)),
      decoration: BoxDecoration(
        color: AppTheme.isDark(context)
            ? const Color(0xFF1E2D3D)
            : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border(context)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color:
                  isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive
                    ? color.withValues(alpha: 0.4)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? color : AppTheme.textDisabled(context),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== TicketDialog ====================

class TicketDialog extends StatefulWidget {
  final Ticket? ticket;
  final Function(Map<String, dynamic>) onSave;
  final List<Map<String, String>> technicians;
  final List<Ticket> existingTickets;
  final List<SparePart> spareParts;

  const TicketDialog(
      {super.key,
      this.ticket,
      required this.onSave,
      required this.technicians,
      required this.existingTickets,
      required this.spareParts});

  @override
  State<TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<TicketDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _deviceController;
  late TextEditingController _problemController;
  late TextEditingController _costController;
  late TextEditingController _notesController;
  late TextEditingController _deviceConditionController;
  late TextEditingController _technicianNameController;
  late TextEditingController _technicianPhoneController;
  late TextEditingController _partsCostController;
  late TextEditingController _commissionRateController;
  late String _status;
  List<Map<String, String>> filteredTechnicians = [];
  List<Map<String, dynamic>> _selectedParts = [];

  List<String> allCustomerNames = [];
  List<String> allCustomerPhones = [];
  List<String> allDeviceModels = [];

  List<String> filteredCustomerNames = [];
  List<String> filteredCustomerPhones = [];
  List<String> filteredDeviceModels = [];

  List<Ticket> customerHistory = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.ticket?.customerName);
    _phoneController =
        TextEditingController(text: widget.ticket?.customerPhone);
    _deviceController = TextEditingController(text: widget.ticket?.deviceModel);
    _problemController = TextEditingController(text: widget.ticket?.problem);
    _costController =
        TextEditingController(text: widget.ticket?.cost.toString() ?? '0');
    _notesController = TextEditingController(text: widget.ticket?.notes);
    _deviceConditionController =
        TextEditingController(text: widget.ticket?.deviceCondition);
    _technicianNameController =
        TextEditingController(text: widget.ticket?.technicianName);
    _technicianPhoneController =
        TextEditingController(text: widget.ticket?.technicianPhone);
    _partsCostController =
        TextEditingController(text: widget.ticket?.partsCost.toString() ?? '0');
    _commissionRateController = TextEditingController(
        text: widget.ticket?.commissionRate.toString() ?? '50.0');
    _status = widget.ticket?.status ?? 'pending';
    filteredTechnicians = [];

    if (widget.ticket?.partsUsed != null &&
        widget.ticket!.partsUsed!.isNotEmpty) {
      try {
        _selectedParts = List<Map<String, dynamic>>.from(
            jsonDecode(widget.ticket!.partsUsed!));
      } catch (e) {
        debugPrint('Error decoding partsUsed: $e');
      }
    }

    final tickets = widget.existingTickets;
    allCustomerNames = tickets
        .map((t) => t.customerName.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    allCustomerPhones = tickets
        .map((t) => t.customerPhone.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    allDeviceModels = tickets
        .map((t) => t.deviceModel.trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();

    if (widget.ticket != null) {
      _updateCustomerHistory(widget.ticket!.customerPhone);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _deviceController.dispose();
    _problemController.dispose();
    _costController.dispose();
    _notesController.dispose();
    _deviceConditionController.dispose();
    _technicianNameController.dispose();
    _technicianPhoneController.dispose();
    _partsCostController.dispose();
    _commissionRateController.dispose();
    super.dispose();
  }

  void _calculateTotalPartsCost() {
    double total = 0.0;
    for (var p in _selectedParts) {
      total += (p['price'] as num) * (p['quantity'] as num);
    }
    setState(() {
      _partsCostController.text = total.toStringAsFixed(2);
    });
  }

  void _showAddPartToTicketDialog() {
    SparePart? selectedInventoryPart;
    int qty = 1;
    final qtyController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text('إضافة قطعة غيار للإيصال',
                  style: TextStyle(color: Color(0xFFD4AF37), fontSize: 20)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<SparePart>(
                    dropdownColor: AppTheme.cardBg(context),
                    style:
                        TextStyle(color: AppTheme.text(context), fontSize: 16),
                    decoration: const InputDecoration(
                      labelText: 'اختر قطعة الغيار من المستودع',
                    ),
                    items: widget.spareParts.map((p) {
                      return DropdownMenuItem<SparePart>(
                        value: p,
                        child: Text(
                            '${p.name} (المتاح: ${p.quantity} - السعر: ${p.price} ج.م)'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedInventoryPart = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: qtyController,
                    style:
                        TextStyle(color: AppTheme.text(context), fontSize: 16),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الكمية المطلوبة',
                    ),
                    onChanged: (val) {
                      qty = int.tryParse(val) ?? 1;
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('إلغاء',
                      style: TextStyle(
                          color: AppTheme.textMuted(context), fontSize: 16)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF1A2A3A),
                  ),
                  onPressed: () {
                    if (selectedInventoryPart != null) {
                      final existingIndex = _selectedParts.indexWhere(
                          (p) => p['partId'] == selectedInventoryPart!.id);
                      setState(() {
                        if (existingIndex != -1) {
                          _selectedParts[existingIndex]['quantity'] += qty;
                        } else {
                          _selectedParts.add({
                            'partId': selectedInventoryPart!.id,
                            'name': selectedInventoryPart!.name,
                            'quantity': qty,
                            'price': selectedInventoryPart!.price,
                          });
                        }
                        _calculateTotalPartsCost();
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _filterCustomerNames(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredCustomerNames = [];
      } else {
        filteredCustomerNames = allCustomerNames
            .where((name) => name.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _filterCustomerPhones(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredCustomerPhones = [];
      } else {
        filteredCustomerPhones = allCustomerPhones
            .where((phone) => phone.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _filterDeviceModels(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredDeviceModels = [];
      } else {
        filteredDeviceModels = allDeviceModels
            .where((model) => model.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _selectCustomerName(String name) {
    setState(() {
      _nameController.text = name;
      filteredCustomerNames = [];
      if (_phoneController.text.isEmpty) {
        final hasMatch = widget.existingTickets
            .any((t) => t.customerName.trim() == name.trim());
        if (hasMatch) {
          final match = widget.existingTickets
              .firstWhere((t) => t.customerName.trim() == name.trim());
          _phoneController.text = match.customerPhone;
          _updateCustomerHistory(match.customerPhone);
        }
      }
    });
  }

  void _selectCustomerPhone(String phone) {
    setState(() {
      _phoneController.text = phone;
      filteredCustomerPhones = [];
      if (_nameController.text.isEmpty) {
        final hasMatch = widget.existingTickets
            .any((t) => t.customerPhone.trim() == phone.trim());
        if (hasMatch) {
          final match = widget.existingTickets
              .firstWhere((t) => t.customerPhone.trim() == phone.trim());
          _nameController.text = match.customerName;
        }
      }
      _updateCustomerHistory(phone);
    });
  }

  void _selectDeviceModel(String model) {
    setState(() {
      _deviceController.text = model;
      filteredDeviceModels = [];
    });
  }

  void _updateCustomerHistory(String phone) {
    final cleanPhone = phone.trim();
    setState(() {
      if (cleanPhone.isEmpty) {
        customerHistory = [];
      } else {
        customerHistory = widget.existingTickets
            .where((t) =>
                t.customerPhone.trim() == cleanPhone &&
                (widget.ticket == null || t.id != widget.ticket!.id))
            .toList();
        customerHistory
            .sort((a, b) => b.receivedDate.compareTo(a.receivedDate));
      }
    });
  }

  Widget _buildHistoryStatusBadge(String status) {
    Color badgeColor;
    String text;
    switch (status) {
      case 'pending':
        badgeColor = Colors.orange;
        text = '⏳ قيد الانتظار';
        break;
      case 'in_progress':
        badgeColor = Colors.blue;
        text = '🔧 تحت الصيانة';
        break;
      case 'repaired':
        badgeColor = Colors.green;
        text = '✅ تم الإصلاح';
        break;
      case 'delivered':
        badgeColor = Colors.purple;
        text = '📦 تم التسليم';
        break;
      case 'rejected':
        badgeColor = Colors.red;
        text = '❌ المرفوض';
        break;
      default:
        badgeColor = Colors.grey;
        text = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: badgeColor, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _filterTechnicians(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredTechnicians = [];
      } else {
        filteredTechnicians = widget.technicians
            .where((tech) =>
                tech['name']!.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  void _selectTechnician(Map<String, String> tech) {
    setState(() {
      _technicianNameController.text = tech['name']!;
      _technicianPhoneController.text = tech['phone']!;
      filteredTechnicians = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    widget.ticket == null
                        ? '➕ إضافة إيصال جديد'
                        : '✏️ تعديل إيصال',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD4AF37))),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.blue[900]!.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('معلومات العميل',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37))),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            style: TextStyle(
                                color: AppTheme.text(context), fontSize: 18),
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'اسم العميل *',
                            ),
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'مطلوب' : null,
                            onChanged: _filterCustomerNames,
                            onFieldSubmitted: (value) {
                              if (filteredCustomerNames.isNotEmpty) {
                                _selectCustomerName(
                                    filteredCustomerNames.first);
                              }
                            },
                          ),
                          if (filteredCustomerNames.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              constraints: const BoxConstraints(maxHeight: 150),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceTint(context),
                                border: Border.all(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredCustomerNames.length,
                                itemBuilder: (context, index) {
                                  final name = filteredCustomerNames[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(name,
                                        style: TextStyle(
                                            color: AppTheme.text(context),
                                            fontSize: 18)),
                                    onTap: () => _selectCustomerName(name),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            autofocus: true,
                            style: TextStyle(
                                color: AppTheme.text(context), fontSize: 18),
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'رقم الهاتف *',
                            ),
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'مطلوب' : null,
                            onChanged: (val) {
                              _filterCustomerPhones(val);
                              _updateCustomerHistory(val);
                            },
                            onFieldSubmitted: (value) {
                              if (filteredCustomerPhones.isNotEmpty) {
                                _selectCustomerPhone(
                                    filteredCustomerPhones.first);
                              }
                            },
                          ),
                          if (filteredCustomerPhones.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              constraints: const BoxConstraints(maxHeight: 150),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceTint(context),
                                border: Border.all(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredCustomerPhones.length,
                                itemBuilder: (context, index) {
                                  final phone = filteredCustomerPhones[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(phone,
                                        style: TextStyle(
                                            color: AppTheme.text(context),
                                            fontSize: 18)),
                                    onTap: () => _selectCustomerPhone(phone),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            style: TextStyle(
                                color: AppTheme.text(context), fontSize: 18),
                            controller: _deviceController,
                            decoration: const InputDecoration(
                              labelText: 'نوع الجهاز *',
                            ),
                            validator: (v) =>
                                v?.isEmpty ?? true ? 'مطلوب' : null,
                            onChanged: _filterDeviceModels,
                            onFieldSubmitted: (value) {
                              if (filteredDeviceModels.isNotEmpty) {
                                _selectDeviceModel(filteredDeviceModels.first);
                              }
                            },
                          ),
                          if (filteredDeviceModels.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              constraints: const BoxConstraints(maxHeight: 150),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceTint(context),
                                border: Border.all(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredDeviceModels.length,
                                itemBuilder: (context, index) {
                                  final model = filteredDeviceModels[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(model,
                                        style: TextStyle(
                                            color: AppTheme.text(context),
                                            fontSize: 18)),
                                    onTap: () => _selectDeviceModel(model),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                            color: AppTheme.text(context), fontSize: 18),
                        controller: _problemController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'العطل *',
                        ),
                        validator: (v) => v?.isEmpty ?? true ? 'مطلوب' : null,
                      ),
                    ],
                  ),
                ),
                if (customerHistory.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber[900]!.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                          width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.history,
                                color: Color(0xFFD4AF37), size: 22),
                            const SizedBox(width: 8),
                            Text(
                              '📋 سجل هذا العميل مسبقاً (${customerHistory.length} أجهزة):',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD4AF37)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: customerHistory.length,
                            separatorBuilder: (context, index) => const Divider(
                              color: Colors.white24,
                              thickness: 1,
                              height: 16,
                            ),
                            itemBuilder: (context, index) {
                              final hist = customerHistory[index];
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '📱 الجهاز: ${hist.deviceModel}',
                                        style: TextStyle(
                                            color: AppTheme.text(context),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15),
                                      ),
                                      _buildHistoryStatusBadge(hist.status),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '🔧 العطل: ${hist.problem}',
                                    style: TextStyle(
                                        color: AppTheme.textMuted(context),
                                        fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '📅 تاريخ الاستلام: ${DateFormat('yyyy/MM/dd').format(hist.receivedDate)}',
                                        style: TextStyle(
                                            color:
                                                AppTheme.textDisabled(context),
                                            fontSize: 12),
                                      ),
                                      Text(
                                        '💰 التكلفة المبدئية: ${hist.cost.toStringAsFixed(2)} ج.م',
                                        style: const TextStyle(
                                            color: Color(0xFFD4AF37),
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.green[900]!.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('معلومات الفني',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37))),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            style: TextStyle(
                                color: AppTheme.text(context), fontSize: 18),
                            controller: _technicianNameController,
                            decoration: const InputDecoration(
                              labelText: 'اسم الفني',
                              hintText: 'اكتب أول حرف من اسم الفني',
                            ),
                            onChanged: _filterTechnicians,
                            onFieldSubmitted: (value) {
                              if (filteredTechnicians.isNotEmpty) {
                                _selectTechnician(filteredTechnicians.first);
                              }
                            },
                          ),
                          if (filteredTechnicians.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceTint(context),
                                border: Border.all(
                                    color: const Color(0xFFD4AF37)
                                        .withValues(alpha: 0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredTechnicians.length,
                                itemBuilder: (context, index) {
                                  final tech = filteredTechnicians[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(tech['name']!,
                                        style: TextStyle(
                                            color: AppTheme.text(context),
                                            fontSize: 18)),
                                    subtitle: Text(tech['phone']!,
                                        style: TextStyle(
                                            color: AppTheme.textMuted(context),
                                            fontSize: 14)),
                                    onTap: () => _selectTechnician(tech),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                            color: AppTheme.text(context), fontSize: 18),
                        controller: _technicianPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الفني',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.purple[900]!.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('قطع الغيار المستخدمة',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFD4AF37))),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: const Color(0xFF1A2A3A),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('إضافة قطعة',
                                style: TextStyle(fontSize: 13)),
                            onPressed: () {
                              _showAddPartToTicketDialog();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedParts.isEmpty)
                        Text(
                          'لا توجد قطع غيار مضافة حالياً.',
                          style: TextStyle(
                              color: AppTheme.textMuted(context), fontSize: 14),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _selectedParts.length,
                          itemBuilder: (context, index) {
                            final item = _selectedParts[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(item['name'],
                                  style: TextStyle(
                                      color: AppTheme.text(context),
                                      fontSize: 16)),
                              subtitle: Text(
                                'الكمية: ${item['quantity']} | السعر: ${item['price']} ج.م',
                                style: TextStyle(
                                    color: AppTheme.textMuted(context),
                                    fontSize: 14),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _selectedParts.removeAt(index);
                                    _calculateTotalPartsCost();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.orange[900]!.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('معلومات إضافية',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37))),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _status,
                              dropdownColor: AppTheme.cardBg(context),
                              style: TextStyle(
                                  color: AppTheme.text(context), fontSize: 18),
                              decoration: const InputDecoration(
                                labelText: 'الحالة',
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'pending',
                                    child: Text('⏳ قيد الانتظار')),
                                DropdownMenuItem(
                                    value: 'in_progress',
                                    child: Text('🔧 تحت الصيانة')),
                                DropdownMenuItem(
                                    value: 'repaired',
                                    child: Text('✅ تم الإصلاح')),
                                DropdownMenuItem(
                                    value: 'delivered',
                                    child: Text('📦 تم التسليم')),
                                DropdownMenuItem(
                                    value: 'rejected',
                                    child: Text('❌ المرفوض')),
                                DropdownMenuItem(
                                    value: 'bought_from_customer',
                                    child: Text('💜 تم الشراء من العميل')),
                              ],
                              onChanged: (v) => setState(() => _status = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              style: TextStyle(
                                  color: AppTheme.text(context), fontSize: 18),
                              controller: _costController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'التكلفة المبدئية/النهائية (ج.م)',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              style: TextStyle(
                                  color: AppTheme.text(context), fontSize: 18),
                              controller: _partsCostController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'تكلفة قطع الغيار (ج.م)',
                                helperText: 'تُحسب تلقائياً من القطع المضافة',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              style: TextStyle(
                                  color: AppTheme.text(context), fontSize: 18),
                              controller: _commissionRateController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'نسبة عمولة الفني (%)',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                            color: AppTheme.text(context), fontSize: 18),
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                            color: AppTheme.text(context), fontSize: 18),
                        controller: _deviceConditionController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'حالة الجهاز',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTint(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFFD4AF37)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.confirmation_number,
                                color: Color(0xFFD4AF37), size: 24),
                            const SizedBox(width: 12),
                            Text('رقم الشكوى:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textMuted(context),
                                    fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(DatabaseHelper.complaintNumber,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD4AF37))),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color:
                                      Colors.red[900]!.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12)),
                              child: const Text('ثابت',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.red)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          if (_formKey.currentState!.validate()) {
                            widget.onSave({
                              'customerName': _nameController.text,
                              'customerPhone': _phoneController.text,
                              'deviceModel': _deviceController.text,
                              'problem': _problemController.text,
                              'status': _status,
                              'cost':
                                  double.tryParse(_costController.text) ?? 0,
                              'notes': _notesController.text,
                              'deviceCondition':
                                  _deviceConditionController.text,
                              'technicianName': _technicianNameController.text,
                              'technicianPhone':
                                  _technicianPhoneController.text,
                              'partsCost':
                                  double.tryParse(_partsCostController.text) ??
                                      0.0,
                              'partsUsed': _selectedParts.isNotEmpty
                                  ? jsonEncode(_selectedParts)
                                  : null,
                              'commissionRate': double.tryParse(
                                      _commissionRateController.text) ??
                                  50.0,
                            });
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: const Color(0xFF1A2A3A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('حفظ',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 20)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child:
                            const Text('إلغاء', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== AddPartDialog ====================

class AddPartDialog extends StatefulWidget {
  final SparePart? part;
  final Function(String, int, double, String) onSave;

  const AddPartDialog({super.key, this.part, required this.onSave});

  @override
  State<AddPartDialog> createState() => _AddPartDialogState();
}

class _AddPartDialogState extends State<AddPartDialog> {
  late TextEditingController _nameController;
  late TextEditingController _qtyController;
  late TextEditingController _priceController;
  late TextEditingController _supplierController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.part?.name);
    _qtyController =
        TextEditingController(text: widget.part?.quantity.toString() ?? '0');
    _priceController =
        TextEditingController(text: widget.part?.price.toString() ?? '0');
    _supplierController = TextEditingController(text: widget.part?.supplier);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(widget.part == null ? 'إضافة قطعة غيار' : 'تعديل قطعة غيار',
          style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 22)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'اسم القطعة',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _qtyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'الكمية',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'السعر',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _supplierController,
            decoration: const InputDecoration(
              labelText: 'المورد',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء',
              style:
                  TextStyle(color: AppTheme.textMuted(context), fontSize: 18)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD4AF37),
            foregroundColor: const Color(0xFF1A2A3A),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          onPressed: () {
            widget.onSave(
              _nameController.text,
              int.tryParse(_qtyController.text) ?? 0,
              double.tryParse(_priceController.text) ?? 0,
              _supplierController.text,
            );
            Navigator.pop(context);
          },
          child: const Text('حفظ', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}

// ==================== Printer Settings Dialog ====================

class _PrinterSettingsDialog extends StatefulWidget {
  @override
  State<_PrinterSettingsDialog> createState() => _PrinterSettingsDialogState();
}

class _PrinterSettingsDialogState extends State<_PrinterSettingsDialog> {
  List<Printer> _printers = [];
  bool _loading = true;

  String? _selectedLabel;
  String? _selectedReceipt;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final config = await PrinterSettingsService.load();
    final printers = await PrinterSettingsService.listAll();
    if (mounted) {
      setState(() {
        _printers = printers;
        _selectedLabel = config.labelPrinterName;
        _selectedReceipt = config.receiptPrinterName;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await PrinterSettingsService.save(PrinterConfig(
      labelPrinterName: _selectedLabel,
      receiptPrinterName: _selectedReceipt,
    ));
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم حفظ إعدادات الطابعة'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  bool _isMissing(String? name) {
    if (name == null || name.isEmpty) return false;
    return !_printers.any((p) => p.name == name);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.print_outlined,
                          color: Color(0xFFD4AF37), size: 26),
                      SizedBox(width: 10),
                      Text(
                        'إعدادات الطابعة',
                        style: TextStyle(
                          color: Color(0xFFD4AF37),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'تحديث قائمة الطابعات',
                    icon: Icon(Icons.refresh,
                        color: AppTheme.textMuted(context), size: 22),
                    onPressed: _loading ? null : _loadData,
                  ),
                ],
              ),
              const Divider(
                  color: Color(0xFFD4AF37), thickness: 0.5, height: 24),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                            color: Color(0xFFD4AF37)),
                        const SizedBox(height: 14),
                        Text('جارٍ البحث عن الطابعات...',
                            style: TextStyle(
                                color: AppTheme.textMuted(context),
                                fontSize: 15)),
                      ],
                    ),
                  ),
                )
              else ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceTint(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border(context)),
                  ),
                  child: Text(
                    'الطابعات المكتشفة: ${_printers.length}',
                    style: TextStyle(
                        color: AppTheme.textDisabled(context), fontSize: 13),
                  ),
                ),
                const SizedBox(height: 20),
                _buildPrinterDropdown(
                  label: '🏷️ طابعة الملصقات',
                  hint: 'اختر طابعة الملصقات (XP-370B)',
                  selectedValue: _selectedLabel,
                  onChanged: (v) => setState(() => _selectedLabel = v),
                ),
                if (_isMissing(_selectedLabel)) ...[
                  const SizedBox(height: 6),
                  _warningChip(_selectedLabel!),
                ],
                const SizedBox(height: 20),
                _buildPrinterDropdown(
                  label: '🧾 طابعة الفواتير',
                  hint: 'اختر طابعة الفواتير (XP-80C)',
                  selectedValue: _selectedReceipt,
                  onChanged: (v) => setState(() => _selectedReceipt = v),
                ),
                if (_isMissing(_selectedReceipt)) ...[
                  const SizedBox(height: 6),
                  _warningChip(_selectedReceipt!),
                ],
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('إلغاء',
                          style: TextStyle(
                              color: AppTheme.textDisabled(context),
                              fontSize: 16)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text('حفظ الإعدادات',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: const Color(0xFF1A2A3A),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrinterDropdown({
    required String label,
    required String hint,
    required String? selectedValue,
    required ValueChanged<String?> onChanged,
  }) {
    final names = _printers
        .map((p) => p.name)
        .whereType<String>()
        .where((n) => n.isNotEmpty)
        .toList();
    if (selectedValue != null &&
        selectedValue.isNotEmpty &&
        !names.contains(selectedValue)) {
      names.insert(0, selectedValue);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.textMuted(context),
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceTint(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFFD4AF37).withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedValue,
              dropdownColor: AppTheme.cardBg(context),
              hint: Text(hint,
                  style: TextStyle(
                      color: AppTheme.textDisabled(context), fontSize: 14)),
              style: TextStyle(color: AppTheme.text(context), fontSize: 15),
              iconEnabledColor: const Color(0xFFD4AF37),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('— لا شيء —',
                      style: TextStyle(
                          color: AppTheme.textDisabled(context), fontSize: 14)),
                ),
                ...names.map((name) {
                  final printer =
                      _printers.where((p) => p.name == name).firstOrNull;
                  final online = printer?.isAvailable ?? false;
                  return DropdownMenuItem<String>(
                    value: name,
                    child: Row(
                      children: [
                        Icon(
                          online ? Icons.circle : Icons.circle_outlined,
                          size: 10,
                          color: online ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        if (!online)
                          const Text(' (offline)',
                              style:
                                  TextStyle(color: Colors.red, fontSize: 11)),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _warningChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '⚠️ الطابعة "$name" غير موجودة في النظام — يرجى إعادة الاختيار',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
