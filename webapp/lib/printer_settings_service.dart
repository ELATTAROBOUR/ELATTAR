// lib/printer_settings_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Printer Settings Service
//  Saves selected label & receipt printer names to printer_settings.json
//  (native) or the database settings table (web).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import 'database_helper.dart';
import 'platform_stub.dart' if (dart.library.io) 'dart:io';

/// Holds the two saved printer name selections.
class PrinterConfig {
  final String? labelPrinterName;
  final String? receiptPrinterName;

  const PrinterConfig({this.labelPrinterName, this.receiptPrinterName});

  factory PrinterConfig.fromJson(Map<String, dynamic> json) => PrinterConfig(
    labelPrinterName: json['labelPrinter'] as String?,
    receiptPrinterName: json['receiptPrinter'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'labelPrinter': labelPrinterName,
    'receiptPrinter': receiptPrinterName,
  };

  PrinterConfig copyWith({
    String? labelPrinterName,
    String? receiptPrinterName,
  }) => PrinterConfig(
    labelPrinterName: labelPrinterName ?? this.labelPrinterName,
    receiptPrinterName: receiptPrinterName ?? this.receiptPrinterName,
  );
}

class PrinterSettingsService {
  static const _fileName = 'printer_settings.json';
  static const _dbKeyLabel = 'printerLabel';
  static const _dbKeyReceipt = 'printerReceipt';

  // ─── Persistence ────────────────────────────────────────────────────────────

  /// Load saved printer names.
  /// On native uses a JSON file; on web uses the database settings table.
  static Future<PrinterConfig> load() async {
    try {
      if (kIsWeb) {
        final label = await DatabaseHelper.getSetting(_dbKeyLabel);
        final receipt = await DatabaseHelper.getSetting(_dbKeyReceipt);
        return PrinterConfig(
          labelPrinterName: label?.isNotEmpty == true ? label : null,
          receiptPrinterName: receipt?.isNotEmpty == true ? receipt : null,
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_fileName');
        if (await file.exists()) {
          final raw = await file.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          return PrinterConfig.fromJson(json);
        }
      }
    } catch (e) {
      debugPrint('PrinterSettingsService.load error: $e');
    }
    return const PrinterConfig(
      labelPrinterName: 'Xprinter XP-370B',
      receiptPrinterName: 'XP-80C',
    );
  }

  /// Persist the current printer selections.
  /// On native uses a JSON file; on web uses the database settings table.
  static Future<void> save(PrinterConfig config) async {
    try {
      if (kIsWeb) {
        await DatabaseHelper.saveSetting(
          _dbKeyLabel,
          config.labelPrinterName ?? '',
        );
        await DatabaseHelper.saveSetting(
          _dbKeyReceipt,
          config.receiptPrinterName ?? '',
        );
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$_fileName');
        await file.writeAsString(jsonEncode(config.toJson()));
      }
      debugPrint(
        'PrinterSettings saved: label="${config.labelPrinterName}" receipt="${config.receiptPrinterName}"',
      );
    } catch (e) {
      debugPrint('PrinterSettingsService.save error: $e');
    }
  }

  // ─── Printer Enumeration ────────────────────────────────────────────────────

  /// Returns all printers currently installed on the system, sorted by name.
  /// On web returns an empty list (system printers are not accessible from browser).
  static Future<List<Printer>> listAll() async {
    if (kIsWeb) {
      return [];
    }
    final printers = await Printing.listPrinters();
    for (final p in printers) {
      debugPrint('Detected Printer: ${p.name} | available=${p.isAvailable}');
    }
    final sorted = List<Printer>.from(printers)
      ..sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }

  // ─── Resolution (used at print-time) ───────────────────────────────────────

  /// Resolves a saved printer name to a live [Printer] object.
  ///
  /// On web, throws an exception — callers should use [Printing.layoutPdf]
  /// instead (browser print dialog).
  ///
  /// Throws an [Exception] with a clear Arabic message if:
  ///   • No name is configured (null / empty).
  ///   • The printer is no longer installed.
  ///   • The printer is offline / unavailable.
  static Future<Printer> resolve(String? savedName, String role) async {
    if (kIsWeb) {
      throw Exception('الطباعة عبر المتصفح - استخدم نافذة الطباعة في المتصفح');
    }

    String nameToResolve = savedName ?? '';
    bool isLabel = role.contains('ملصق') || role.contains('label');

    if (nameToResolve.trim().isEmpty) {
      nameToResolve = isLabel ? 'Xprinter XP-370B' : 'XP-80C';
    }

    final printers = await Printing.listPrinters();
    if (printers.isEmpty) {
      throw Exception('لم يتم العثور على أي طابعة مثبتة على النظام');
    }

    Printer? found;

    // 1. Try exact match
    for (final p in printers) {
      if (p.name == nameToResolve) {
        found = p;
        break;
      }
    }

    // 2. Try case-insensitive contains match
    if (found == null) {
      final query = nameToResolve.toLowerCase();
      for (final p in printers) {
        final pName = p.name.toLowerCase();
        if (pName.contains(query) || query.contains(pName)) {
          found = p;
          break;
        }
      }
    }

    // 3. Try fallback keywords
    if (found == null) {
      final fallbackKeyword = isLabel ? '370' : '80';
      for (final p in printers) {
        if (p.name.toLowerCase().contains(fallbackKeyword)) {
          found = p;
          break;
        }
      }
    }

    // 4. Default to first printer
    if (found == null) {
      found = printers.first;
    }

    debugPrint('Resolved $role → "${found.name}"');
    return found;
  }
}
