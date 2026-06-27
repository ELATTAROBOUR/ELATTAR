import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'views/keygen_view.dart';

/// Standalone Keygen App widget.
/// Used by [runKeygenApp] to start the app independently,
/// or can be imported and used elsewhere.
class KeygenApp extends StatelessWidget {
  const KeygenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KEY - توليد مفاتيح التفعيل',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFFD4AF37),
        scaffoldBackgroundColor: const Color(0xFF121B26),
        fontFamily: 'Cairo',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A2A3A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1A2A3A),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFD4AF37),
          secondary: Colors.amberAccent,
          surface: const Color(0xFF1A2A3A),
        ),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'EG'), Locale('en', 'US')],
      locale: const Locale('ar', 'EG'),
      home: const KeygenView(),
    );
  }
}

/// Call this function instead of [main] to run the keygen app independently.
/// Used by [entry_keygen.dart] as the build entry point.
void runKeygenApp() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KeygenApp());
}
