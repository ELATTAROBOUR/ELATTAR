/// Database factory initialization for all platforms.
/// Uses kIsWeb to determine the appropriate SQLite backend.
import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Sets up the platform-appropriate database factory.
void setupDatabaseFactory() {
  if (kIsWeb) {
    // Web: use SQLite WASM
    databaseFactory = databaseFactoryFfiWeb;
  } else {
    // Native (desktop): use the FFI-based factory
    databaseFactory = databaseFactoryFfiWeb;
  }
}
