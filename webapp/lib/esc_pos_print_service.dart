// lib/esc_pos_print_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// ESC/POS Direct USB Printing Service for Web
// Uses Web Serial API (primary) + WebUSB API (fallback) via JavaScript bridge.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'models.dart';
import 'printer_settings_service.dart';
import 'database_helper.dart';

// Conditional import: use JS interop on web, stub on native
import 'esc_pos_interop_stub.dart'
    if (dart.library.js_interop) 'esc_pos_interop_web.dart';

// ═════════════════════════════════════════════════════════════════════════════
// ESC/POS Command Builder
// ═════════════════════════════════════════════════════════════════════════════

class EscPosBuilder {
  final List<int> _bytes = [];

  /// Initialize printer
  void init() {
    _bytes.addAll([0x1B, 0x40]); // ESC @
  }

  /// Set alignment: 0=left, 1=center, 2=right
  void align(int n) {
    _bytes.addAll([0x1B, 0x61, n.clamp(0, 2)]);
  }

  /// Set character size: width×height (1-8)
  void charSize(int width, int height) {
    final n = ((width.clamp(1, 8) - 1) << 4) | (height.clamp(1, 8) - 1);
    _bytes.addAll([0x1D, 0x21, n]);
  }

  /// Set bold mode on/off
  void bold(bool on) {
    _bytes.addAll([0x1B, 0x45, on ? 1 : 0]);
  }

  /// Print text (encoded as UTF-8)
  void text(String txt) {
    _bytes.addAll(utf8.encode(txt));
  }

  /// Print text with line feed
  void textLn(String txt) {
    text(txt);
    _bytes.add(0x0A); // LF
  }

  /// Line feed (n lines)
  void feed(int n) {
    _bytes.addAll([0x1B, 0x64, n]);
  }

  /// Print barcode (CODE128)
  void barcode128(String data, {int height = 100, int width = 2}) {
    final bytes = utf8.encode(data);
    _bytes.addAll([
      0x1D, 0x68, height, // Barcode height
      0x1D, 0x77, width.clamp(2, 6), // Barcode width
      0x1D, 0x6B, 0x49, // CODE128
    ]);
    _bytes.addAll(bytes);
    _bytes.addAll([0x00, 0x0A]); // NUL terminator + LF
  }

  /// Print QR code
  void qrCode(String data, {int size = 4}) {
    final bytes = utf8.encode(data);
    final len = bytes.length;

    // Set QR code model (model 2)
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);

    // Set QR code size
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size.clamp(1, 16)]);

    // Store QR code data
    final pl = len + 3;
    _bytes.addAll([0x1D, 0x28, 0x6B, pl % 256, pl >> 8, 0x31, 0x50, 0x30]);
    _bytes.addAll(bytes);

    // Print QR code
    _bytes.addAll([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    _bytes.add(0x0A); // LF
  }

  /// Full cut
  void cut() {
    _bytes.addAll([0x1D, 0x56, 0x00]); // GS V 0
  }

  /// Draw horizontal line
  void hr({String char = '-', int width = 48}) {
    textLn(char * width);
  }

  /// Get the final byte array
  Uint8List build() => Uint8List.fromList(_bytes);
}

// ═════════════════════════════════════════════════════════════════════════════
// ESC/POS Print Service
// ═════════════════════════════════════════════════════════════════════════════

class EscPosPrintService {
  static const String labelPrinterType = 'label';
  static const String receiptPrinterType = 'receipt';

  // ═════════════════════════════════════════════════════════════════════════
  // Web Serial API (Primary)
  // ═════════════════════════════════════════════════════════════════════════

  /// Check if Web Serial API is available in this browser.
  static bool isWebSerialAvailable() {
    if (!kIsWeb) return false;
    return jsCheckWebSerialAvailable();
  }

  /// Connect to a printer via Web Serial API.
  static Future<bool> connectPrinterSerial(String type) async {
    if (!kIsWeb) return false;
    try {
      final vid = await _getSavedVendorId(type);
      final pid = await _getSavedProductId(type);
      final jsonStr = await jsPrintConnect(type, vendorId: vid, productId: pid);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (result['success'] == true) {
        final newVid = result['vendorId'] as int?;
        final newPid = result['productId'] as int?;
        debugPrint('Serial printer connected ($type): vendor=$newVid, product=$newPid');
        if (newVid != null) await _saveVendorId(type, newVid, newPid);
        return true;
      }
      if (result['cancelled'] == true) {
        debugPrint('User cancelled serial port selection ($type)');
      } else {
        debugPrint('Serial connection failed ($type): ${result['error']}');
      }
      return false;
    } catch (e) {
      debugPrint('EscPosPrintService.connectPrinterSerial($type) error: $e');
      return false;
    }
  }

  /// Check if a specific printer type is connected via Web Serial.
  static bool isSerialConnected(String type) {
    if (!kIsWeb) return false;
    try {
      final jsonStr = jsPrintIsConnected(type);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Disconnect a serial printer.
  static Future<void> disconnectSerial(String type) async {
    if (!kIsWeb) return;
    try {
      await jsPrintDisconnect(type);
    } catch (e) {
      debugPrint('EscPosPrintService.disconnectSerial($type) error: $e');
    }
  }

  /// Send raw data via Web Serial.
  static Future<bool> printDataSerial(String type, Uint8List data) async {
    if (!kIsWeb || !isSerialConnected(type)) return false;
    try {
      final jsonStr = await jsPrintPrint(type, data);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['success'] == true;
    } catch (e) {
      debugPrint('EscPosPrintService.printDataSerial($type) error: $e');
      return false;
    }
  }

  /// Auto-reconnect to a previously authorized serial port (no dialog).
  static Future<bool> autoReconnectSerial(String type) async {
    if (!kIsWeb) return false;
    try {
      final vid = await _getSavedVendorId(type);
      if (vid == null) return false;
      final jsonStr = await jsPrintAutoReconnect(type, vendorId: vid, productId: await _getSavedProductId(type));
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['success'] == true;
    } catch (e) {
      debugPrint('EscPosPrintService.autoReconnectSerial($type) error: $e');
      return false;
    }
  }

  /// Scan all previously authorized serial ports (no dialog).
  static Future<List<Map<String, dynamic>>> scanAllPorts() async {
    if (!kIsWeb) return [];
    try {
      final jsonStr = await jsPrintScanAllPorts();
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      final ports = result['ports'] as List?;
      if (ports == null) return [];
      return ports.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('EscPosPrintService.scanAllPorts error: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // WebUSB API (Fallback)
  // ═════════════════════════════════════════════════════════════════════════

  /// Check if WebUSB API is available in this browser.
  static bool isWebUsbAvailable() {
    if (!kIsWeb) return false;
    return jsCheckWebUsbAvailable();
  }

  /// Connect to a USB printer via WebUSB API.
  static Future<bool> connectPrinterUsb(String type) async {
    if (!kIsWeb) return false;
    try {
      final jsonStr = await jsPrintUsbConnect(type);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (result['success'] == true) {
        final newVid = result['vendorId'] as int?;
        final newPid = result['productId'] as int?;
        debugPrint('USB printer connected ($type): vendor=$newVid, product=$newPid');
        if (newVid != null) await _saveVendorId(type, newVid, newPid);
        return true;
      }
      if (result['cancelled'] == true) {
        debugPrint('User cancelled USB printer selection ($type)');
      } else {
        debugPrint('USB connection failed ($type): ${result['error']}');
      }
      return false;
    } catch (e) {
      debugPrint('EscPosPrintService.connectPrinterUsb($type) error: $e');
      return false;
    }
  }

  /// Check if a specific printer type is connected via WebUSB.
  static bool isUsbConnected(String type) {
    if (!kIsWeb) return false;
    try {
      final jsonStr = jsPrintUsbIsConnected(type);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Disconnect a USB printer.
  static Future<void> disconnectUsb(String type) async {
    if (!kIsWeb) return;
    try {
      await jsPrintUsbDisconnect(type);
    } catch (e) {
      debugPrint('EscPosPrintService.disconnectUsb($type) error: $e');
    }
  }

  /// Send raw data via WebUSB.
  static Future<bool> printDataUsb(String type, Uint8List data) async {
    if (!kIsWeb || !isUsbConnected(type)) return false;
    try {
      final jsonStr = await jsPrintUsbPrint(type, data);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['success'] == true;
    } catch (e) {
      debugPrint('EscPosPrintService.printDataUsb($type) error: $e');
      return false;
    }
  }

  /// Auto-reconnect to a previously authorized USB printer (no dialog).
  static Future<bool> autoReconnectUsb(String type) async {
    if (!kIsWeb) return false;
    try {
      final vid = await _getSavedVendorId(type);
      if (vid == null) return false;
      final jsonStr = await jsPrintUsbAutoReconnect(type, vendorId: vid, productId: await _getSavedProductId(type));
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['success'] == true;
    } catch (e) {
      debugPrint('EscPosPrintService.autoReconnectUsb($type) error: $e');
      return false;
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // Unified API (used by main.dart)
  // ═════════════════════════════════════════════════════════════════════════

  /// Check if any printer API is available in this browser.
  static bool isAvailable() {
    if (!kIsWeb) return false;
    return jsCheckWebSerialAvailable() || jsCheckWebUsbAvailable();
  }

  /// Check if a specific printer type is connected (via any method).
  static bool isConnected(String type) {
    return isSerialConnected(type) || isUsbConnected(type);
  }

  /// Connect to a printer (tries Serial first, falls back to WebUSB).
  static Future<bool> connectPrinter({required String type}) async {
    if (!kIsWeb || !isAvailable()) return false;

    // Try Web Serial first (most common for thermal printers)
    if (jsCheckWebSerialAvailable()) {
      final ok = await connectPrinterSerial(type);
      if (ok) return true;
    }

    // Fallback to WebUSB
    if (jsCheckWebUsbAvailable()) {
      return await connectPrinterUsb(type);
    }

    return false;
  }

  /// Disconnect a printer (disconnects both Serial and WebUSB).
  static Future<void> disconnectPrinter(String type) async {
    if (!kIsWeb) return;
    await disconnectSerial(type);
    await disconnectUsb(type);
  }

  /// Auto-reconnect to a previously authorized printer (tries Serial, then WebUSB).
  static Future<bool> autoReconnect(String type) async {
    if (!kIsWeb) return false;

    // Try Serial first
    if (jsCheckWebSerialAvailable()) {
      final ok = await autoReconnectSerial(type);
      if (ok) return true;
    }

    // Fallback to WebUSB
    if (jsCheckWebUsbAvailable()) {
      return await autoReconnectUsb(type);
    }

    return false;
  }

  /// Send raw data via any available connection (Serial first, then WebUSB).
  static Future<bool> printViaAny(String type, Uint8List data) async {
    if (!kIsWeb) return false;

    // Try Serial first
    if (isSerialConnected(type)) {
      final ok = await printDataSerial(type, data);
      if (ok) return true;
    }

    // Fallback to WebUSB
    if (isUsbConnected(type)) {
      return await printDataUsb(type, data);
    }

    debugPrint('printViaAny($type): no connection available');
    return false;
  }

  /// Auto-reconnect ALL printers on app startup.
  static Future<void> autoReconnectAll() async {
    if (!kIsWeb) return;
    // First sync saved IDs to JS bridge
    await setSavedDevicesInJs();

    for (final type in [labelPrinterType, receiptPrinterType]) {
      await autoReconnect(type);
    }
  }

  /// Get the USB vendor ID of a connected printer (via any method), or null.
  static int? getConnectedVendorId(String type) {
    if (!kIsWeb) return null;
    try {
      if (isSerialConnected(type)) {
        final jsonStr = jsPrintIsConnected(type);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        return result['vendorId'] as int?;
      }
      if (isUsbConnected(type)) {
        final jsonStr = jsPrintUsbIsConnected(type);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        return result['vendorId'] as int?;
      }
    } catch (_) {}
    return null;
  }

  /// Get the USB product ID of a connected printer (via any method), or null.
  static int? getConnectedProductId(String type) {
    if (!kIsWeb) return null;
    try {
      if (isSerialConnected(type)) {
        final jsonStr = jsPrintIsConnected(type);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        return result['productId'] as int?;
      }
      if (isUsbConnected(type)) {
        final jsonStr = jsPrintUsbIsConnected(type);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        return result['productId'] as int?;
      }
    } catch (_) {}
    return null;
  }

  // ─── Helper: Saved Device IDs ──────────────────────────────────────────

  static Future<int?> _getSavedVendorId(String type) async {
    try {
      final val = await DatabaseHelper.getSetting('usb_vid_' + type);
      if (val != null && val.isNotEmpty) return int.tryParse(val);
    } catch (_) {}
    return null;
  }

  static Future<int?> _getSavedProductId(String type) async {
    try {
      final val = await DatabaseHelper.getSetting('usb_pid_' + type);
      if (val != null && val.isNotEmpty) return int.tryParse(val);
    } catch (_) {}
    return null;
  }

  static Future<void> _saveVendorId(String type, int vendorId, int? productId) async {
    try {
      await DatabaseHelper.saveSetting('usb_vid_' + type, vendorId.toString());
      if (productId != null) {
        await DatabaseHelper.saveSetting('usb_pid_' + type, productId.toString());
      }
    } catch (e) {
      debugPrint('Error saving USB IDs for ' + type + ': ' + e.toString());
    }
  }

  /// Sync saved USB vendor/product IDs from persistent storage to the JS bridge.
  static Future<void> setSavedDevicesInJs() async {
    if (!kIsWeb) return;
    try {
      for (final type in [labelPrinterType, receiptPrinterType]) {
        final vid = await _getSavedVendorId(type);
        final pid = await _getSavedProductId(type);
        jsPrintSetSavedDeviceIds(type, vid, pid);
      }
    } catch (e) {
      debugPrint('EscPosPrintService.setSavedDevicesInJs error: ' + e.toString());
    }
  }

  // ─── Print Functions ──────────────────────────────────────────────────

  /// Print a label to the connected label printer.
  static Future<bool> printLabel(Ticket ticket) async {
    if (!kIsWeb) return false;
    try {
      final data = _buildLabelEscPos(ticket);
      return await printViaAny(labelPrinterType, data);
    } catch (e) {
      debugPrint('EscPosPrintService.printLabel error: ' + e.toString());
      return false;
    }
  }

  /// Print a receipt to the connected receipt printer.
  static Future<bool> printReceipt(Ticket ticket, {int copies = 1}) async {
    if (!kIsWeb) return false;
    try {
      for (int i = 0; i < copies; i++) {
        final data = _buildReceiptEscPos(ticket, copyIndex: i + 1, totalCopies: copies);
        final ok = await printViaAny(receiptPrinterType, data);
        if (!ok) {
          debugPrint('ESC/POS receipt copy ${i + 1} failed');
          return false;
        }
      }
      debugPrint('ESC/POS receipt printed successfully ($copies copies)');
      return true;
    } catch (e) {
      debugPrint('EscPosPrintService.printReceipt error: ' + e.toString());
      return false;
    }
  }

  // ─── ESC/POS Layout Builders ──────────────────────────────────────────

  static Uint8List _buildLabelEscPos(Ticket ticket) {
    final b = EscPosBuilder();
    b.init();
    b.align(1);

    b.charSize(2, 2);
    b.textLn('العطار استور');
    b.charSize(1, 1);
    b.textLn('================');

    b.bold(true);
    b.textLn('العميل: ${ticket.customerName ?? "---"}');
    b.bold(false);
    if (ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty) {
      b.textLn('هاتف: ${ticket.customerPhone}');
    }
    b.textLn('');

    b.bold(true);
    b.textLn('الجهاز: ${ticket.deviceModel}');
    b.bold(false);
    if (ticket.problem.isNotEmpty) {
      b.textLn('العطل: ${ticket.problem}');
    }
    b.textLn('');

    final dateStr = DateFormat('yyyy-MM-dd').format(ticket.receivedDate);
    b.textLn('التاريخ: $dateStr');
    b.textLn('رقم التذكرة: ${ticket.id ?? "---"}');

    if (ticket.id != null) {
      b.feed(1);
      b.align(1);
      b.barcode128(ticket.id.toString());
    }

    b.align(1);
    b.textLn('');
    b.textLn('شكراً لثقتكم');
    b.textLn('Developed By Eng: BELALZAGHL0L');

    b.feed(3);
    b.cut();
    return b.build();
  }

  static Uint8List _buildReceiptEscPos(Ticket ticket, {int copyIndex = 1, int totalCopies = 1}) {
    final b = EscPosBuilder();
    b.init();
    b.align(1);

    b.charSize(2, 2);
    b.bold(true);
    b.textLn('العطار استور');
    b.charSize(1, 1);
    b.bold(false);
    b.textLn('نظام صيانة الموبايلات');
    b.hr();

    b.align(0);
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(ticket.receivedDate);
    b.textLn('التاريخ: $dateStr');
    b.textLn('رقم التذكرة: ${ticket.id ?? "---"}');
    b.textLn('');

    b.bold(true);
    b.textLn('بيانات العميل:');
    b.bold(false);
    b.textLn('الاسم: ${ticket.customerName ?? "---"}');
    if (ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty) {
      b.textLn('الهاتف: ${ticket.customerPhone}');
    }
    b.textLn('');

    b.bold(true);
    b.textLn('بيانات الجهاز:');
    b.bold(false);
    b.textLn('الموديل: ${ticket.deviceModel ?? "---"}');
    if (ticket.deviceCondition.isNotEmpty) {
      b.textLn('الحالة: ${ticket.deviceCondition}');
    }
    b.textLn('');

    b.bold(true);
    b.textLn('العطل:');
    b.bold(false);
    b.textLn(ticket.problem.isEmpty ? '---' : ticket.problem);
    b.textLn('');

    b.hr();
    b.bold(true);
    b.charSize(2, 2);
    b.textLn('الإجمالي: ${ticket.cost.toStringAsFixed(2)} ج.م');
    b.charSize(1, 1);
    b.bold(false);

    b.hr();
    if (ticket.paymentMethod != null && ticket.paymentMethod!.isNotEmpty) {
      b.textLn('طريقة الدفع: ${ticket.paymentMethod}');
    }
    if (ticket.technicianName != null && ticket.technicianName!.isNotEmpty) {
      b.textLn('الفني: ${ticket.technicianName}');
    }

    b.align(1);
    b.hr();
    b.textLn('');
    b.textLn('شكراً لثقتكم في العطار استور');

    final qrData = 'ELATTAR:${ticket.id}:${ticket.cost.toStringAsFixed(2)}';
    b.align(1);
    b.qrCode(qrData);

    if (totalCopies > 1) {
      b.align(1);
      b.textLn('(نسخة $copyIndex من $totalCopies)');
    }

    b.textLn('');
    b.textLn('Developed By Eng: BELALZAGHL0L');
    b.feed(4);
    b.cut();
    return b.build();
  }
}
