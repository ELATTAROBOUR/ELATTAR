import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'platform_stub.dart' if (dart.library.io) 'dart:io';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'theme/app_theme.dart';
import 'widgets/custom_toast.dart';
import 'package:path_provider/path_provider.dart';

import 'local_print_service.dart';
import 'models.dart';
import 'printer_settings_service.dart';
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'db_init.dart';
import 'database_helper.dart';
import 'hwid_service.dart';

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
import 'views/branches_view.dart';
import 'views/attendance_view.dart';
import 'services/whatsapp_service.dart';
import 'widgets/smart_search_dialog.dart';
import 'esc_pos_print_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize database factory (platform-appropriate via db_init.dart)
  setupDatabaseFactory();

  // Migrate JSON data to SQLite if necessary (ignore if database is missing for now)
  // Use timeouts to prevent hanging on web where path_provider has no implementation
  try {
    await DatabaseHelper.checkAndMigrate().timeout(const Duration(seconds: 10));
    await DatabaseHelper.loadComplaintNumber().timeout(
      const Duration(seconds: 5),
    );
  } on TimeoutException {
    debugPrint('Database initialization timed out (likely on web).');
  } on DatabaseMissingException {
    debugPrint(
      'Database is missing, migration deferred until user creates/restores database.',
    );
  } catch (e) {
    debugPrint('Migration checking failed: $e');
  }

  ThemeMode initialTheme = ThemeMode.dark;
  try {
    initialTheme = await ThemeSettingsService.load().timeout(
      const Duration(seconds: 3),
    );
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
      isDark(context) ? AppColors.scaffoldDark : AppColors.scaffoldLight;
  static Color cardBg(BuildContext context) =>
      isDark(context) ? AppColors.cardDark : AppColors.cardLight;
  static Color cardElevatedBg(BuildContext context) => isDark(context)
      ? AppColors.cardDarkElevated
      : AppColors.cardLightElevated;
  static Color text(BuildContext context) =>
      isDark(context) ? Colors.white : AppColors.textPrimary;
  static Color textMuted(BuildContext context) =>
      isDark(context) ? Colors.white70 : AppColors.textSecondary;
  static Color textTertiary(BuildContext context) =>
      isDark(context) ? Colors.white38 : AppColors.textTertiary;
  static Color textDisabled(BuildContext context) =>
      isDark(context) ? Colors.white30 : AppColors.textDisabled;
  static Color border(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);
  static Color surfaceTint(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.03)
      : Colors.black.withValues(alpha: 0.03);

  static Color searchBarBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF0D1520) : const Color(0xFFE8E2DA);
  static Color searchFieldBg(BuildContext context) =>
      isDark(context) ? const Color(0xFF162338) : Colors.white;

  static Color getHoverColor(BuildContext context, String status) {
    if (isDark(context)) {
      switch (status) {
        case 'pending':
          return const Color(0x1AF59E0B);
        case 'in_progress':
          return const Color(0x1A3B82F6);
        case 'repaired':
          return const Color(0x1A10B981);
        case 'delivered':
          return const Color(0x1AFFFFFF);
        case 'rejected':
          return const Color(0x1AEF4444);
        default:
          return AppColors.cardDark;
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

/// Custom scrollbar behavior for the desktop app - thicker, more visible scrollbar
class _AppScrollBehavior extends ScrollBehavior {
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics();
  }

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 8,
      radius: const Radius.circular(4),
      child: child,
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
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
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
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

  ThemeData _buildLightTheme() {
    return ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.blue,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: AppColors.scaffoldLight,
      colorScheme: ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surfaceLight,
        error: AppColors.error,
        onPrimary: AppColors.textOnPrimary,
        onSecondary: Colors.white,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.cardLight,
        foregroundColor: AppColors.primary,
        titleTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        color: AppColors.cardLight,
        surfaceTintColor: AppColors.cardLight,
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            fontFamily: 'Cairo',
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textDisabled),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.06),
        thickness: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          Colors.black.withValues(alpha: 0.2),
        ),
        trackColor: WidgetStateProperty.all(
          Colors.black.withValues(alpha: 0.05),
        ),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.blue,
      fontFamily: 'Cairo',
      scaffoldBackgroundColor: AppColors.scaffoldDark,
      colorScheme: ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.accent,
        surface: AppColors.surfaceDark,
        error: AppColors.error,
        onPrimary: AppColors.textOnPrimary,
        onSecondary: Colors.white,
        onSurface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppColors.cardDark,
        foregroundColor: AppColors.primary,
        titleTextStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        color: AppColors.cardDark,
        surfaceTintColor: AppColors.cardDark,
        shadowColor: Colors.black.withValues(alpha: 0.3),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          elevation: 0,
          shadowColor: AppColors.primary.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            fontFamily: 'Cairo',
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardDarkElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: const TextStyle(color: Colors.white70),
        hintStyle: const TextStyle(color: Colors.white38),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.06),
        thickness: 1,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.2),
        ),
        trackColor: WidgetStateProperty.all(
          Colors.white.withValues(alpha: 0.05),
        ),
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
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
                color: primaryColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
        final hiddenFile = File(
          "$localAppData/Microsoft/Windows/Shell/wincheck.dat",
        );
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

    // Fetch central status from Google Apps Script Web App if internet is available
    try {
      final scriptUrlStr =
          await DatabaseHelper.getSetting('activationScriptUrl') ??
          'https://script.google.com/macros/s/AKfycbymgT4dNqdfNvXHNv8bFpkWxAwShpVnIl19wWyeReywMMxJZrUHnbX-I9903RS72d6fSA/exec';
      final url = Uri.parse('$scriptUrlStr?hwid=$_hwid');
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData['status'] == 'success' && resData['found'] == true) {
          githubCheckAttempted = true;
          hwidFoundInCentral = true;
          final status = resData['clientStatus']?.toString().toLowerCase();
          final expiry = resData['expiryDate']?.toString();

          if (status == 'blocked' || status == 'محظور') {
            centralError =
                "تم حظر هذا الاشتراك لعدم سداد المستحقات أو لمخالفة الشروط. يرجى التواصل مع الدعم الفني.";
            await _clearLocalLicense();
          } else if (status == 'inactive' ||
              status == 'غير نشط' ||
              status == 'غير متفعل') {
            centralError =
                "هذا الاشتراك غير نشط حالياً. يرجى التواصل مع الدعم الفني لتفعيل الخدمة.";
            await _clearLocalLicense();
          } else if (expiry != null) {
            final isValid = await HwidService.verifyLicense(expiry);
            if (isValid) {
              await DatabaseHelper.saveActivationKey(expiry);
              final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
              if (localAppData.isNotEmpty) {
                final hiddenFile = File(
                  "$localAppData/Microsoft/Windows/Shell/wincheck.dat",
                );
                await hiddenFile.parent.create(recursive: true);
                await hiddenFile.writeAsString(expiry);
              }
              isLicenseValid = true;
            } else {
              // Extract the raw expiry part to provide appropriate error message
              final parts = expiry.split('.');
              final rawExpiry = parts[0];
              if (rawExpiry != 'LIFETIME') {
                try {
                  final expDate = DateTime.parse(rawExpiry);
                  if (DateTime.now().isAfter(
                    expDate.add(const Duration(days: 1)),
                  )) {
                    centralError =
                        "انتهت فترة الاشتراك الخاصة بك ($rawExpiry). يرجى التجديد للاستمرار.";
                  }
                } catch (_) {}
              }
              centralError ??=
                  "مفتاح ترخيص السحابة غير صالح أو تم التلاعب به ❌";
              await _clearLocalLicense();
            }
          }
        }
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
              final hiddenFile = File(
                "$localAppData/Microsoft/Windows/Shell/wincheck.dat",
              );
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
            final hiddenFile = File(
              "$localAppData/Microsoft/Windows/Shell/wincheck.dat",
            );
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
                final hiddenFile = File(
                  "$localAppData/Microsoft/Windows/Shell/wincheck.dat",
                );
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
      // Check for pending activation/registration info
      try {
        final pendingName = await DatabaseHelper.getSetting(
          'pendingClientName',
        );
        final pendingEmail = await DatabaseHelper.getSetting(
          'pendingClientEmail',
        );
        final pendingHash = await DatabaseHelper.getSetting(
          'pendingClientPasswordHash',
        );

        if (pendingName != null &&
            pendingName.isNotEmpty &&
            pendingEmail != null &&
            pendingEmail.isNotEmpty &&
            pendingHash != null &&
            pendingHash.isNotEmpty) {
          final newUser = AppUser(
            email: pendingEmail,
            passwordHash: pendingHash,
            role: 'manager',
          );

          await DatabaseHelper.saveRegistrationDetails(
            name: pendingName,
            hwid: _hwid,
            email: pendingEmail,
            passwordHash: pendingHash,
            user: newUser,
          );

          currentLoggedInUser = newUser;
          DatabaseHelper.currentLoggedInUser = newUser;

          // Clear pending registration details
          await DatabaseHelper.saveSetting('pendingClientName', "");
          await DatabaseHelper.saveSetting('pendingClientEmail', "");
          await DatabaseHelper.saveSetting('pendingClientPasswordHash', "");
        }
      } catch (e) {
        debugPrint("Error auto-registering pending client: $e");
      }

      String? effectiveEmail = await DatabaseHelper.getClientEmail();
      String? effectiveHash = await DatabaseHelper.getClientPasswordHash();
      final users = await DatabaseHelper.loadUsers();
      final hasManager = users.any((u) => u.role == 'manager');

      if ((effectiveEmail == null ||
              effectiveEmail.isEmpty ||
              effectiveHash == null ||
              effectiveHash.isEmpty) &&
          !hasManager) {
        setState(() {
          _pageState = LicensePageState.notRegistered;
        });
        return;
      }

      // If settings are missing but a manager user exists, restore the settings from the manager user
      if ((effectiveEmail == null ||
              effectiveEmail.isEmpty ||
              effectiveHash == null ||
              effectiveHash.isEmpty) &&
          hasManager) {
        try {
          final manager = users.firstWhere((u) => u.role == 'manager');
          await DatabaseHelper.saveClientCredentials(
            email: manager.email,
            passwordHash: manager.passwordHash,
            name: manager.name ?? "Manager",
          );
          effectiveEmail = manager.email;
          effectiveHash = manager.passwordHash;
        } catch (_) {}
      }

      // Auto-login: only if session was active before (user didn't explicitly log out)
      final sessionActive = await DatabaseHelper.getSetting('sessionActive');
      if (sessionActive == 'true' &&
          effectiveEmail != null &&
          effectiveEmail.isNotEmpty &&
          effectiveHash != null &&
          effectiveHash.isNotEmpty) {
        // Try to find user by email in the users table
        AppUser? user = await DatabaseHelper.getUserByEmail(effectiveEmail);
        if (user != null && user.passwordHash == effectiveHash) {
          // Found matching user → auto-authenticate
          currentLoggedInUser = user;
          DatabaseHelper.currentLoggedInUser = user;
          try {
            await DatabaseHelper.saveSetting('sessionActive', 'true');
          } catch (_) {}
          setState(() {
            _pageState = LicensePageState.authenticated;
          });
          return;
        }

        // Fallback: user might not be in users table yet (legacy migration).
        // If we have valid credentials in settings, create the user automatically.
        final newMgr = AppUser(
          email: effectiveEmail,
          passwordHash: effectiveHash,
          role: 'manager',
        );
        await DatabaseHelper.saveUser(newMgr);
        currentLoggedInUser = newMgr;
        DatabaseHelper.currentLoggedInUser = newMgr;
        try {
          await DatabaseHelper.saveSetting('sessionActive', 'true');
        } catch (_) {}
        setState(() {
          _pageState = LicensePageState.authenticated;
        });
        return;
      }

      // If auto-login failed, show login screen
      setState(() {
        _pageState = LicensePageState.login;
      });
    } else {
      setState(() {
        _pageState = LicensePageState.notActivated;
        if (githubCheckAttempted &&
            hwidFoundInCentral &&
            centralError != null) {
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
          final hiddenFile = File(
            "$localAppData/Microsoft/Windows/Shell/wincheck.dat",
          );
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
      final users = await DatabaseHelper.loadUsers();
      final hasManager = users.any((u) => u.role == 'manager');

      // If settings are missing but a manager user exists, restore the settings from the manager user
      if ((email == null ||
              email.isEmpty ||
              passHash == null ||
              passHash.isEmpty) &&
          hasManager) {
        try {
          final manager = users.firstWhere((u) => u.role == 'manager');
          await DatabaseHelper.saveClientCredentials(
            email: manager.email,
            passwordHash: manager.passwordHash,
            name: manager.name ?? "Manager",
          );
        } catch (_) {}
      }

      setState(() {
        _activating = false;
        if ((email == null ||
                email.isEmpty ||
                passHash == null ||
                passHash.isEmpty) &&
            !hasManager) {
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

  Future<void> _sendActivationRequest() async {
    final name = _regUsernameController.text.trim();
    final email = _regEmailController.text.trim();
    final password = _regPasswordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "الرجاء ملء جميع الحقول المطلوبة لطلب التفعيل ⚠️",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_isValidGmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "الرجاء إدخال بريد إلكتروني Gmail صالح ⚠️",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "يجب ألا تقل كلمة المرور عن 8 خانات ⚠️",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo'),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _registering = true;
    });

    try {
      // 1. Save locally as pending registration info
      final hashed = hashPassword(password);
      await DatabaseHelper.saveSetting('pendingClientName', name);
      await DatabaseHelper.saveSetting('pendingClientEmail', email);
      await DatabaseHelper.saveSetting('pendingClientPasswordHash', hashed);

      // 2. Prepare JSON data payload
      final payload = {
        "name": name,
        "email": email,
        "password": password,
        "hwid": _hwid,
      };

      // 3. Send via POST request
      final scriptUrlStr =
          await DatabaseHelper.getSetting('activationScriptUrl') ??
          'https://script.google.com/macros/s/AKfycbymgT4dNqdfNvXHNv8bFpkWxAwShpVnIl19wWyeReywMMxJZrUHnbX-I9903RS72d6fSA/exec';
      final url = Uri.parse(scriptUrlStr);

      final response = await _postToScript(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "✅ تم إرسال طلب التفعيل بنجاح! يرجى إبلاغ الدعم الفني.",
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        throw Exception("Server returned code ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error sending activation request email: $e");

      // Fallback: Show copy dialog with details so they can send it manually via WhatsApp
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text(
                "تعذر الإرسال التلقائي",
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "لم نتمكن من إرسال الطلب تلقائياً بسبب انقطاع الإنترنت أو عدم إعداد الرابط. يرجى نسخ البيانات التالية وإرسالها يدوياً للدعم الفني:",
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.black26,
                    child: SelectableText(
                      "طلب تفعيل العطار استور:\nالاسم: $name\nالبريد: $email\nكلمة المرور: $password\nرمز الجهاز (HWID): $_hwid",
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text:
                            "طلب تفعيل العطار استور:\nالاسم: $name\nالبريد: $email\nكلمة المرور: $password\nرمز الجهاز (HWID): $_hwid",
                      ),
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("📋 تم نسخ البيانات للحافظة"),
                      ),
                    );
                  },
                  child: const Text(
                    "نسخ البيانات وإغلاق",
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } finally {
      setState(() {
        _registering = false;
      });
    }
  }

  Future<http.Response> _postToScript(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final client = http.Client();
    try {
      var request = http.Request('POST', url);
      if (headers != null) request.headers.addAll(headers);
      if (body != null) {
        if (body is String) {
          request.body = body;
        } else {
          request.body = jsonEncode(body);
        }
      }
      request.followRedirects = false;

      var responseStream = await client.send(request).timeout(timeout);
      var response = await http.Response.fromStream(responseStream);

      if (response.statusCode == 302 ||
          response.statusCode == 301 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final redirectUrlStr = response.headers['location'];
        if (redirectUrlStr != null) {
          final redirectUrl = Uri.parse(redirectUrlStr);
          var redirectRequest = http.Request('POST', redirectUrl);
          if (headers != null) redirectRequest.headers.addAll(headers);
          if (body != null) {
            if (body is String) {
              redirectRequest.body = body;
            } else {
              redirectRequest.body = jsonEncode(body);
            }
          }
          var redirectResponseStream = await client
              .send(redirectRequest)
              .timeout(timeout);
          return http.Response.fromStream(redirectResponseStream);
        }
      }
      return response;
    } finally {
      client.close();
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
    // Database restore from file is not available on web.
    // On desktop, this would open a file picker to select an .db file.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "⚠️ استيراد قاعدة البيانات من ملف متاح فقط في نسخة ويندوز.\nيمكنك استخدام مزامنة Supabase لاستعادة البيانات.",
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 14),
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 4),
        ),
      );
    }
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
            prefixIcon: Icon(
              Icons.phone_android_rounded,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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

    if (username.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
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
      final newUser = AppUser(
        email: email,
        passwordHash: hashed,
        role: 'manager',
      );

      await DatabaseHelper.saveRegistrationDetails(
        name: username,
        hwid: _hwid,
        email: email,
        passwordHash: hashed,
        user: newUser,
      );

      currentLoggedInUser = newUser;
      DatabaseHelper.currentLoggedInUser = newUser;

      try {
        await DatabaseHelper.saveSetting('sessionActive', 'true');
      } catch (_) {}

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
      if (storedName != null &&
          storedName.trim().toLowerCase() == email.toLowerCase() &&
          storedEmail != null) {
        user = await DatabaseHelper.getUserByEmail(storedEmail);
      }
    }

    bool isLoginValid = false;
    if (user != null) {
      if (user.passwordHash == enteredHash) {
        currentLoggedInUser = user;
        DatabaseHelper.currentLoggedInUser = user;
        isLoginValid = true;
      }
    } else {
      // Fallback/backward compatibility for first client settings user
      final storedEmail = await DatabaseHelper.getClientEmail();
      final storedHash = await DatabaseHelper.getClientPasswordHash();
      final storedName = await DatabaseHelper.getClientName();
      if (((storedEmail?.trim().toLowerCase() == email.toLowerCase()) ||
              (storedName?.trim().toLowerCase() == email.toLowerCase())) &&
          storedHash == enteredHash &&
          storedEmail != null) {
        final newMgr = AppUser(
          email: storedEmail,
          passwordHash: enteredHash,
          role: 'manager',
        );
        await DatabaseHelper.saveUser(newMgr);
        currentLoggedInUser = newMgr;
        DatabaseHelper.currentLoggedInUser = newMgr;
        isLoginValid = true;
      }
    }

    if (isLoginValid) {
      try {
        await DatabaseHelper.saveSetting('sessionActive', 'true');
      } catch (_) {}
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
          try {
            DatabaseHelper.saveSetting('sessionActive', 'false');
          } catch (_) {}
          currentLoggedInUser = null;
          DatabaseHelper.currentLoggedInUser = null;
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
          child: Icon(Icons.vpn_key_rounded, color: primaryColor, size: 48),
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
            border: Border.all(color: textColor.withValues(alpha: 0.1)),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                      fontWeight: FontWeight.bold,
                    ),
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
            suffixIcon: Icon(
              Icons.key,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF1A2A3A),
                      ),
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
            border: Border.all(color: primaryColor.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.headset_mic_rounded,
                    color: primaryColor,
                    size: 20,
                  ),
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
        const Divider(height: 40, thickness: 1, color: Colors.grey),
        Text(
          "📝 طلب تسجيل وتفعيل سريع",
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "أدخل بياناتك هنا لإرسال طلب تفعيل للدعم الفني مباشرة. بمجرد تفعيل حسابك من الإدارة، سيفتح البرنامج تلقائياً.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: textMutedColor,
          ),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "الاسم / اسم المحل:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regUsernameController,
          style: TextStyle(color: textColor, fontSize: 15),
          decoration: InputDecoration(
            hintText: "أدخل اسم العميل أو اسم المحل",
            prefixIcon: Icon(
              Icons.person_outline_rounded,
              color: primaryColor.withValues(alpha: 0.7),
              size: 20,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "البريد الإلكتروني (Gmail):",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regEmailController,
          style: TextStyle(color: textColor, fontSize: 15),
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: "example@gmail.com",
            prefixIcon: Icon(
              Icons.email_outlined,
              color: primaryColor.withValues(alpha: 0.7),
              size: 20,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "كلمة المرور المطلوبة:",
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _regPasswordController,
          style: TextStyle(color: textColor, fontSize: 15),
          obscureText: !_regPasswordVisible,
          decoration: InputDecoration(
            hintText: "أدخل كلمة مرور لا تقل عن 8 أحرف",
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              color: primaryColor.withValues(alpha: 0.7),
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _regPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: primaryColor.withValues(alpha: 0.7),
                size: 20,
              ),
              onPressed: () {
                setState(() {
                  _regPasswordVisible = !_regPasswordVisible;
                });
              },
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E2F41),
              foregroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: primaryColor.withValues(alpha: 0.5)),
              ),
              elevation: 2,
            ),
            onPressed: _registering ? null : _sendActivationRequest,
            icon: _registering
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
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text(
              "إرسال طلب تفعيل للدعم الفني",
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
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
          child: Icon(Icons.security_rounded, color: primaryColor, size: 48),
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
            prefixIcon: Icon(
              Icons.person_outline_rounded,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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
            prefixIcon: Icon(
              Icons.mail_outline_rounded,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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
            prefixIcon: Icon(
              Icons.lock_clock_outlined,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF1A2A3A),
                      ),
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
          child: Icon(Icons.lock_person_rounded, color: primaryColor, size: 48),
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
            prefixIcon: Icon(
              Icons.mail_outline_rounded,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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
            prefixIcon: Icon(
              Icons.lock_outline_rounded,
              color: primaryColor.withValues(alpha: 0.7),
            ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF1A2A3A),
                      ),
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
  final Map<String, int> _badgeCounts = {};
  Timer? _badgeTimer;
  final Set<String> _shownAlertSignatures = {};

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
        view: RepairsView(
          technicianFilter: currentLoggedInUser?.role == 'technician'
              ? (currentLoggedInUser!.name ?? currentLoggedInUser!.email)
              : null,
        ),
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
      MenuItemDef(
        title: '🏪 إدارة الفروع',
        icon: Icons.store_mall_directory_rounded,
        view: const BranchesView(),
        allowedRoles: ['manager'],
      ),
      MenuItemDef(
        title: '⏰ الحضور والانصراف',
        icon: Icons.access_time_rounded,
        view: const AttendanceView(),
        allowedRoles: ['manager', 'staff', 'technician'],
      ),
    ];

    final role = currentLoggedInUser?.role ?? 'manager';
    _filteredMenuItems = allMenuItems
        .where((item) => item.allowedRoles.contains(role))
        .toList();
    _selectedIndex = 0;

    _startSyncTimer();
    _updateBadgeCounts();
    _badgeTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => _updateBadgeCounts(),
    );

    // Printers: local HTTP server handles auto-connect on startup.
    // No browser API initialization needed.
  }

  Timer? _syncTimer;
  WebSocket? _attendanceWebSocket;
  WebSocket? _syncWebSocket;

  void _startSyncTimer() {
    // Run initial sync immediately
    _runPeriodicSync();
    // Periodic GitHub sync every 10 minutes (silent background backup)
    _syncTimer = Timer.periodic(const Duration(minutes: 10), (timer) async {
      await _runPeriodicSync();
    });
    // Start the instant notification listeners
    _startInstantAttendanceListener();
    _startInstantSyncListener();
  }

  void _startInstantAttendanceListener() async {
    final url = 'wss://ntfy.sh/elattar_attendance_obourdist_9f70cb7a/ws';
    debugPrint('Connecting to instant attendance WebSocket...');
    try {
      _attendanceWebSocket = await WebSocket.connect(
        url,
      ).timeout(const Duration(seconds: 10));
      debugPrint('Connected to instant attendance WebSocket successfully.');

      _attendanceWebSocket!.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['event'] == 'message') {
              final msgStr = data['message'] as String?;
              if (msgStr != null && msgStr.contains('|')) {
                final parts = msgStr.split('|');
                final techName = parts[0];
                final action = parts[1]; // "حضور" or "انصراف"

                debugPrint(
                  'Instant attendance alert received via WS: $techName | $action',
                );

                // Construct a temporary ModificationLog to pass to _showAttendanceNotification
                final tempLog = ModificationLog(
                  id: null,
                  actionDate: DateTime.now().toIso8601String(),
                  actionType: 'attendance',
                  itemType: action == 'حضور' ? 'حضور' : 'انصراف',
                  itemName: techName,
                  details: action == 'حضور'
                      ? 'تسجيل حضور من تطبيق الموبايل'
                      : 'تسجيل انصراف من تطبيق الموبايل',
                );

                if (mounted) {
                  _showAttendanceNotification(tempLog);
                }

                // Instantly trigger a background sync to fetch the actual database record
                DatabaseHelper.syncDatabase();
              }
            }
          } catch (e) {
            debugPrint('Error parsing attendance WS message: $e');
          }
        },
        onError: (error) {
          debugPrint(
            'Attendance WebSocket error: $error. Reconnecting in 5 seconds...',
          );
          _reconnectInstantAttendanceListener();
        },
        onDone: () {
          debugPrint(
            'Attendance WebSocket closed. Reconnecting in 5 seconds...',
          );
          _reconnectInstantAttendanceListener();
        },
      );
    } catch (e) {
      debugPrint(
        'Failed to connect to attendance WebSocket: $e. Retrying in 5 seconds...',
      );
      _reconnectInstantAttendanceListener();
    }
  }

  void _reconnectInstantAttendanceListener() {
    _attendanceWebSocket?.close();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _startInstantAttendanceListener();
      }
    });
  }

  void _startInstantSyncListener() async {
    final url = 'wss://ntfy.sh/elattar_sync_obourdist_9f70cb7a/ws';
    debugPrint('Connecting to instant sync WebSocket...');
    try {
      _syncWebSocket = await WebSocket.connect(
        url,
      ).timeout(const Duration(seconds: 10));
      debugPrint('Connected to instant sync WebSocket successfully.');

      _syncWebSocket!.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            if (data['event'] == 'message') {
              final sender = data['message'] as String?;
              if (sender == 'mobile') {
                debugPrint(
                  'Instant sync ping received from mobile. Triggering database sync...',
                );
                DatabaseHelper.syncDatabase();
              }
            }
          } catch (e) {
            debugPrint('Error parsing sync WS message: $e');
          }
        },
        onError: (error) {
          debugPrint(
            'Sync WebSocket error: $error. Reconnecting in 5 seconds...',
          );
          _reconnectInstantSyncListener();
        },
        onDone: () {
          debugPrint('Sync WebSocket closed. Reconnecting in 5 seconds...');
          _reconnectInstantSyncListener();
        },
      );
    } catch (e) {
      debugPrint(
        'Failed to connect to sync WebSocket: $e. Retrying in 5 seconds...',
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

  Future<void> _runPeriodicSync() async {
    try {
      debugPrint('Periodic Background Sync triggered.');
      await DatabaseHelper.syncDatabase();
      // Check for new attendance notifications after sync
      await _checkForAttendanceNotifications();
    } catch (e) {
      debugPrint('Periodic Sync Error: $e');
    }
  }

  /// Check for new attendance check-in/out logs and show beautiful notification
  Future<void> _checkForAttendanceNotifications() async {
    try {
      // Defensively check if lastSeenAttendanceLogId is initialized
      final lastSeenStr = await DatabaseHelper.getSetting(
        'lastSeenAttendanceLogId',
      );
      if (lastSeenStr == null) {
        // If it's the first time running, set it to the max existing attendance log ID.
        // This avoids popping up alerts for historical check-ins on startup.
        final database = await DatabaseHelper.db;
        final maxIdResult = await database.rawQuery(
          "SELECT MAX(id) as max_id FROM modification_logs WHERE actionType = 'attendance'",
        );
        int maxId = 0;
        if (maxIdResult.isNotEmpty && maxIdResult.first['max_id'] != null) {
          maxId = maxIdResult.first['max_id'] as int;
        }
        await DatabaseHelper.updateLastSeenAttendanceLogId(maxId);
        debugPrint(
          'Initialized lastSeenAttendanceLogId to $maxId to prevent historical alerts.',
        );
        return;
      }

      final newLogs = await DatabaseHelper.checkUnseenAttendanceLogs();
      if (newLogs.isEmpty) return;

      for (final log in newLogs) {
        if (mounted) {
          _showAttendanceNotification(log);
        }
        // Update last seen id
        if (log.id != null) {
          await DatabaseHelper.updateLastSeenAttendanceLogId(log.id!);
        }
      }
    } catch (e) {
      debugPrint('Error checking attendance notifications: $e');
    }
  }

  /// Show a beautiful animated attendance notification overlay
  void _showAttendanceNotification(ModificationLog log) {
    final isCheckIn = log.itemType == 'حضور';
    final action = isCheckIn ? 'تسجيل حضور' : 'تسجيل انصراف';
    final techName = log.itemName;

    // Deduplicate alerts using signature (technician + action + today's date)
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final signature = "$techName|$action|$todayStr";
    if (_shownAlertSignatures.contains(signature)) {
      return;
    }
    _shownAlertSignatures.add(signature);

    final icon = isCheckIn ? Icons.login_rounded : Icons.logout_rounded;
    final iconColor = isCheckIn
        ? const Color(0xFF4CAF50)
        : const Color(0xFFFF9800);
    final bgGradient = isCheckIn
        ? const LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)])
        : const LinearGradient(colors: [Color(0xFFE65100), Color(0xFFF57C00)]);

    OverlayEntry? overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) {
        return _AttendanceNotificationWidget(
          techName: techName,
          action: isCheckIn ? 'تسجيل حضور' : 'تسجيل انصراف',
          icon: icon,
          iconColor: iconColor,
          bgGradient: bgGradient,
          onDismiss: () {
            overlayEntry?.remove();
          },
        );
      },
    );

    Overlay.of(context).insert(overlayEntry);

    // Auto-remove after 6 seconds
    Future.delayed(const Duration(seconds: 6), () {
      try {
        overlayEntry?.remove();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _badgeTimer?.cancel();
    _attendanceWebSocket?.close();
    _syncWebSocket?.close();
    super.dispose();
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
      final idx = _filteredMenuItems.indexWhere(
        (item) => item.title == targetTitle,
      );
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

  void _showWhatsAppSettings() {
    showDialog(
      context: context,
      builder: (context) => _WhatsAppSettingsDialog(),
    );
  }

  void _showSmartSearch() {
    SmartSearchDialog.show(
      context,
      onNavigate: (menuTitle, itemId) {
        final idx = _filteredMenuItems.indexWhere((m) => m.title == menuTitle);
        if (idx != -1) {
          setState(() => _selectedIndex = idx);
        }
      },
    );
  }

  void _toggleTheme() async {
    final current = themeNotifier.value;
    final newMode = current == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeNotifier.value = newMode;
    await ThemeSettingsService.save(newMode);
  }

  Future<void> _updateBadgeCounts() async {
    try {
      // Count pending repairs
      final tickets = await DatabaseHelper.loadTickets();
      final pendingRepairs = tickets
          .where((t) => t.status != 'تم الاستلام' && t.status != 'ملغي')
          .length;

      // Count active deferred payments
      final deferred = await DatabaseHelper.loadDeferredPayments();
      final activeDeferred = deferred
          .where((d) => d.remainingAmount > 0)
          .length;

      // Count low stock items (quantity < 3)
      final accessories = await DatabaseHelper.loadAccessories();
      int lowStockCount = accessories.where((a) => a.quantity < 3).length;
      final devices = await DatabaseHelper.loadDevices();
      lowStockCount += devices.where((d) => d.quantity < 3).length;
      final spareParts = await DatabaseHelper.loadSpareParts();
      lowStockCount += spareParts.where((p) => p.quantity < 3).length;

      if (mounted) {
        setState(() {
          _badgeCounts['🔧 الصيانة والإصلاحات'] = pendingRepairs;
          _badgeCounts['💳 حسابات العملاء الآجلة'] = activeDeferred;
          _badgeCounts['📦 المخزن والجرد'] = lowStockCount;
        });
      }
    } catch (_) {
      // Silently ignore badge update errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textColor = AppTheme.text(context);
    final primaryGold = AppColors.primary;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 768;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _showSmartSearch,
        },
        child: Focus(
          autofocus: true,
          child: isMobile
              ? _buildMobileLayout(context, isDark, primaryGold)
              : _buildDesktopLayout(context, isDark, textColor, primaryGold),
        ),
      ),
    );
  }

  /// Desktop layout: fixed sidebar (280px) + content area
  Widget _buildDesktopLayout(
    BuildContext context,
    bool isDark,
    Color textColor,
    Color primaryGold,
  ) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      body: Row(
        children: [
          // ═══════════════════════════════════════════════
          // SIDEBAR — Premium Glass Design
          // ═══════════════════════════════════════════════
          Container(
            width: 280,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xFF0D1520),
                        const Color(0xFF0A1220),
                        const Color(0xFF080E1A),
                      ]
                    : [
                        const Color(0xFFF0EBE4),
                        const Color(0xFFE8E2DA),
                        const Color(0xFFE5DFD7),
                      ],
              ),
              border: Border(
                left: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
            ),
            child: Column(
              children: [
                // ── Branding / Header ──
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        if (isDark) ...[
                          AppColors.primary.withValues(alpha: 0.04),
                          const Color(0xFF0D1520),
                        ] else ...[
                          AppColors.primary.withValues(alpha: 0.06),
                          const Color(0xFFF0EBE4),
                        ],
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Logo with glow
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          image: DecorationImage(
                            image: AssetImage(
                              isDark
                                  ? 'assets/image/logod.jpg'
                                  : 'assets/image/logow.jpg',
                            ),
                            fit: BoxFit.cover,
                          ),
                          boxShadow: isDark ? AppShadows.goldGlow : null,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ShaderMask(
                        shaderCallback: (bounds) => LinearGradient(
                          colors: [
                            AppColors.primary,
                            AppColors.primaryLight,
                            AppColors.primary,
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ).createShader(bounds),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Text(
                              'DESIGNED BY',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                letterSpacing: 1.5,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'BELALZAGHL0L',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontFamily: 'Cairo',
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Search bar
                      _SidebarSearchBar(onTap: _showSmartSearch),
                      const SizedBox(height: 10),

                      // Branch indicator
                      _BranchIndicator(
                        branch: DatabaseHelper.currentBranch,
                        onTap: () {
                          final idx = _filteredMenuItems.indexWhere(
                            (m) => m.title.contains('إدارة الفروع'),
                          );
                          if (idx != -1) {
                            setState(() => _selectedIndex = idx);
                          }
                        },
                      ),
                    ],
                  ),
                ),

                // Divider
                Container(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06),
                ),
                const SizedBox(height: 8),

                // ── Menu Items ──
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _filteredMenuItems.length,
                    itemBuilder: (context, index) {
                      final item = _filteredMenuItems[index];
                      final isSelected = _selectedIndex == index;
                      return _SidebarMenuItem(
                        item: item,
                        isSelected: isSelected,
                        isDark: isDark,
                        badgeCount: _badgeCounts[item.title] ?? 0,
                        onTap: () {
                          setState(() => _selectedIndex = index);
                        },
                      );
                    },
                  ),
                ),

                // ── Bottom Controls ──
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      _SidebarBottomTile(
                        icon: isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        iconColor: primaryGold,
                        label: isDark ? 'الوضع المضيء' : 'الوضع الداكن',
                        isDark: isDark,
                        onTap: _toggleTheme,
                      ),
                      const SizedBox(height: 2),
                      _SidebarBottomTile(
                        icon: Icons.chat_rounded,
                        iconColor: const Color(0xFF25D366),
                        label: 'واتساب API',
                        isDark: isDark,
                        onTap: _showWhatsAppSettings,
                      ),
                      const SizedBox(height: 2),
                      _SidebarBottomTile(
                        icon: Icons.print_rounded,
                        iconColor: null,
                        label: 'إعدادات الطابعة',
                        isDark: isDark,
                        onTap: _showPrinterSettings,
                      ),
                      const SizedBox(height: 2),
                      _SidebarBottomTile(
                        icon: Icons.logout_rounded,
                        iconColor: AppColors.error,
                        label: 'تسجيل الخروج',
                        isDark: isDark,
                        labelColor: AppColors.error,
                        onTap: () => widget.onLogout?.call(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ═══════════════════════════════════════════════
          // MAIN VIEW AREA
          // ═══════════════════════════════════════════════
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: isDark
                    ? AppColors.surfaceDarkGradient
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.scaffoldLight,
                          AppColors.surfaceLight,
                        ],
                      ),
              ),
              child: ScrollConfiguration(
                behavior: _AppScrollBehavior(),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: const Offset(0.06, 0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          ),
                        );
                      },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_selectedIndex),
                    child: _filteredMenuItems[_selectedIndex].view,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile layout: Scaffold with AppBar + Drawer + full-width content
  Widget _buildMobileLayout(
    BuildContext context,
    bool isDark,
    Color primaryGold,
  ) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF0D1520)
            : const Color(0xFFF0EBE4),
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            iconSize: 28,
            color: primaryGold,
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'القائمة',
          ),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [primaryGold, AppColors.primaryLight, primaryGold],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: const Text(
            'ELATTAR',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFamily: 'Cairo',
              letterSpacing: 1.5,
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: Color(0xFFD4AF37)),
            onPressed: _showSmartSearch,
            tooltip: 'بحث',
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: isDark
            ? const Color(0xFF0A1220)
            : const Color(0xFFF0EBE4),
        width: 300,
        child: SafeArea(
          child: Column(
            children: [
              // ── Mobile Drawer Header ──
              Container(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      if (isDark) ...[
                        AppColors.primary.withValues(alpha: 0.04),
                        const Color(0xFF0D1520),
                      ] else ...[
                        AppColors.primary.withValues(alpha: 0.06),
                        const Color(0xFFF0EBE4),
                      ],
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    // Logo
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: AssetImage(
                            isDark
                                ? 'assets/image/logod.jpg'
                                : 'assets/image/logow.jpg',
                          ),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'العطار استور',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                        fontFamily: 'Cairo',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'BELALZAGHL0L',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Search bar in drawer
                    _SidebarSearchBar(
                      onTap: () {
                        Navigator.pop(context); // Close drawer
                        _showSmartSearch();
                      },
                    ),
                    const SizedBox(height: 8),
                    // Branch indicator
                    _BranchIndicator(
                      branch: DatabaseHelper.currentBranch,
                      onTap: () {
                        Navigator.pop(context);
                        final idx = _filteredMenuItems.indexWhere(
                          (m) => m.title.contains('إدارة الفروع'),
                        );
                        if (idx != -1) {
                          setState(() => _selectedIndex = idx);
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Divider
              Container(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
              const SizedBox(height: 4),

              // ── Menu Items ──
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 4),
                  itemCount: _filteredMenuItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredMenuItems[index];
                    final isSelected = _selectedIndex == index;
                    return _SidebarMenuItem(
                      item: item,
                      isSelected: isSelected,
                      isDark: isDark,
                      badgeCount: _badgeCounts[item.title] ?? 0,
                      onTap: () {
                        setState(() => _selectedIndex = index);
                        Navigator.pop(context); // Close drawer
                      },
                    );
                  },
                ),
              ),

              // ── Bottom Controls ──
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    _SidebarBottomTile(
                      icon: isDark
                          ? Icons.light_mode_rounded
                          : Icons.dark_mode_rounded,
                      iconColor: primaryGold,
                      label: isDark ? 'الوضع المضيء' : 'الوضع الداكن',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        _toggleTheme();
                      },
                    ),
                    const SizedBox(height: 2),
                    _SidebarBottomTile(
                      icon: Icons.chat_rounded,
                      iconColor: const Color(0xFF25D366),
                      label: 'واتساب API',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        _showWhatsAppSettings();
                      },
                    ),
                    const SizedBox(height: 2),
                    _SidebarBottomTile(
                      icon: Icons.print_rounded,
                      iconColor: null,
                      label: 'إعدادات الطابعة',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(context);
                        _showPrinterSettings();
                      },
                    ),
                    const SizedBox(height: 2),
                    _SidebarBottomTile(
                      icon: Icons.logout_rounded,
                      iconColor: AppColors.error,
                      label: 'تسجيل الخروج',
                      isDark: isDark,
                      labelColor: AppColors.error,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onLogout?.call();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? AppColors.surfaceDarkGradient
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.scaffoldLight, AppColors.surfaceLight],
                  ),
          ),
          child: ScrollConfiguration(
            behavior: _AppScrollBehavior(),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutCubic,
                          ),
                        ),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<int>(_selectedIndex),
                child: _filteredMenuItems[_selectedIndex].view,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 🎯 Premium Sidebar Widgets
// ═════════════════════════════════════════════════════════════════════════════

/// Search bar button in the sidebar
class _SidebarSearchBar extends StatelessWidget {
  final VoidCallback onTap;
  const _SidebarSearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 18,
              color: isDark ? Colors.white38 : AppColors.textTertiary,
            ),
            const SizedBox(width: 10),
            Text(
              'بحث سريع…',
              style: TextStyle(
                color: isDark ? Colors.white38 : AppColors.textTertiary,
                fontSize: 13,
                fontFamily: 'Cairo',
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Ctrl+F',
                style: TextStyle(
                  color: isDark ? Colors.white30 : AppColors.textDisabled,
                  fontSize: 10,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modern sidebar menu item with hover and active states
class _SidebarMenuItem extends StatefulWidget {
  final MenuItemDef item;
  final bool isSelected;
  final bool isDark;
  final int badgeCount;
  final VoidCallback onTap;

  const _SidebarMenuItem({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.badgeCount,
    required this.onTap,
  });

  @override
  State<_SidebarMenuItem> createState() => _SidebarMenuItemState();
}

class _SidebarMenuItemState extends State<_SidebarMenuItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isSelected = widget.isSelected;
    final isDark = widget.isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            curve: AppAnimations.defaultCurve,
            padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
            decoration: AppDecorations.sidebarItem(
              isSelected: isSelected,
              isDark: isDark,
            ),
            child: Row(
              children: [
                // Icon with subtle background when selected
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : (_isHovered
                              ? (isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04))
                              : Colors.transparent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.icon,
                    color: isSelected
                        ? AppColors.primary
                        : (_isHovered
                              ? (isDark ? Colors.white : AppColors.textPrimary)
                              : (isDark
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : AppColors.textSecondary)),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Title
                Expanded(
                  child: Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? AppColors.primary
                          : (_isHovered
                                ? (isDark
                                      ? Colors.white
                                      : AppColors.textPrimary)
                                : (isDark
                                      ? Colors.white.withValues(alpha: 0.85)
                                      : AppColors.textPrimary)),
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
                // Badge
                if (widget.badgeCount > 0)
                  AnimatedContainer(
                    duration: AppAnimations.fast,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.errorGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.error.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${widget.badgeCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
                // Animated selection indicator
                if (isSelected)
                  Container(
                    width: 3,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: AppShadows.goldGlow,
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

/// Bottom settings tile in sidebar
class _SidebarBottomTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  final Color? labelColor;

  const _SidebarBottomTile({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Row(
          children: [
            Icon(
              icon,
              color:
                  iconColor ??
                  (isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : AppColors.textSecondary),
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color:
                    labelColor ??
                    (isDark
                        ? Colors.white.withValues(alpha: 0.8)
                        : AppColors.textPrimary),
                fontSize: 13,
                fontFamily: 'Cairo',
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
  final Set<String> presentTechnicians;

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
    this.presentTechnicians = const {},
  });

  @override
  State<TicketCard> createState() => _TicketCardState();
}

class _TicketCardState extends State<TicketCard> {
  bool _isHovered = false;

  void _showBuyDeviceDialog(BuildContext context, Ticket ticket) async {
    final costController = TextEditingController(text: '0.0');
    final priceController = TextEditingController(text: '0.0');
    final imeiController = TextEditingController(
      text: ticket.complaintNumber ?? '',
    );

    final warehouses = await DatabaseHelper.loadWarehouses();
    String selectedWarehouse = warehouses.isNotEmpty
        ? warehouses.first.name
        : 'المحل الرئيسي';

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
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    color: primaryGold,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'شراء جهاز عميل للمستعمل',
                    style: TextStyle(
                      color: primaryGold,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: costController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(color: textColor),
                        decoration: const InputDecoration(
                          labelText: 'سعر الشراء من العميل (ج.م) *',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: TextStyle(color: textColor),
                        decoration: const InputDecoration(
                          labelText: 'سعر البيع المقترح للمستعمل (ج.م) *',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: imeiController,
                        style: TextStyle(color: textColor),
                        decoration: const InputDecoration(
                          labelText: 'رقم السيريال / IMEI',
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedWarehouse,
                        dropdownColor: AppTheme.cardBg(context),
                        style: TextStyle(color: textColor, fontSize: 16),
                        decoration: const InputDecoration(
                          labelText: 'المخزن *',
                        ),
                        items: warehouses
                            .map(
                              (w) => DropdownMenuItem(
                                value: w.name,
                                child: Text(w.name),
                              ),
                            )
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
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: AppTheme.textMuted(context),
                      fontSize: 16,
                    ),
                  ),
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
                      widget.ticket,
                      'bought_from_customer',
                    );

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ تم شراء الجهاز بمبلغ ${cost.toStringAsFixed(2)} ج.م وتحويله للمستعمل بنجاح!',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: const Text(
                    'شراء وحفظ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
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
                    color: getStatusColor(
                      widget.ticket.status,
                    ).withValues(alpha: 0.3),
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
            splashColor: getStatusColor(
              widget.ticket.status,
            ).withValues(alpha: 0.15),
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
                          color: getStatusColor(
                            widget.ticket.status,
                          ).withValues(alpha: _isHovered ? 0.25 : 0.15),
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
                                  backgroundColor: Colors.blueAccent.withValues(
                                    alpha: 0.15,
                                  ),
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
                                  backgroundColor: Colors.blue.withValues(
                                    alpha: 0.15,
                                  ),
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
                                  backgroundColor: Colors.teal.withValues(
                                    alpha: 0.15,
                                  ),
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
                                  backgroundColor: Colors.green.withValues(
                                    alpha: 0.15,
                                  ),
                                  foregroundColor: Colors.greenAccent.shade400,
                                  onPressed: () =>
                                      widget.onPrintReceipt(widget.ticket),
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
                                  widget.ticket,
                                  'pending',
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.build,
                                color: Colors.blue,
                                isActive: widget.ticket.status == 'in_progress',
                                tooltip: 'تحت الصيانة',
                                onTap: () => widget.onStatusChanged(
                                  widget.ticket,
                                  'in_progress',
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.check_circle,
                                color: Colors.green,
                                isActive: widget.ticket.status == 'repaired',
                                tooltip: 'تم الإصلاح',
                                onTap: () => widget.onStatusChanged(
                                  widget.ticket,
                                  'repaired',
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.delivery_dining,
                                color: Colors.grey,
                                isActive: widget.ticket.status == 'delivered',
                                tooltip: 'تم التسليم',
                                onTap: () => widget.onStatusChanged(
                                  widget.ticket,
                                  'delivered',
                                ),
                              ),
                              const SizedBox(width: 6),
                              _buildStatusIconIndicator(
                                icon: Icons.cancel,
                                color: Colors.red,
                                isActive: widget.ticket.status == 'rejected',
                                tooltip: 'المرفوض',
                                onTap: () => widget.onStatusChanged(
                                  widget.ticket,
                                  'rejected',
                                ),
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
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(
                                      0xFFD4AF37,
                                    ).withValues(alpha: 0.4),
                                  ),
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
                              if (widget.ticket.agent != null &&
                                  widget.ticket.agent!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(
                                        alpha: 0.2,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.redAccent.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      widget.ticket.agent!,
                                      style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              Text(
                                '${widget.ticket.cost.toStringAsFixed(2)} ج.م',
                                style: const TextStyle(
                                  color: Color(0xFFD4AF37),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildInfoChip(
                                Icons.phone,
                                widget.ticket.customerPhone,
                              ),
                              _buildInfoChip(
                                Icons.phone_android,
                                widget.ticket.deviceModel,
                              ),
                              _buildInfoChip(
                                Icons.build_circle_outlined,
                                widget.ticket.problem,
                              ),
                              if (widget.ticket.technicianName != null &&
                                  widget.ticket.technicianName!.isNotEmpty)
                                widget.presentTechnicians.contains(
                                      widget.ticket.technicianName,
                                    )
                                    ? _buildPresentChip(
                                        widget.ticket.technicianName!,
                                      )
                                    : _buildInfoChip(
                                        Icons.person_outline,
                                        widget.ticket.technicianName!,
                                      ),
                              _buildInfoChip(
                                Icons.access_time,
                                DateFormat(
                                  'yyyy/MM/dd HH:mm',
                                ).format(widget.ticket.receivedDate),
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
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                          if (widget.ticket.deviceCondition.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'حالة الجهاز: ${widget.ticket.deviceCondition}',
                              style: TextStyle(
                                color: AppTheme.textMuted(context),
                                fontSize: 14,
                              ),
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
        border: Border.all(
          color: AppTheme.border(context).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textDisabled(context)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: AppTheme.textMuted(context), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildPresentChip(String techName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🟢', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            techName,
            style: const TextStyle(
              color: Colors.green,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
            decoration: BoxDecoration(
              color: Colors.green,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'حاضر',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
            : const Color(0xFF1A2A3A),
      ),
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
            child: Icon(icon, color: foregroundColor, size: 18),
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
            : const Color(0xFF1A2A3A),
      ),
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
              color: isActive
                  ? color.withValues(alpha: 0.15)
                  : Colors.transparent,
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

  const TicketDialog({
    super.key,
    this.ticket,
    required this.onSave,
    required this.technicians,
    required this.existingTickets,
    required this.spareParts,
  });

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
  late TextEditingController _agentController;
  late TextEditingController _deviceConditionController;
  late TextEditingController _technicianNameController;
  late TextEditingController _technicianPhoneController;
  late TextEditingController _partsCostController;
  late TextEditingController _commissionRateController;
  late TextEditingController _expectedDeliveryController;
  late String _status;
  late DateTime _receivedDate;
  late FocusNode _nameFocusNode;
  late FocusNode _phoneFocusNode;
  late FocusNode _deviceFocusNode;
  late FocusNode _technicianNameFocusNode;
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
    _phoneController = TextEditingController(
      text: widget.ticket?.customerPhone,
    );
    _deviceController = TextEditingController(text: widget.ticket?.deviceModel);
    _problemController = TextEditingController(text: widget.ticket?.problem);
    _costController = TextEditingController(
      text: widget.ticket?.cost.toString() ?? '0',
    );
    _notesController = TextEditingController(text: widget.ticket?.notes);
    _agentController = TextEditingController(text: widget.ticket?.agent);
    _deviceConditionController = TextEditingController(
      text: widget.ticket?.deviceCondition,
    );
    _technicianNameController = TextEditingController(
      text: widget.ticket?.technicianName,
    );
    _technicianPhoneController = TextEditingController(
      text: widget.ticket?.technicianPhone,
    );
    _partsCostController = TextEditingController(
      text: widget.ticket?.partsCost.toString() ?? '0',
    );
    _commissionRateController = TextEditingController(
      text: widget.ticket?.commissionRate.toString() ?? '50.0',
    );
    _expectedDeliveryController = TextEditingController(
      text: widget.ticket?.expectedDelivery,
    );
    _receivedDate = widget.ticket?.receivedDate ?? DateTime.now();
    _status = widget.ticket?.status ?? 'pending';
    filteredTechnicians = [];

    if (widget.ticket?.partsUsed != null &&
        widget.ticket!.partsUsed!.isNotEmpty) {
      try {
        _selectedParts = List<Map<String, dynamic>>.from(
          jsonDecode(widget.ticket!.partsUsed!),
        );
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

    _nameFocusNode = FocusNode();
    _phoneFocusNode = FocusNode();
    _deviceFocusNode = FocusNode();
    _technicianNameFocusNode = FocusNode();

    _nameFocusNode.addListener(() {
      if (!_nameFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              filteredCustomerNames = [];
            });
          }
        });
      }
    });

    _phoneFocusNode.addListener(() {
      if (!_phoneFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              filteredCustomerPhones = [];
            });
          }
        });
      }
    });

    _deviceFocusNode.addListener(() {
      if (!_deviceFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              filteredDeviceModels = [];
            });
          }
        });
      }
    });

    _technicianNameFocusNode.addListener(() {
      if (!_technicianNameFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              filteredTechnicians = [];
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _deviceController.dispose();
    _problemController.dispose();
    _costController.dispose();
    _notesController.dispose();
    _agentController.dispose();
    _deviceConditionController.dispose();
    _technicianNameController.dispose();
    _technicianPhoneController.dispose();
    _partsCostController.dispose();
    _commissionRateController.dispose();
    _expectedDeliveryController.dispose();
    _nameFocusNode.dispose();
    _phoneFocusNode.dispose();
    _deviceFocusNode.dispose();
    _technicianNameFocusNode.dispose();
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
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text(
                'إضافة قطعة غيار للإيصال',
                style: TextStyle(color: Color(0xFFD4AF37), fontSize: 20),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<SparePart>(
                    dropdownColor: AppTheme.cardBg(context),
                    style: TextStyle(
                      color: AppTheme.text(context),
                      fontSize: 16,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'اختر قطعة الغيار من المستودع',
                    ),
                    items: widget.spareParts.map((p) {
                      return DropdownMenuItem<SparePart>(
                        value: p,
                        child: Text(
                          '${p.name} (المتاح: ${p.quantity} - السعر: ${p.price} ج.م)',
                        ),
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
                    style: TextStyle(
                      color: AppTheme.text(context),
                      fontSize: 16,
                    ),
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
                  child: Text(
                    'إلغاء',
                    style: TextStyle(
                      color: AppTheme.textMuted(context),
                      fontSize: 16,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF1A2A3A),
                  ),
                  onPressed: () {
                    if (selectedInventoryPart != null) {
                      final existingIndex = _selectedParts.indexWhere(
                        (p) => p['partId'] == selectedInventoryPart!.id,
                      );
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
        final hasMatch = widget.existingTickets.any(
          (t) => t.customerName.trim() == name.trim(),
        );
        if (hasMatch) {
          final match = widget.existingTickets.firstWhere(
            (t) => t.customerName.trim() == name.trim(),
          );
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
        final hasMatch = widget.existingTickets.any(
          (t) => t.customerPhone.trim() == phone.trim(),
        );
        if (hasMatch) {
          final match = widget.existingTickets.firstWhere(
            (t) => t.customerPhone.trim() == phone.trim(),
          );
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
            .where(
              (t) =>
                  t.customerPhone.trim() == cleanPhone &&
                  (widget.ticket == null || t.id != widget.ticket!.id),
            )
            .toList();
        customerHistory.sort(
          (a, b) => b.receivedDate.compareTo(a.receivedDate),
        );
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
          color: badgeColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  void _filterTechnicians(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredTechnicians = [];
      } else {
        filteredTechnicians = widget.technicians
            .where(
              (tech) =>
                  tech['name']!.toLowerCase().contains(query.toLowerCase()),
            )
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
                    color: Color(0xFFD4AF37),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[900]!.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'معلومات العميل',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            focusNode: _nameFocusNode,
                            style: TextStyle(
                              color: AppTheme.text(context),
                              fontSize: 18,
                            ),
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
                                  filteredCustomerNames.first,
                                );
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
                                  color: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.3),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredCustomerNames.length,
                                itemBuilder: (context, index) {
                                  final name = filteredCustomerNames[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      name,
                                      style: TextStyle(
                                        color: AppTheme.text(context),
                                        fontSize: 18,
                                      ),
                                    ),
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
                            focusNode: _phoneFocusNode,
                            autofocus: true,
                            style: TextStyle(
                              color: AppTheme.text(context),
                              fontSize: 18,
                            ),
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
                                  filteredCustomerPhones.first,
                                );
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
                                  color: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.3),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredCustomerPhones.length,
                                itemBuilder: (context, index) {
                                  final phone = filteredCustomerPhones[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      phone,
                                      style: TextStyle(
                                        color: AppTheme.text(context),
                                        fontSize: 18,
                                      ),
                                    ),
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
                            focusNode: _deviceFocusNode,
                            style: TextStyle(
                              color: AppTheme.text(context),
                              fontSize: 18,
                            ),
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
                                  color: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.3),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredDeviceModels.length,
                                itemBuilder: (context, index) {
                                  final model = filteredDeviceModels[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      model,
                                      style: TextStyle(
                                        color: AppTheme.text(context),
                                        fontSize: 18,
                                      ),
                                    ),
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
                          color: AppTheme.text(context),
                          fontSize: 18,
                        ),
                        controller: _problemController,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'العطل *'),
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
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.history,
                              color: Color(0xFFD4AF37),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '📋 سجل هذا العميل مسبقاً (${customerHistory.length} أجهزة):',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37),
                              ),
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
                                          fontSize: 15,
                                        ),
                                      ),
                                      _buildHistoryStatusBadge(hist.status),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '🔧 العطل: ${hist.problem}',
                                    style: TextStyle(
                                      color: AppTheme.textMuted(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '📅 تاريخ الاستلام: ${DateFormat('yyyy/MM/dd').format(hist.receivedDate)}',
                                        style: TextStyle(
                                          color: AppTheme.textDisabled(context),
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '💰 التكلفة المبدئية: ${hist.cost.toStringAsFixed(2)} ج.م',
                                        style: const TextStyle(
                                          color: Color(0xFFD4AF37),
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'معلومات الفني',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                            focusNode: _technicianNameFocusNode,
                            style: TextStyle(
                              color: AppTheme.text(context),
                              fontSize: 18,
                            ),
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
                                  color: const Color(
                                    0xFFD4AF37,
                                  ).withValues(alpha: 0.3),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: filteredTechnicians.length,
                                itemBuilder: (context, index) {
                                  final tech = filteredTechnicians[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      tech['name']!,
                                      style: TextStyle(
                                        color: AppTheme.text(context),
                                        fontSize: 18,
                                      ),
                                    ),
                                    subtitle: Text(
                                      tech['phone']!,
                                      style: TextStyle(
                                        color: AppTheme.textMuted(context),
                                        fontSize: 14,
                                      ),
                                    ),
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
                          color: AppTheme.text(context),
                          fontSize: 18,
                        ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'قطع الغيار المستخدمة',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: const Color(0xFF1A2A3A),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text(
                              'إضافة قطعة',
                              style: TextStyle(fontSize: 13),
                            ),
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
                            color: AppTheme.textMuted(context),
                            fontSize: 14,
                          ),
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
                              title: Text(
                                item['name'],
                                style: TextStyle(
                                  color: AppTheme.text(context),
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Text(
                                'الكمية: ${item['quantity']} | السعر: ${item['price']} ج.م',
                                style: TextStyle(
                                  color: AppTheme.textMuted(context),
                                  fontSize: 14,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 20,
                                ),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'معلومات إضافية',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFD4AF37),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _status,
                              dropdownColor: AppTheme.cardBg(context),
                              style: TextStyle(
                                color: AppTheme.text(context),
                                fontSize: 18,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'الحالة',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'pending',
                                  child: Text('⏳ قيد الانتظار'),
                                ),
                                DropdownMenuItem(
                                  value: 'in_progress',
                                  child: Text('🔧 تحت الصيانة'),
                                ),
                                DropdownMenuItem(
                                  value: 'repaired',
                                  child: Text('✅ تم الإصلاح'),
                                ),
                                DropdownMenuItem(
                                  value: 'delivered',
                                  child: Text('📦 تم التسليم'),
                                ),
                                DropdownMenuItem(
                                  value: 'rejected',
                                  child: Text('❌ المرفوض'),
                                ),
                              ],
                              onChanged: (v) => setState(() => _status = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              style: TextStyle(
                                color: AppTheme.text(context),
                                fontSize: 18,
                              ),
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
                                color: AppTheme.text(context),
                                fontSize: 18,
                              ),
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
                                color: AppTheme.text(context),
                                fontSize: 18,
                              ),
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
                          color: AppTheme.text(context),
                          fontSize: 18,
                        ),
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'ملاحظات'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 18,
                        ),
                        controller: _agentController,
                        decoration: const InputDecoration(
                          labelText: 'الوكيل',
                          hintText: 'اسم الوكيل (اختياري)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 18,
                        ),
                        controller: _deviceConditionController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'حالة الجهاز',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        style: TextStyle(
                          color: AppTheme.text(context),
                          fontSize: 18,
                        ),
                        controller: _expectedDeliveryController,
                        decoration: const InputDecoration(
                          labelText:
                              'توقيت متوقع للتسليم (مثال: ساعتين، يوم، إلخ)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTint(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFD4AF37,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  color: Color(0xFFD4AF37),
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'توقيت استلام الجهاز:',
                                  style: TextStyle(
                                    color: AppTheme.textMuted(context),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  DateFormat(
                                    'yyyy-MM-dd',
                                  ).format(_receivedDate),
                                  style: const TextStyle(
                                    color: Color(0xFFD4AF37),
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('hh:mm a').format(_receivedDate),
                                  style: TextStyle(
                                    color: AppTheme.text(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Cairo',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTint(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFFD4AF37,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.confirmation_number,
                              color: Color(0xFFD4AF37),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'رقم الشكوى:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textMuted(context),
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DatabaseHelper.complaintNumber,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFD4AF37),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red[900]!.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'ثابت',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.red,
                                ),
                              ),
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
                              'agent': _agentController.text,
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
                              'commissionRate':
                                  double.tryParse(
                                    _commissionRateController.text,
                                  ) ??
                                  50.0,
                              'expectedDelivery': _expectedDeliveryController
                                  .text
                                  .trim(),
                            });
                            Navigator.pop(context);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD4AF37),
                          foregroundColor: const Color(0xFF1A2A3A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text(
                          'حفظ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
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
                        child: const Text(
                          'إلغاء',
                          style: TextStyle(fontSize: 20),
                        ),
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
    _qtyController = TextEditingController(
      text: widget.part?.quantity.toString() ?? '0',
    );
    _priceController = TextEditingController(
      text: widget.part?.price.toString() ?? '0',
    );
    _supplierController = TextEditingController(text: widget.part?.supplier);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        widget.part == null ? 'إضافة قطعة غيار' : 'تعديل قطعة غيار',
        style: const TextStyle(color: Color(0xFFD4AF37), fontSize: 22),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'اسم القطعة'),
          ),
          const SizedBox(height: 12),
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _qtyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'الكمية'),
          ),
          const SizedBox(height: 12),
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _priceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'السعر'),
          ),
          const SizedBox(height: 12),
          TextField(
            style: TextStyle(color: AppTheme.text(context), fontSize: 18),
            controller: _supplierController,
            decoration: const InputDecoration(labelText: 'المورد'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'إلغاء',
            style: TextStyle(color: AppTheme.textMuted(context), fontSize: 18),
          ),
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

// ==================== Branch Indicator Widget ====================

class _BranchIndicator extends StatelessWidget {
  final StoreBranch? branch;
  final VoidCallback onTap;

  const _BranchIndicator({required this.branch, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final branchName = branch?.name ?? 'الفرع الرئيسي';
    final branchCode = branch?.code ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue[50]?.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[200]!, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store, size: 14, color: Colors.blue[700]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                branchName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[800],
                  fontFamily: 'Cairo',
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (branchCode.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                '($branchCode)',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.blue[400],
                  fontFamily: 'Cairo',
                ),
              ),
            ],
            const SizedBox(width: 6),
            Icon(Icons.swap_horiz, size: 14, color: Colors.blue[400]),
          ],
        ),
      ),
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
  bool _serverAlive = false;
  bool _startingServer = false;

  String? _selectedLabel;
  String? _selectedReceipt;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    if (kIsWeb) {
      // On web: check local print server status first
      final status = await LocalPrintService.checkStatus();
      final alive = status.alive;
      if (alive) {
        final printers = await PrinterSettingsService.listAll();
        final config = await PrinterSettingsService.load();
        if (mounted) {
          setState(() {
            _printers = printers;
            _serverAlive = true;
            _selectedLabel = config.labelPrinterName;
            _selectedReceipt = config.receiptPrinterName;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _serverAlive = false;
            _printers = [];
            _loading = false;
          });
        }
      }
    } else {
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
  }

  Future<void> _save() async {
    await PrinterSettingsService.save(
      PrinterConfig(
        labelPrinterName: _selectedLabel,
        receiptPrinterName: _selectedReceipt,
      ),
    );
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

  // ─── Try to start the print server ──────────────────────────────────
  /// Copies the PowerShell command to clipboard and attempts to connect.
  Future<void> _tryStartServer() async {
    final scaffold = ScaffoldMessenger.of(context);

    // First re-check status in case it started since we last checked
    final status = await LocalPrintService.checkStatus();
    if (status.alive) {
      // Server is already running — just reload
      await _loadData();
      scaffold.showSnackBar(
        const SnackBar(
          content: Text('✅ خادم الطباعة يعمل بالفعل'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _startingServer = true);

    // Copy command to clipboard
    const cmd = 'powershell -ExecutionPolicy Bypass -File print_server.ps1';
    await Clipboard.setData(const ClipboardData(text: cmd));

    // Try a few more times with short delays (user may have just launched it)
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final retry = await LocalPrintService.checkStatus();
      if (retry.alive) {
        if (mounted) {
          scaffold.showSnackBar(
            const SnackBar(
              content: Text('✅ خادم الطباعة شغال! تم تحميل الطابعات'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          await _loadData();
        }
        setState(() => _startingServer = false);
        return;
      }
    }

    if (mounted) {
      scaffold.showSnackBar(
        const SnackBar(
          content: Text(
            '📋 تم نسخ الأمر! افتح PowerShell والصق الأمر لتشغيل الخادم',
          ),
          backgroundColor: Color(0xFFD4AF37),
          duration: Duration(seconds: 4),
        ),
      );
    }
    setState(() => _startingServer = false);
  }

  // ─── Web Printer Dialog (local print server) ───────────────────────

  Widget _buildWebDialog(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.cardBg(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 480,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header ──────────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _serverAlive
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFEF5350),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(
                          Icons.print_rounded,
                          color: Color(0xFFD4AF37),
                          size: 24,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _serverAlive
                                ? 'خادم الطباعة متصل'
                                : 'خادم الطباعة غير متصل',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD4AF37),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'تحديث',
                          icon: const Icon(
                            Icons.refresh,
                            color: Color(0xFFD4AF37),
                            size: 22,
                          ),
                          onPressed: _loadData,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (!_serverAlive) ...[
                      // ── Server not running ────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2A3A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(
                              0xFFEF5350,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFEF5350),
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'خادم الطباعة المحلي غير شغال',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFEF5350),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10),
                            Text(
                              'للطباعة المباشرة، شغّل ملف print_server.ps1 على جهاز الويندوز:',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                color: Color(0xFF8899AA),
                                height: 1.5,
                              ),
                            ),
                            SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.folder_open_rounded,
                                  color: Color(0xFFD4AF37),
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'webapp/lib/print_server.ps1',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: Color(0xFFD4AF37),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.terminal_rounded,
                                  color: Color(0xFFD4AF37),
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'powershell -ExecutionPolicy Bypass -File print_server.ps1',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 11,
                                      color: Color(0xFF8899AA),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Quick-launch buttons ──────────────────────────
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: _startingServer
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF1A2A3A),
                                  ),
                                )
                              : const Icon(Icons.copy_rounded, size: 20),
                          label: Text(
                            _startingServer
                                ? 'جاري الاتصال...'
                                : '📋 نسخ الأمر وتشغيل الخادم',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFD4AF37),
                            foregroundColor: const Color(0xFF1A2A3A),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _startingServer ? null : _tryStartServer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'حسناً',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 16,
                              color: Color(0xFF8899AA),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      // ── Server running → show printer selection ──────
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceTint(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.border(context)),
                        ),
                        child: Text(
                          'الطابعات المكتشفة: ${_printers.length}',
                          style: TextStyle(
                            color: AppTheme.textDisabled(context),
                            fontSize: 13,
                          ),
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
                            child: Text(
                              'إلغاء',
                              style: TextStyle(
                                color: AppTheme.textDisabled(context),
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.save_alt, size: 18),
                            label: const Text(
                              'حفظ الإعدادات',
                              style: TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4AF37),
                              foregroundColor: const Color(0xFF1A2A3A),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
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

  bool _isMissing(String? name) {
    if (name == null || name.isEmpty) return false;
    return !_printers.any((p) => p.name == name);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebDialog(context);
    }

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
                      Icon(
                        Icons.print_outlined,
                        color: Color(0xFFD4AF37),
                        size: 26,
                      ),
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
                    icon: Icon(
                      Icons.refresh,
                      color: AppTheme.textMuted(context),
                      size: 22,
                    ),
                    onPressed: _loading ? null : _loadData,
                  ),
                ],
              ),
              const Divider(
                color: Color(0xFFD4AF37),
                thickness: 0.5,
                height: 24,
              ),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Column(
                      children: [
                        const CircularProgressIndicator(
                          color: Color(0xFFD4AF37),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'جارٍ البحث عن الطابعات...',
                          style: TextStyle(
                            color: AppTheme.textMuted(context),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceTint(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border(context)),
                  ),
                  child: Text(
                    'الطابعات المكتشفة: ${_printers.length}',
                    style: TextStyle(
                      color: AppTheme.textDisabled(context),
                      fontSize: 13,
                    ),
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
                      child: Text(
                        'إلغاء',
                        style: TextStyle(
                          color: AppTheme.textDisabled(context),
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.save_alt, size: 18),
                      label: const Text(
                        'حفظ الإعدادات',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37),
                        foregroundColor: const Color(0xFF1A2A3A),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
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
        Text(
          label,
          style: TextStyle(
            color: AppTheme.textMuted(context),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceTint(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selectedValue,
              dropdownColor: AppTheme.cardBg(context),
              hint: Text(
                hint,
                style: TextStyle(
                  color: AppTheme.textDisabled(context),
                  fontSize: 14,
                ),
              ),
              style: TextStyle(color: AppTheme.text(context), fontSize: 15),
              iconEnabledColor: const Color(0xFFD4AF37),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(
                    '— لا شيء —',
                    style: TextStyle(
                      color: AppTheme.textDisabled(context),
                      fontSize: 14,
                    ),
                  ),
                ),
                ...names.map((name) {
                  final printer = _printers
                      .where((p) => p.name == name)
                      .firstOrNull;
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
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (!online)
                          const Text(
                            ' (offline)',
                            style: TextStyle(color: Colors.red, fontSize: 11),
                          ),
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
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Colors.orange,
          ),
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

// ═══════════════════════════════════════════════════════════════════════════════
//  WhatsApp Settings Dialog
// ═══════════════════════════════════════════════════════════════════════════════

class _WhatsAppSettingsDialog extends StatefulWidget {
  @override
  State<_WhatsAppSettingsDialog> createState() =>
      _WhatsAppSettingsDialogState();
}

class _WhatsAppSettingsDialogState extends State<_WhatsAppSettingsDialog> {
  final _tokenController = TextEditingController();
  final _phoneNumberIdController = TextEditingController();
  final _businessAccountIdController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _phoneNumberIdController.dispose();
    _businessAccountIdController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    final config = await WhatsAppService.loadConfig();
    if (mounted) {
      setState(() {
        _tokenController.text = config.token;
        _phoneNumberIdController.text = config.phoneNumberId;
        _businessAccountIdController.text = config.businessAccountId;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await WhatsAppService.saveConfig(
      WhatsAppConfig(
        token: _tokenController.text.trim(),
        phoneNumberId: _phoneNumberIdController.text.trim(),
        businessAccountId: _businessAccountIdController.text.trim(),
      ),
    );
    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم حفظ إعدادات واتساب بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    // Quick validation
    if (_tokenController.text.trim().isEmpty ||
        _phoneNumberIdController.text.trim().isEmpty) {
      setState(() {
        _isTesting = false;
        _testResult = '⚠️ يرجى إدخال التوكن ورقم الهاتف أولاً';
      });
      return;
    }

    // Save first, then test
    await WhatsAppService.saveConfig(
      WhatsAppConfig(
        token: _tokenController.text.trim(),
        phoneNumberId: _phoneNumberIdController.text.trim(),
        businessAccountId: _businessAccountIdController.text.trim(),
      ),
    );

    final result = await WhatsAppService.testConnection();
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = result
            ? '✅ تم الاتصال بنجاح! الإعدادات صحيحة.'
            : '❌ فشل الاتصال. تحقق من التوكن ورقم الهاتف.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final cardBg = AppTheme.cardBg(context);
    final primaryGold = const Color(0xFFD4AF37);
    final whatsappGreen = const Color(0xFF25D366);

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.chat_rounded, color: whatsappGreen, size: 26),
                      const SizedBox(width: 10),
                      Text(
                        'إعدادات واتساب API',
                        style: TextStyle(
                          color: primaryGold,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.info_outline, color: textMuted, size: 22),
                    onPressed: _showHelpDialog,
                  ),
                ],
              ),
              const Divider(
                color: Color(0xFFD4AF37),
                thickness: 0.5,
                height: 24,
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                  ),
                )
              else ...[
                // Instructions
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: whatsappGreen.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: whatsappGreen.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_rounded, color: whatsappGreen, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ستحتاج إلى حساب واتساب Business ومنصة Meta Developers.',
                          style: TextStyle(
                            color: textMuted,
                            fontSize: 12,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Token Field
                TextField(
                  controller: _tokenController,
                  style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                  obscureText: true,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: '🔑 Access Token',
                    hintText: 'أدخل توكن واجهة واتساب API',
                    hintStyle: TextStyle(color: textMuted, fontSize: 13),
                    labelStyle: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                const SizedBox(height: 16),

                // Phone Number ID
                TextField(
                  controller: _phoneNumberIdController,
                  style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: '📞 Phone Number ID',
                    hintText: 'أدخل رقم تعريف الهاتف من Meta',
                    hintStyle: TextStyle(color: textMuted, fontSize: 13),
                    labelStyle: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                const SizedBox(height: 16),

                // Business Account ID (optional)
                TextField(
                  controller: _businessAccountIdController,
                  style: TextStyle(color: textColor, fontFamily: 'Cairo'),
                  decoration: InputDecoration(
                    labelText: '🏢 WhatsApp Business Account ID (اختياري)',
                    hintText: 'معرف حساب الأعمال (WABA ID)',
                    hintStyle: TextStyle(color: textMuted, fontSize: 13),
                    labelStyle: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),

                // Test result
                if (_testResult != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _testResult!.contains('✅')
                          ? Colors.green.withValues(alpha: 0.1)
                          : _testResult!.contains('❌')
                          ? Colors.red.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testResult!.contains('✅')
                              ? Icons.check_circle
                              : _testResult!.contains('❌')
                              ? Icons.error
                              : Icons.warning,
                          color: _testResult!.contains('✅')
                              ? Colors.green
                              : _testResult!.contains('❌')
                              ? Colors.red
                              : Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testResult!,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Test connection button
                    OutlinedButton.icon(
                      icon: _isTesting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFD4AF37),
                              ),
                            )
                          : const Icon(Icons.wifi_find_rounded, size: 18),
                      label: Text(
                        _isTesting ? 'جارٍ الاختبار...' : 'اختبار الاتصال',
                        style: const TextStyle(fontSize: 14),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: primaryGold,
                        side: BorderSide(
                          color: primaryGold.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                      onPressed: _isTesting ? null : _testConnection,
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'إلغاء',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 16,
                              fontFamily: 'Cairo',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF1A2A3A),
                                  ),
                                )
                              : const Icon(Icons.save_alt, size: 18),
                          label: Text(
                            _isSaving ? 'جارٍ الحفظ...' : 'حفظ الإعدادات',
                            style: const TextStyle(
                              fontSize: 16,
                              fontFamily: 'Cairo',
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGold,
                            foregroundColor: const Color(0xFF1A2A3A),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onPressed: _isSaving ? null : _save,
                        ),
                      ],
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

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'كيفية إعداد واتساب API',
          style: TextStyle(
            color: Color(0xFFD4AF37),
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        content: SingleChildScrollView(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _helpStep(
                  '1',
                  'تسجيل الدخول',
                  'في Meta Developers (https://developers.facebook.com)',
                ),
                _helpStep('2', 'إنشاء تطبيق', 'اختر "WhatsApp" ثم "Business"'),
                _helpStep('3', 'إعداد الواتساب', 'اربط رقم هاتف عملك'),
                _helpStep(
                  '4',
                  'الحصول على التوكن',
                  'من قسم "API Setup" اختر "Access Token"',
                ),
                _helpStep(
                  '5',
                  'معرف الهاتف',
                  'Phone Number ID موجود في نفس الصفحة',
                ),
                _helpStep(
                  '6',
                  'حفظ الإعدادات',
                  'ضع التوكن والمعرف في الحقول أعلاه',
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ملاحظة: الإصدار المجاني من واتساب API يسمح بإرسال الرسائل للعملاء الذين تواصلوا معك أولاً (24-hour window). للإرسال المباشر، ستحتاج إلى قالب معتمد.',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'فهمت ✅',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _helpStep(String number, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFFD4AF37),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF1A2A3A),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 🔔 Beautiful animated attendance notification overlay
class _AttendanceNotificationWidget extends StatefulWidget {
  final String techName;
  final String action;
  final IconData icon;
  final Color iconColor;
  final Gradient bgGradient;
  final VoidCallback onDismiss;

  const _AttendanceNotificationWidget({
    required this.techName,
    required this.action,
    required this.icon,
    required this.iconColor,
    required this.bgGradient,
    required this.onDismiss,
  });

  @override
  State<_AttendanceNotificationWidget> createState() =>
      _AttendanceNotificationWidgetState();
}

class _AttendanceNotificationWidgetState
    extends State<_AttendanceNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = widget.action == 'تسجيل حضور';
    final accentColor = widget.iconColor;

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
          child: Container(
            color: Colors.black.withValues(alpha: 0.45),
            child: Center(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 500,
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.3),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pulsing Icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                            border: Border.all(color: accentColor, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.4),
                                blurRadius: 25,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Status title
                        Text(
                          isCheckIn
                              ? "تسجيل حضور فني جديد 👨‍🔧"
                              : "تسجيل انصراف فني 🚪",
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // Message details
                        Text(
                          isCheckIn
                              ? "مرحباً بك! قام الفني"
                              : "عمل موفق! قام الفني",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontFamily: 'Cairo',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.techName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Cairo',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isCheckIn
                              ? "بتسجيل حضوره بنجاح اليوم."
                              : "بتسجيل انصرافه بنجاح اليوم.",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontFamily: 'Cairo',
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 36),

                        // Dismiss button
                        ElevatedButton.icon(
                          onPressed: widget.onDismiss,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text(
                            "حسناً، إغلاق",
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
