// lib/local_print_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Local Print Service — communicates with print_server.ps1 on the Windows
// machine to enumerate printers and send PDF documents for direct printing.
//
// The PowerShell server runs on http://localhost:19283 and handles:
//   GET  /status          → server health
//   GET  /list-printers   → installed printers
//   POST /print           → print a PDF to a named printer
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// ═════════════════════════════════════════════════════════════════════════════
// Top-level types
// ═════════════════════════════════════════════════════════════════════════════

/// Represents the print server's health status.
class ServerStatus {
  final bool alive;
  final Map<String, dynamic> raw;

  ServerStatus({required this.alive, required this.raw});

  factory ServerStatus.fromJson(Map<String, dynamic> json) =>
      ServerStatus(alive: json['status'] == 'ok', raw: json);

  factory ServerStatus.unreachable() =>
      ServerStatus(alive: false, raw: {'status': 'unreachable'});
}

/// Represents a printer reported by the server.
class PrinterInfo {
  final String name;
  final bool isDefault;
  final String status;

  PrinterInfo({
    required this.name,
    required this.isDefault,
    required this.status,
  });

  factory PrinterInfo.fromJson(Map<String, dynamic> json) => PrinterInfo(
    name: json['name'] as String,
    isDefault: json['isDefault'] as bool? ?? false,
    status: json['status'] as String? ?? 'idle',
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// Client
// ═════════════════════════════════════════════════════════════════════════════

/// Lightweight client for the local ELATTAR Print Server.
class LocalPrintService {
  static const String _baseUrl = 'http://localhost:19283';
  static const Duration _timeout = Duration(seconds: 10);

  /// Check if the local print server is running.
  static Future<ServerStatus> checkStatus() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/status'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        return ServerStatus.fromJson(json);
      }
      return ServerStatus.unreachable();
    } catch (_) {
      return ServerStatus.unreachable();
    }
  }

  // ─── List printers ─────────────────────────────────────────────────────────

  /// Fetch all installed printers from the Windows machine.
  /// Returns an empty list if the server is unreachable.
  static Future<List<PrinterInfo>> listPrinters() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/list-printers'))
          .timeout(_timeout);
      if (res.statusCode == 200) {
        final List<dynamic> list = jsonDecode(res.body) as List<dynamic>;
        return list
            .map((e) => PrinterInfo.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ─── Print PDF ─────────────────────────────────────────────────────────────

  /// Send a PDF document to the specified printer on the Windows machine.
  ///
  /// Returns `true` if the server accepted the job.
  /// Throws a descriptive [Exception] on failure.
  static Future<bool> printPdf({
    required Uint8List pdfBytes,
    required String printerName,
  }) async {
    final uri = Uri.parse('$_baseUrl/print');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['printer'] = printerName
        ..files.add(
          http.MultipartFile.fromBytes('file', pdfBytes, filename: 'print.pdf'),
        );

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['success'] == true) {
          return true;
        }
        throw Exception(json['error'] ?? 'فشلت الطباعة');
      }

      // Try to parse error
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(json['error'] ?? 'خطأ في خادم الطباعة');
      } catch (_) {
        throw Exception('خطأ في خادم الطباعة (${response.statusCode})');
      }
    } on Exception catch (e) {
      if (e is Exception) rethrow;
      throw Exception('تعذر الاتصال بخادم الطباعة المحلي');
    }
  }
}
