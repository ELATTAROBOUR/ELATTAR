import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'database_helper.dart';
import 'models.dart';
import 'hwid_service.dart';
import 'views/repairs_view.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);
AppUser? currentLoggedInUser;

String hashPassword(String password) {
  final bytes = utf8.encode(password.trim());
  final digest = sha256.convert(bytes);
  return digest.toString();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite database
  await DatabaseHelper.init();

  // Perform startup sync from GitHub
  await DatabaseHelper.performStartupSync();

  // Load theme preference
  ThemeMode initialTheme = ThemeMode.dark;
  try {
    final isDark = await DatabaseHelper.getIsDarkSetting();
    if (isDark != null) {
      initialTheme = isDark ? ThemeMode.dark : ThemeMode.light;
    }
  } catch (e) {
    debugPrint('Error loading initial theme: $e');
  }
  themeNotifier.value = initialTheme;

  runApp(const MobileRepairApp());
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
      builder: (_, ThemeMode currentMode, child) {
        return MaterialApp(
          title: 'العطار استور - الصيانة',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFFD4AF37),
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
                borderRadius: BorderRadius.circular(12),
              ),
              color: Colors.white,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1A2A3A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Cairo',
                ),
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
                borderSide: const BorderSide(
                  color: Color(0xFFD4AF37),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              labelStyle: const TextStyle(
                color: Color(0xFF4A5D6E),
                fontFamily: 'Cairo',
              ),
              hintStyle: const TextStyle(
                color: Colors.black38,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFFD4AF37),
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
                borderRadius: BorderRadius.circular(12),
              ),
              color: const Color(0xFF1A2A3A),
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF1A2A3A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: const Color(0xFF1A2A3A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFFD4AF37),
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              labelStyle: const TextStyle(
                color: Colors.white70,
                fontFamily: 'Cairo',
              ),
              hintStyle: const TextStyle(
                color: Colors.white38,
                fontFamily: 'Cairo',
              ),
            ),
          ),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
          locale: const Locale('ar', 'EG'),
          home: const LicenseGatePage(),
        );
      },
    );
  }
}

enum LicensePageState { checking, notActivated, authenticated }

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

  @override
  void initState() {
    super.initState();
    _checkLicense();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _checkLicense() async {
    setState(() {
      _pageState = LicensePageState.checking;
    });

    bool isLicenseValid = false;

    // Check saved license key in settings table
    final savedKey = await DatabaseHelper.getActivationKey();
    if (savedKey != null && savedKey.isNotEmpty) {
      final isValid = await HwidService.verifyLicense(savedKey);
      if (isValid) {
        isLicenseValid = true;
      }
    }

    if (isLicenseValid) {
      if (mounted) {
        // Check user session
        final prefs = await SharedPreferences.getInstance();
        final email = prefs.getString('session_user_email');
        AppUser? user;
        if (email != null) {
          user = await DatabaseHelper.getUserByEmail(email);
        }

        if (!mounted) return;

        if (user != null) {
          currentLoggedInUser = user;
          setState(() {
            _pageState = LicensePageState.authenticated;
          });
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        } else {
          // Go to Login
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
      }
    } else {
      final hwid = await HwidService.getHWID();
      if (mounted) {
        setState(() {
          _hwid = hwid;
          _pageState = LicensePageState.notActivated;
        });
      }
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "✅ تم تفعيل البرنامج بنجاح!",
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // Go to Login
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _activating = false;
          _errorMessage = "❌ مفتاح التفعيل غير صالح لهذا الجهاز";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFFD4AF37);
    final bgColor = isDark ? const Color(0xFF121B26) : const Color(0xFFF0F4F8);
    final cardBg = isDark ? const Color(0xFF1A2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_pageState == LicensePageState.checking) ...[
                  const CircularProgressIndicator(color: Color(0xFFD4AF37)),
                  const SizedBox(height: 20),
                  Text(
                    'جاري التحقق من الترخيص...',
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Cairo',
                      color: textColor,
                    ),
                  ),
                ],
                if (_pageState == LicensePageState.notActivated) ...[
                  Icon(Icons.security_rounded, size: 80, color: primaryColor),
                  const SizedBox(height: 20),
                  Text(
                    'العطار استور',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Cairo',
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'نظام إدارة الصيانة',
                    style: TextStyle(
                      fontSize: 16,
                      fontFamily: 'Cairo',
                      color: textMuted,
                    ),
                  ),
                  const SizedBox(height: 30),
                  Card(
                    color: cardBg,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            'تفعيل البرنامج',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF0D1829)
                                  : const Color(0xFFF8F4E8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'رمز الجهاز:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'Cairo',
                                        color: textMuted,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(
                                          ClipboardData(text: _hwid),
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '✅ تم نسخ رمز الجهاز',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 14,
                                              ),
                                            ),
                                            duration: Duration(seconds: 2),
                                            backgroundColor: Colors.green,
                                          ),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(4),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primaryColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.copy_rounded,
                                              size: 14,
                                              color: primaryColor,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              'نسخ',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontFamily: 'Cairo',
                                                color: primaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  _hwid,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontFamily: 'monospace',
                                    color: primaryColor,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                  textDirection: TextDirection.ltr,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _keyController,
                            style: TextStyle(
                              color: textColor,
                              fontFamily: 'Cairo',
                              fontSize: 14,
                            ),
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              labelText: 'مفتاح التفعيل',
                              hintText: 'أدخل مفتاح التفعيل هنا',
                              labelStyle: TextStyle(
                                color: textMuted,
                                fontFamily: 'Cairo',
                              ),
                              hintStyle: TextStyle(
                                color: textMuted.withValues(alpha: 0.5),
                                fontFamily: 'Cairo',
                              ),
                              filled: true,
                              fillColor: isDark
                                  ? const Color(0xFF15202F)
                                  : const Color(0xFFF0F4F8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(
                                  color: primaryColor,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          if (_errorMessage.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              _errorMessage,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontFamily: 'Cairo',
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: const Color(0xFF1A2A3A),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _activating ? null : _activate,
                              child: _activating
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Color(0xFF1A2A3A),
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'تفعيل',
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
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
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = "";
  bool _loggingIn = false;
  bool _passwordVisible = false;

  bool _syncing = false;
  String _syncStatus = "اضغط للمزامنة وسحب الحسابات الجديدة";

  @override
  void initState() {
    super.initState();
    _syncData();
  }

  Future<void> _syncData() async {
    if (!mounted) return;
    setState(() {
      _syncing = true;
      _syncStatus = "جاري مزامنة البيانات من السحابة...";
    });
    try {
      await DatabaseHelper.syncDatabase();
      if (mounted) {
        setState(() {
          _syncStatus = "✅ تمت المزامنة بنجاح!";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = "❌ فشلت المزامنة: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  Future<void> _login() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "⚠️ يرجى ملء كافة الحقول";
      });
      return;
    }

    setState(() {
      _loggingIn = true;
      _errorMessage = "";
    });

    try {
      final enteredHash = hashPassword(password);
      final user = await DatabaseHelper.getUserByEmail(email);

      if (user != null && user.passwordHash == enteredHash) {
        currentLoggedInUser = user;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('session_user_email', user.email);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "✅ تم تسجيل الدخول بنجاح",
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
      } else {
        // Fallback: Check technicians table directly
        try {
          final db = await DatabaseHelper.db;
          final List<Map<String, dynamic>> techMaps = await db.query(
            'technicians',
            where: 'LOWER(email) = ?',
            whereArgs: [email.trim().toLowerCase()],
          );
          if (techMaps.isNotEmpty) {
            final techHash = techMaps.first['mobilePasswordHash'] as String?;
            if (techHash != null && techHash == enteredHash) {
              // Login successful via technicians table
              currentLoggedInUser = AppUser(
                id: techMaps.first['id'] as int?,
                email: email,
                passwordHash: enteredHash,
                role: 'technician',
                name: techMaps.first['name'] as String?,
              );
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('session_user_email', email);

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "✅ تم تسجيل الدخول بنجاح",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const MainScreen()),
                );
              }
              return;
            }
          }
        } catch (e) {
          debugPrint('Login fallback error: $e');
        }

        setState(() {
          _errorMessage = "❌ البريد الإلكتروني أو كلمة المرور غير صحيحة";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "❌ خطأ أثناء تسجيل الدخول: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loggingIn = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = const Color(0xFFD4AF37);
    final bgColor = isDark ? const Color(0xFF121B26) : const Color(0xFFF0F4F8);
    final cardBg = isDark ? const Color(0xFF1A2A3A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1A2A3A);
    final textMuted = isDark ? Colors.white70 : const Color(0xFF4A5D6E);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_person_rounded, size: 80, color: primaryColor),
                const SizedBox(height: 16),
                Text(
                  'تسجيل الدخول للنظام',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'يرجى إدخال بيانات الحساب للمتابعة',
                  style: TextStyle(
                    fontSize: 14,
                    fontFamily: 'Cairo',
                    color: textMuted,
                  ),
                ),
                const SizedBox(height: 30),
                Card(
                  color: cardBg,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'Cairo',
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: 'البريد الإلكتروني',
                            hintText: 'example@domain.com',
                            prefixIcon: Icon(
                              Icons.email_outlined,
                              color: primaryColor,
                            ),
                            labelStyle: TextStyle(
                              color: textMuted,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_passwordVisible,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'Cairo',
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: Icon(
                              Icons.lock_outline_rounded,
                              color: primaryColor,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _passwordVisible
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: textMuted,
                              ),
                              onPressed: () {
                                setState(() {
                                  _passwordVisible = !_passwordVisible;
                                });
                              },
                            ),
                            labelStyle: TextStyle(
                              color: textMuted,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontFamily: 'Cairo',
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: const Color(0xFF1A2A3A),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _loggingIn ? null : _login,
                            child: _loggingIn
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF1A2A3A),
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'دخول',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Divider(),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _syncing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFFD4AF37),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(
                                      Icons.cloud_download_rounded,
                                      color: Color(0xFFD4AF37),
                                    ),
                                    onPressed: _syncData,
                                    tooltip: 'مزامنة الآن',
                                  ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _syncStatus,
                                style: TextStyle(
                                  color: textMuted,
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  Timer? _syncTimer;
  WebSocket? _syncWebSocket;
  bool _syncing = false;

  // Attendance State Variables
  Attendance? _todayAttendance;
  bool _isLoadingAttendance = true;
  bool _isSubmittingAttendance = false;
  bool _forceShowAttendancePage = false;

  @override
  void initState() {
    super.initState();
    _initSync();
    _loadTodayAttendance();
  }

  Future<void> _loadTodayAttendance() async {
    if (currentLoggedInUser == null) {
      setState(() => _isLoadingAttendance = false);
      return;
    }
    setState(() => _isLoadingAttendance = true);
    try {
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final userName = currentLoggedInUser!.name ?? currentLoggedInUser!.email;
      final att = await DatabaseHelper.getAttendanceByUserAndDate(
        userName,
        todayStr,
      );
      setState(() {
        _todayAttendance = att;
        _isLoadingAttendance = false;
      });
    } catch (e) {
      debugPrint('Error loading today attendance: $e');
      setState(() => _isLoadingAttendance = false);
    }
  }

  Future<void> _initSync() async {
    // Periodic GitHub sync every 10 minutes (silent background backup)
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _autoSync();
    });

    // Start the WebSocket instant sync listener
    _startInstantSyncListener();

    // Run an initial sync
    _autoSync();
  }

  void _startInstantSyncListener() async {
    final url = 'wss://ntfy.sh/elattar_sync_obourdist_9f70cb7a/ws';
    debugPrint('Mobile: Connecting to instant sync WebSocket...');
    try {
      _syncWebSocket = await WebSocket.connect(
        url,
      ).timeout(const Duration(seconds: 10));
      debugPrint('Mobile: Connected to instant sync WebSocket successfully.');

      _syncWebSocket!.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['event'] == 'message') {
              final sender = data['message'] as String?;
              if (sender == 'desktop') {
                debugPrint(
                  'Mobile: Instant sync ping received from desktop. Triggering database sync...',
                );
                _autoSync();
              }
            }
          } catch (e) {
            debugPrint('Mobile: Error parsing sync WS message: $e');
          }
        },
        onError: (error) {
          debugPrint(
            'Mobile: Sync WebSocket error: $error. Reconnecting in 5 seconds...',
          );
          _reconnectInstantSyncListener();
        },
        onDone: () {
          debugPrint(
            'Mobile: Sync WebSocket closed. Reconnecting in 5 seconds...',
          );
          _reconnectInstantSyncListener();
        },
      );
    } catch (e) {
      debugPrint(
        'Mobile: Failed to connect to sync WebSocket: $e. Retrying in 5 seconds...',
      );
      _reconnectInstantSyncListener();
    }
  }

  void _reconnectInstantSyncListener() {
    _syncWebSocket?.close();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _startInstantSyncListener();
      }
    });
  }

  /// Silent auto-sync for timer (no SnackBar to avoid annoying the user)
  Future<void> _autoSync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await DatabaseHelper.syncDatabase();
    } catch (e) {
      debugPrint('Auto Sync failed: $e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _syncWebSocket?.close();
    super.dispose();
  }

  Future<void> _handleCheckIn() async {
    if (currentLoggedInUser == null || _isSubmittingAttendance) return;
    setState(() => _isSubmittingAttendance = true);

    final userName = currentLoggedInUser!.name ?? currentLoggedInUser!.email;
    final userRole = currentLoggedInUser!.role;
    final userId = currentLoggedInUser!.id;

    final result = await DatabaseHelper.checkIn(
      userName,
      userRole,
      userId: userId,
    );

    setState(() {
      _isSubmittingAttendance = false;
      if (result != null) {
        _todayAttendance = result;
      }
    });

    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ تم تسجيل الحضور بنجاح وجاري المزامنة...',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _handleCheckOut() async {
    if (currentLoggedInUser == null || _isSubmittingAttendance) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.cardBg(context),
          title: const Text(
            'تسجيل الانصراف',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'هل أنت متأكد من تسجيل انصرافك اليوم؟',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text(
                'تسجيل انصراف',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmittingAttendance = true);

    final userName = currentLoggedInUser!.name ?? currentLoggedInUser!.email;
    final success = await DatabaseHelper.checkOut(userName);

    if (success) {
      await _loadTodayAttendance();
    }

    setState(() => _isSubmittingAttendance = false);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '✅ تم تسجيل الانصراف بنجاح وجاري المزامنة...',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildAttendanceView() {
    final userName =
        currentLoggedInUser?.name ?? currentLoggedInUser?.email ?? "";
    final isCheckedIn = _todayAttendance != null;
    final isCheckedOut = isCheckedIn && _todayAttendance!.checkOut != null;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            // Log out / back button
            Positioned(
              top: 16,
              right: 16,
              child: Row(
                children: [
                  if (isCheckedIn)
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() {
                          _forceShowAttendancePage = false;
                        });
                      },
                      tooltip: 'العودة للصيانات',
                    ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Colors.white),
                    onPressed: _logout,
                    tooltip: 'تسجيل الخروج',
                  ),
                ],
              ),
            ),

            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 340),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header Icon
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    (isCheckedOut
                                            ? Colors.orange
                                            : (isCheckedIn
                                                  ? Colors.green
                                                  : const Color(0xFFD4AF37)))
                                        .withValues(alpha: 0.3),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (isCheckedOut
                                              ? Colors.orange
                                              : (isCheckedIn
                                                    ? Colors.green
                                                    : const Color(0xFFD4AF37)))
                                          .withValues(alpha: 0.1),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: Icon(
                              isCheckedOut
                                  ? Icons.assignment_turned_in_rounded
                                  : (isCheckedIn
                                        ? Icons.check_circle_rounded
                                        : Icons.wb_sunny_rounded),
                              color: isCheckedOut
                                  ? Colors.orange
                                  : (isCheckedIn
                                        ? Colors.green
                                        : const Color(0xFFD4AF37)),
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Greeting text
                          Text(
                            isCheckedOut
                                ? "يوم عمل موفق!"
                                : (isCheckedIn
                                      ? "مرحباً بك مجدداً!"
                                      : "مرحباً بك في يوم جديد"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),

                          // Subtitle text
                          Text(
                            isCheckedOut
                                ? "تم تسجيل انصرافك لليوم بنجاح. شكراً لجهودك!"
                                : (isCheckedIn
                                      ? "الفني: $userName\nتم تسجيل حضورك اليوم بنجاح."
                                      : "الفني: $userName\nيرجى تسجيل الحضور للبدء بالعمل والاطلاع على الصيانات اليومية."),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 13,
                              fontFamily: 'Cairo',
                              height: 1.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Submitting loading indicator
                          if (_isSubmittingAttendance)
                            const CircularProgressIndicator(
                              color: Color(0xFFD4AF37),
                            )
                          else ...[
                            // Primary Button
                            if (!isCheckedIn)
                              InkWell(
                                onTap: _handleCheckIn,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        const Color(
                                          0xFFD4AF37,
                                        ).withValues(alpha: 0.85),
                                        const Color(
                                          0xFFAA7C11,
                                        ).withValues(alpha: 0.85),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.3,
                                      ),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFFD4AF37,
                                        ).withValues(alpha: 0.3),
                                        blurRadius: 15,
                                        offset: const Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      "تسجيل الحضور",
                                      style: TextStyle(
                                        color: Color(0xFF1A2A3A),
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              // Checked in state
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "وقت الحضور:",
                                          style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 13,
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                        Text(
                                          _todayAttendance!.formattedCheckIn,
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isCheckedOut) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            "وقت الانصراف:",
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          Text(
                                            _todayAttendance!.formattedCheckOut,
                                            style: const TextStyle(
                                              color: Colors.orange,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Action Buttons for checked in user
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(
                                    Icons.dashboard_customize_outlined,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    "لوحة الصيانات والإصلاحات",
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD4AF37),
                                    foregroundColor: const Color(0xFF1A2A3A),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _forceShowAttendancePage = false;
                                    });
                                  },
                                ),
                              ),

                              if (isCheckedOut) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.login_rounded,
                                      size: 18,
                                      color: Colors.green,
                                    ),
                                    label: const Text(
                                      "تسجيل حضور مرة أخرى",
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 14,
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.green,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: _handleCheckIn,
                                  ),
                                ),
                              ],

                              if (!isCheckedOut) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    icon: const Icon(
                                      Icons.exit_to_app_rounded,
                                      size: 18,
                                      color: Colors.orange,
                                    ),
                                    label: const Text(
                                      "تسجيل انصراف الآن",
                                      style: TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 14,
                                        color: Colors.orange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(
                                        color: Colors.orange,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: _handleCheckOut,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerGitHubSync() async {
    if (_syncing) return;
    setState(() {
      _syncing = true;
    });
    try {
      // Sync via GitHub (push local changes & pull remote changes)
      await DatabaseHelper.syncDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ تمت المزامنة بنجاح',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('GitHub Sync failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '❌ فشلت المزامنة: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppTheme.cardBg(context),
          title: const Text(
            'تسجيل الخروج',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'هل أنت متأكد من تسجيل الخروج؟',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              child: const Text(
                'تسجيل خروج',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_user_email');
    currentLoggedInUser = null;
    setState(() {});

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  void _toggleTheme() async {
    final newMode = themeNotifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeNotifier.value = newMode;
    await DatabaseHelper.saveIsDarkSetting(newMode == ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final primaryColor = const Color(0xFFD4AF37);

    // 1. If technician is logging in, enforce the attendance check page
    if (currentLoggedInUser?.role == 'technician') {
      if (_isLoadingAttendance) {
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0F2027),
                  Color(0xFF203A43),
                  Color(0xFF2C5364),
                ],
              ),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
            ),
          ),
        );
      }

      if (_todayAttendance == null || _forceShowAttendancePage) {
        return Scaffold(body: _buildAttendanceView());
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.scaffoldBg(context),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [const Text("العطار استور - الصيانة")],
              ),
              if (currentLoggedInUser != null)
                Text(
                  currentLoggedInUser!.role == 'technician'
                      ? '👨‍🔧 فني: ${currentLoggedInUser!.name ?? currentLoggedInUser!.email}'
                      : '👑 مدير النظام',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFD4AF37),
                    fontFamily: 'Cairo',
                  ),
                ),
            ],
          ),
          leading: IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: primaryColor,
            ),
            onPressed: _toggleTheme,
            tooltip: 'تغيير المظهر',
          ),
          actions: [
            // Sync status and button
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFD4AF37),
                        ),
                      ),
                    )
                  : Icon(Icons.sync, color: primaryColor),
              onPressed: _syncing ? null : _triggerGitHubSync,
              tooltip: 'مزامنة البيانات عبر GitHub',
            ),
            if (currentLoggedInUser?.role == 'technician')
              IconButton(
                icon: const Icon(
                  Icons.fingerprint_rounded,
                  color: Color(0xFFD4AF37),
                ),
                onPressed: () {
                  setState(() {
                    _forceShowAttendancePage = !_forceShowAttendancePage;
                  });
                },
                tooltip: 'تسجيل الحضور/الانصراف',
              ),
            if (currentLoggedInUser != null)
              IconButton(
                icon: Icon(Icons.logout_rounded, color: primaryColor),
                onPressed: _logout,
                tooltip: 'تسجيل الخروج',
              ),
          ],
        ),
        body: RepairsView(
          technicianFilter: currentLoggedInUser?.role == 'technician'
              ? currentLoggedInUser!.email
              : null,
        ),
      ),
    );
  }
}
