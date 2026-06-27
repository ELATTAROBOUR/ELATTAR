// lib/esc_pos_print_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// ESC/POS Print Service - communicates with local print_server.ps1 via HTTP.
// Clean, simple, no browser API dependencies.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Cached server status so UI can check isConnected synchronously.
Map<String, dynamic> _cachedStatus = {};
DateTime _lastStatusFetch = DateTime(2000);

// ═════════════════════════════════════════════════════════════════════════════
// ESC/POS Command Builder
// ═════════════════════════════════════════════════════════════════════════════

class EscPosBuilder {
  final List<int> _bytes = [];

  void init() {
    _bytes.addAll([0x1B, 0x40]);
  }

  void align(int n) {
    _bytes.addAll([0x1B, 0x61, n.clamp(0, 2)]);
  }

  void charSize(int w, int h) {
    _bytes.addAll([
      0x1D,
      0x21,
      ((w.clamp(1, 8) - 1) << 4) | (h.clamp(1, 8) - 1),
    ]);
  }

  void bold(bool on) {
    _bytes.addAll([0x1B, 0x45, on ? 1 : 0]);
  }

  void text(String txt) {
    _bytes.addAll(utf8.encode(txt));
  }

  void textLn(String txt) {
    text(txt);
    _bytes.add(0x0A);
  }

  void feed(int n) {
    _bytes.addAll([0x1B, 0x64, n]);
  }

  void barcode128(String data, {int height = 100, int width = 2}) {
    final bytes = utf8.encode(data);
    _bytes.addAll([
      0x1D,
      0x68,
      height,
      0x1D,
      0x77,
      width.clamp(2, 6),
      0x1D,
      0x6B,
      0x49,
    ]);
    _bytes.addAll(bytes);
    _bytes.addAll([0x00, 0x0A]);
  }

  void qrCode(String data, {int size = 4}) {
    final bytes = utf8.encode(data);
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
    _bytes.addAll([
      0x1D,
      0x28,
      0x6B,
      0x03,
      0x00,
      0x31,
      0x43,
      size.clamp(1, 16),
    ]);
    final pl = bytes.length + 3;
    _bytes.addAll([0x1D, 0x28, 0x6B, pl % 256, pl >> 8, 0x31, 0x50, 0x30]);
    _bytes.addAll(bytes);
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    _bytes.add(0x0A);
  }

  void cut() {
    _bytes.addAll([0x1D, 0x56, 0x00]);
  }

  void hr({String char = "-", int width = 48}) {
    textLn(char * width);
  }

  Uint8List build() => Uint8List.fromList(_bytes);
}

// ═════════════════════════════════════════════════════════════════════════════
// ESC/POS Print Service - communicates with local print_server.ps1 via HTTP.
// The server manages USB/serial connections to the thermal printers.
// ═════════════════════════════════════════════════════════════════════════════

class EscPosPrintService {
  static const String labelPrinterType = "label";
  static const String receiptPrinterType = "receipt";
  static const int serverPort = 19283;
  static String get baseUrl => "http://localhost:$serverPort";

  /// Check if the local print server is running.
  static Future<bool> isServerAvailable() async {
    try {
      final resp = await http
          .get(Uri.parse("$baseUrl/status"))
          .timeout(const Duration(seconds: 2));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetch fresh status from server and update cache.
  static Future<Map<String, dynamic>> refreshStatus() async {
    try {
      final resp = await http
          .get(Uri.parse("$baseUrl/status"))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        _cachedStatus = jsonDecode(resp.body) as Map<String, dynamic>;
        _lastStatusFetch = DateTime.now();
      }
    } catch (_) {
      _cachedStatus = {"status": "unreachable"};
    }
    return _cachedStatus;
  }

  /// Get cached server status.
  static Map<String, dynamic> getServerStatus() => _cachedStatus;

  /// Check if a printer type is connected (uses cached status).
  /// Call [refreshStatus] first to get fresh data.
  static bool isConnected(String type) {
    final key = type == labelPrinterType ? "labelPrinter" : "receiptPrinter";
    final printer = _cachedStatus[key] as Map<String, dynamic>?;
    return printer?["connected"] == true;
  }

  /// Connect (refreshes server status; server auto-connects).
  static Future<bool> connectPrinter({required String type}) async {
    await refreshStatus();
    return isConnected(type);
  }

  /// Disconnect (no-op; server manages connections).
  static Future<void> disconnectPrinter(String type) async {}

  /// Send raw ESC/POS data to the local print server.
  static Future<bool> _sendData(String type, Uint8List data) async {
    try {
      final endpoint = type == labelPrinterType
          ? "/print/label"
          : "/print/receipt";
      final body = jsonEncode({"data": base64Encode(data)});
      final resp = await http
          .post(
            Uri.parse("$baseUrl$endpoint"),
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200) {
        final result = jsonDecode(resp.body) as Map<String, dynamic>;
        return result["success"] == true;
      }
      return false;
    } catch (e) {
      debugPrint("EscPosPrintService._sendData error: $e");
      return false;
    }
  }

  /// Print a label to XP-370B via the local server.
  static Future<bool> printLabel(Ticket ticket) async {
    try {
      final data = _buildLabelEscPos(ticket);
      return await _sendData(labelPrinterType, data);
    } catch (e) {
      debugPrint("EscPosPrintService.printLabel error: $e");
      return false;
    }
  }

  /// Print a receipt to XP-80C via the local server.
  static Future<bool> printReceipt(Ticket ticket, {int copies = 1}) async {
    try {
      for (int i = 0; i < copies; i++) {
        final data = _buildReceiptEscPos(ticket, i + 1, copies);
        final ok = await _sendData(receiptPrinterType, data);
        if (!ok) return false;
      }
      return true;
    } catch (e) {
      debugPrint("EscPosPrintService.printReceipt error: $e");
      return false;
    }
  }

  // ─── ESC/POS Layouts ──────────────────────────────────────────────────

  static Uint8List _buildLabelEscPos(Ticket t) {
    final b = EscPosBuilder();
    b.init();
    b.align(1);
    b.charSize(2, 2);
    b.textLn("العطار استور");
    b.charSize(1, 1);
    b.textLn("================");
    b.bold(true);
    b.textLn("العميل: ${t.customerName ?? "---"}");
    b.bold(false);
    if (t.customerPhone != null && t.customerPhone!.isNotEmpty) {
      b.textLn("هاتف: ${t.customerPhone}");
    }
    b.textLn("");
    b.bold(true);
    b.textLn("الجهاز: ${t.deviceModel}");
    b.bold(false);
    if (t.problem.isNotEmpty) b.textLn("العطل: ${t.problem}");
    b.textLn("");
    final ds = DateFormat("yyyy-MM-dd").format(t.receivedDate);
    b.textLn("التاريخ: $ds");
    b.textLn("رقم التذكرة: ${t.id ?? "---"}");
    if (t.id != null) {
      b.feed(1);
      b.align(1);
      b.barcode128(t.id.toString());
    }
    b.align(1);
    b.textLn("");
    b.textLn("شكراً لثقتكم");
    b.textLn("Developed By Eng: BELALZAGHL0L");
    b.feed(3);
    b.cut();
    return b.build();
  }

  static Uint8List _buildReceiptEscPos(Ticket t, int copyIdx, int total) {
    final b = EscPosBuilder();
    b.init();
    b.align(1);
    b.charSize(2, 2);
    b.bold(true);
    b.textLn("العطار استور");
    b.charSize(1, 1);
    b.bold(false);
    b.textLn("نظام صيانة الموبايلات");
    b.hr();
    b.align(0);
    final ds = DateFormat("yyyy-MM-dd HH:mm").format(t.receivedDate);
    b.textLn("التاريخ: $ds");
    b.textLn("رقم التذكرة: ${t.id ?? "---"}");
    b.textLn("");
    b.bold(true);
    b.textLn("بيانات العميل:");
    b.bold(false);
    b.textLn("الاسم: ${t.customerName ?? "---"}");
    if (t.customerPhone != null && t.customerPhone!.isNotEmpty) {
      b.textLn("الهاتف: ${t.customerPhone}");
    }
    b.textLn("");
    b.bold(true);
    b.textLn("بيانات الجهاز:");
    b.bold(false);
    b.textLn("الموديل: ${t.deviceModel ?? "---"}");
    if (t.deviceCondition.isNotEmpty) b.textLn("الحالة: ${t.deviceCondition}");
    b.textLn("");
    b.bold(true);
    b.textLn("العطل:");
    b.bold(false);
    b.textLn(t.problem.isEmpty ? "---" : t.problem);
    b.textLn("");
    b.hr();
    b.bold(true);
    b.charSize(2, 2);
    b.textLn("الإجمالي: ${t.cost.toStringAsFixed(2)} ج.م");
    b.charSize(1, 1);
    b.bold(false);
    b.hr();
    if (t.paymentMethod != null && t.paymentMethod!.isNotEmpty) {
      b.textLn("طريقة الدفع: ${t.paymentMethod}");
    }
    if (t.technicianName != null && t.technicianName!.isNotEmpty) {
      b.textLn("الفني: ${t.technicianName}");
    }
    b.align(1);
    b.hr();
    b.textLn("");
    b.textLn("شكراً لثقتكم في العطار استور");
    if (t.id != null) {
      b.align(1);
      b.qrCode("ELATTAR:${t.id}:${t.cost.toStringAsFixed(2)}");
    }
    if (total > 1) {
      b.align(1);
      b.textLn("(نسخة $copyIdx من $total)");
    }
    b.textLn("");
    b.textLn("Developed By Eng: BELALZAGHL0L");
    b.feed(4);
    b.cut();
    return b.build();
  }
}
