/// Web database factory initialization (using SQLite WASM)
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

void setupDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}
