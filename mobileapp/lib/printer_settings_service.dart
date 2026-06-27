import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

class PrinterConfig {
  final String? labelPrinterName;
  final String? receiptPrinterName;

  const PrinterConfig({
    this.labelPrinterName,
    this.receiptPrinterName,
  });

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
  }) =>
      PrinterConfig(
        labelPrinterName: labelPrinterName ?? this.labelPrinterName,
        receiptPrinterName: receiptPrinterName ?? this.receiptPrinterName,
      );
}

class PrinterSettingsService {
  static const _fileName = 'printer_settings.json';

  static Future<File> _settingsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<PrinterConfig> load() async {
    try {
      final file = await _settingsFile();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        return PrinterConfig.fromJson(json);
      }
    } catch (e) {
      debugPrint('PrinterSettingsService.load error: $e');
    }
    return const PrinterConfig();
  }

  static Future<void> save(PrinterConfig config) async {
    try {
      final file = await _settingsFile();
      await file.writeAsString(jsonEncode(config.toJson()));
      debugPrint(
          'PrinterSettings saved: label="${config.labelPrinterName}" receipt="${config.receiptPrinterName}"');
    } catch (e) {
      debugPrint('PrinterSettingsService.save error: $e');
    }
  }

  static Future<List<Printer>> listAll() async {
    final printers = await Printing.listPrinters();
    for (final p in printers) {
      debugPrint('Detected Printer: ${p.name} | available=${p.isAvailable}');
    }
    final sorted = List<Printer>.from(printers)
      ..sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }

  static Future<Printer> resolve(String? savedName, String role) async {
    if (savedName == null || savedName.trim().isEmpty) {
      throw Exception(
          'لم يتم تحديد $role — يرجى الذهاب إلى إعدادات الطابعة واختيار الطابعة المناسبة');
    }

    final printers = await Printing.listPrinters();
    Printer? found;
    for (final p in printers) {
      if (p.name == savedName) {
        found = p;
        break;
      }
    }

    if (found == null) {
      throw Exception(
          '$role غير موجودة: "$savedName"\nيرجى فتح إعدادات الطابعة وإعادة الاختيار');
    }

    if (!found.isAvailable) {
      throw Exception(
          '$role غير متصلة (Offline): "${found.name}"\nتأكد من تشغيل الطابعة وإعادة المحاولة');
    }

    debugPrint('Resolved $role → "${found.name}"');
    return found;
  }
}
