// lib/esc_pos_print_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// ESC/POS Direct USB Printing Service for Web
// Uses the Web Serial API via JavaScript bridge to send ESC/POS commands
// directly to thermal printers, enabling zero-dialog automatic printing.
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
  /// Printer type keys used for multi-printer support
  static const String labelPrinterType = 'label';
  static const String receiptPrinterType = 'receipt';

  /// Check if Web Serial API is available in this browser
  static bool isWebSerialAvailable() {
    if (!kIsWeb) return false;
    return jsCheckWebSerialAvailable();
  }

  /// Try to connect to a USB printer via Web Serial for a specific type.
  /// Always shows the full device chooser (no filters) so the user can
  /// select any connected USB/serial device.
  /// On success, saves the vendor/product ID for future auto-reconnect.
  static Future<bool> connectPrinter({required String type}) async {
    if (!kIsWeb || !isWebSerialAvailable()) return false;

    try {
      // Always call with no filters so the user sees ALL serial devices
      // and can select their printer from the chooser dialog.
      final jsonStr = await jsPrintConnect(type, null, null);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (result['success'] == true) {
        final newVid = result['vendorId'] as int?;
        final newPid = result['productId'] as int?;
        debugPrint(
          'USB printer connected ($type): vendor=$newVid, product=$newPid',
        );
        // Save the vendor/product ID for future auto-reconnect
        if (newVid != null) {
          await _saveVendorId(type, newVid, newPid);
        }
        return true;
      }

      if (result['cancelled'] == true) {
        debugPrint('User cancelled printer selection ($type)');
      } else {
        debugPrint('Printer connection failed ($type): ${result['error']}');
      }
      return false;
    } catch (e) {
      debugPrint('EscPosPrintService.connectPrinter($type) error: $e');
      return false;
    }
  }

  /// Disconnect a specific printer type
  static Future<void> disconnectPrinter(String type) async {
    if (!kIsWeb) return;
    try {
      await jsPrintDisconnect(type);
    } catch (e) {
      debugPrint('EscPosPrintService.disconnectPrinter($type) error: $e');
    }
  }

  /// Try to auto-reconnect to a previously authorized printer without showing a dialog.
  /// Uses saved USB vendor/product IDs to find the matching port via getPorts().
  /// Does NOT save or overwrite saved IDs — those come from explicit user connections only.
  /// Call this on app startup to restore printer connections from a previous session.
  static Future<bool> autoReconnect(String type) async {
    if (!kIsWeb || !isWebSerialAvailable()) return false;
    try {
      // First, sync saved IDs from persistent storage to the JS bridge.
      // This ensures the onconnect handler in JS knows which devices to watch for.
      await setSavedDevicesInJs();

      final savedVid = await _getSavedVendorId(type);
      final jsonStr = await jsPrintAutoReconnect(
        type,
        vendorId: savedVid,
        productId: savedVid != null ? await _getSavedProductId(type) : null,
      );
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['success'] == true;
    } catch (e) {
      debugPrint('EscPosPrintService.autoReconnect($type) error: $e');
      return false;
    }
  }

  /// Get saved USB vendor ID for a printer type from settings
  static Future<int?> _getSavedVendorId(String type) async {
    try {
      final val = await DatabaseHelper.getSetting('usb_vid_$type');
      if (val != null && val.isNotEmpty) return int.tryParse(val);
    } catch (_) {}
    return null;
  }

  /// Get saved USB product ID for a printer type from settings
  static Future<int?> _getSavedProductId(String type) async {
    try {
      final val = await DatabaseHelper.getSetting('usb_pid_$type');
      if (val != null && val.isNotEmpty) return int.tryParse(val);
    } catch (_) {}
    return null;
  }

  /// Save USB vendor/product IDs for a printer type
  static Future<void> _saveVendorId(
    String type,
    int vendorId,
    int? productId,
  ) async {
    try {
      await DatabaseHelper.saveSetting('usb_vid_$type', vendorId.toString());
      if (productId != null) {
        await DatabaseHelper.saveSetting('usb_pid_$type', productId.toString());
      }
    } catch (e) {
      debugPrint('Error saving USB IDs for $type: $e');
    }
  }

  /// Sync saved USB vendor/product IDs from persistent storage to the JS bridge.
  /// This must be called on app startup BEFORE autoReconnect, so that the JS
  /// onconnect handler knows which devices to watch for.
  static Future<void> setSavedDevicesInJs() async {
    if (!kIsWeb || !isWebSerialAvailable()) return;
    try {
      for (final type in [labelPrinterType, receiptPrinterType]) {
        final vid = await _getSavedVendorId(type);
        final pid = await _getSavedProductId(type);
        jsPrintSetSavedDeviceIds(type, vid, pid);
      }
    } catch (e) {
      debugPrint('EscPosPrintService.setSavedDevicesInJs error: $e');
    }
  }

  /// Scan all previously authorized serial ports (no dialog) and return info.
  /// Returns a list of {vendorId, productId} for each authorized port.
  /// Use this to check what devices are available without showing a chooser.
  static Future<List<Map<String, dynamic>>> scanAllPorts() async {
    if (!kIsWeb || !isWebSerialAvailable()) return [];
    try {
      final jsonStr = await jsPrintScanAllPorts();
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      final ports = result['ports'] as List<dynamic>? ?? [];
      return ports.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('EscPosPrintService.scanAllPorts error: $e');
      return [];
    }
  }

  // ═════════════════════════════════════════════════════════════════════════
  // WebUSB API (Alternative for printers not visible via Web Serial)
  // ═════════════════════════════════════════════════════════════════════════

  /// Check if WebUSB API is available in this browser
  static bool isWebUsbAvailable() {
    if (!kIsWeb) return false;
    return jsCheckWebUsbAvailable();
  }

  /// Connect to a USB printer via WebUSB API.
  /// Shows a browser chooser filtered by USB printer class.
  /// This is an alternative to connectPrinter() for printers that
  /// don't appear in the Web Serial API chooser.
  static Future<bool> connectUsbPrinter({required String type}) async {
    if (!kIsWeb || !isWebUsbAvailable()) return false;

    try {
      final jsonStr = await jsPrintUsbConnect(type);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (result['success'] == true) {
        final newVid = result['vendorId'] as int?;
        final newPid = result['productId'] as int?;
        final productName = result['productName'] as String?;
        debugPrint(
          'WebUSB printer connected ($type): vendor=$newVid, product=$newPid, name=$productName',
        );
        // Save IDs for auto-reconnect
        if (newVid != null) {
          await _saveVendorId(type, newVid, newPid);
          // Also save with 'usb_' prefix to distinguish WebUSB from Serial
          await DatabaseHelper.saveSetting('usb_method_$type', 'webusb');
        }
        return true;
      }

      if (result['cancelled'] == true) {
        debugPrint('User cancelled WebUSB printer selection ($type)');
      } else {
        debugPrint(
          'WebUSB printer connection failed ($type): ${result['error']}',
        );
      }
      return false;
    } catch (e) {
      debugPrint('EscPosPrintService.connectUsbPrinter($type) error: $e');
      return false;
    }
  }

  /// Disconnect a WebUSB printer
  static Future<void> disconnectUsbPrinter(String type) async {
    if (!kIsWeb) return;
    try {
      await jsPrintUsbDisconnect(type);
    } catch (e) {
      debugPrint('EscPosPrintService.disconnectUsbPrinter($type) error: $e');
    }
  }

  /// Try to auto-reconnect to a previously authorized WebUSB printer.
  static Future<bool> autoReconnectUsb(String type) async {
    if (!kIsWeb || !isWebUsbAvailable()) return false;
    try {
      final savedVid = await _getSavedVendorId(type);
      if (savedVid == null) return false;
      final jsonStr = await jsPrintUsbAutoReconnect(
        type,
        vendorId: savedVid,
        productId: await _getSavedProductId(type),
      );
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['success'] == true;
    } catch (e) {
      debugPrint('EscPosPrintService.autoReconnectUsb($type) error: $e');
      return false;
    }
  }

  /// Check if a specific printer type is connected via WebUSB
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

  /// Check if a printer type is connected via EITHER Web Serial or WebUSB
  static bool isAnyConnected(String type) {
    return isConnected(type) || isUsbConnected(type);
  }

  /// Print via whichever method is connected (Web Serial or WebUSB)
  static Future<bool> printViaAny(String type, Uint8List data) async {
    if (!kIsWeb) return false;

    // Try Web Serial first
    if (isConnected(type)) {
      try {
        final jsonStr = await jsPrintPrint(type, data);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (result['success'] == true) return true;
      } catch (_) {}
    }

    // Try WebUSB next
    if (isUsbConnected(type)) {
      try {
        final jsonStr = await jsPrintUsbPrint(type, data);
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;
        if (result['success'] == true) return true;
      } catch (_) {}
    }

    return false;
  }

  /// Get saved connection method for a printer type
  static Future<String?> _getSavedMethod(String type) async {
    try {
      return await DatabaseHelper.getSetting('usb_method_$type');
    } catch (_) {
      return null;
    }
  }

  /// Auto-reconnect ALL printers using BOTH methods (Serial first, then WebUSB).
  /// Called on app startup.
  static Future<void> autoReconnectAll() async {
    if (!kIsWeb) return;
    // First sync saved IDs to JS bridge
    await setSavedDevicesInJs();

    for (final type in [labelPrinterType, receiptPrinterType]) {
      // Try Web Serial auto-reconnect
      await autoReconnect(type);
      // Try WebUSB auto-reconnect
      await autoReconnectUsb(type);
    }
  }

  /// Check if a specific printer type is currently connected
  static bool isConnected(String type) {
    if (!kIsWeb) return false;
    try {
      final jsonStr = jsPrintIsConnected(type);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      return result['connected'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Get the USB vendor ID of a connected printer, or null
  static int? getConnectedVendorId(String type) {
    if (!kIsWeb) return null;
    try {
      final jsonStr = jsPrintIsConnected(type);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (result['connected'] == true) {
        return result['vendorId'] as int?;
      }
    } catch (_) {}
    return null;
  }

  /// Get the USB product ID of a connected printer, or null
  static int? getConnectedProductId(String type) {
    if (!kIsWeb) return null;
    try {
      final jsonStr = jsPrintIsConnected(type);
      final result = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (result['connected'] == true) {
        return result['productId'] as int?;
      }
    } catch (_) {}
    return null;
  }

  // ─── Print Functions ──────────────────────────────────────────────────────

  /// Print a label to the connected label USB printer.
  static Future<bool> printLabel(Ticket ticket) async {
    if (!kIsWeb || !isAnyConnected(labelPrinterType)) return false;

    try {
      final data = _buildLabelEscPos(ticket);
      return await printViaAny(labelPrinterType, data);
    } catch (e) {
      debugPrint('EscPosPrintService.printLabel error: $e');
      return false;
    }
  }

  /// Print a receipt to the connected receipt USB printer.
  static Future<bool> printReceipt(Ticket ticket, {int copies = 1}) async {
    if (!kIsWeb || !isAnyConnected(receiptPrinterType)) return false;

    try {
      for (int i = 0; i < copies; i++) {
        final data = _buildReceiptEscPos(
          ticket,
          copyIndex: i + 1,
          totalCopies: copies,
        );
        final ok = await printViaAny(receiptPrinterType, data);
        if (!ok) {
          debugPrint('ESC/POS receipt copy ${i + 1} failed');
          return false;
        }
      }
      debugPrint('ESC/POS receipt printed successfully ($copies copies)');
      return true;
    } catch (e) {
      debugPrint('EscPosPrintService.printReceipt error: $e');
      return false;
    }
  }

  // ─── ESC/POS Layout Builders ──────────────────────────────────────────────

  /// Build a thermal label (62mm)
  static Uint8List _buildLabelEscPos(Ticket ticket) {
    final b = EscPosBuilder();
    b.init();
    b.align(1); // Center

    // Header
    b.charSize(2, 2);
    b.textLn('العطار استور');
    b.charSize(1, 1);
    b.textLn('================');

    // Customer info
    b.bold(true);
    b.textLn('العميل: ${ticket.customerName ?? "---"}');
    b.bold(false);
    if (ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty) {
      b.textLn('هاتف: ${ticket.customerPhone}');
    }
    b.textLn('');

    // Device info
    b.bold(true);
    b.textLn('الجهاز: ${ticket.deviceModel}');
    b.bold(false);
    if (ticket.problem.isNotEmpty) {
      b.textLn('العطل: ${ticket.problem}');
    }
    b.textLn('');

    // Date and ID
    final dateStr = DateFormat('yyyy-MM-dd').format(ticket.receivedDate);
    b.textLn('التاريخ: $dateStr');
    b.textLn('رقم التذكرة: ${ticket.id ?? "---"}');

    // Barcode
    if (ticket.id != null) {
      b.feed(1);
      b.align(1);
      b.barcode128(ticket.id.toString());
    }

    // Footer
    b.align(1);
    b.textLn('');
    b.textLn('شكراً لثقتكم');
    b.textLn('Developed By Eng: BELALZAGHL0L');

    b.feed(3);
    b.cut();
    return b.build();
  }

  /// Build a thermal receipt (80mm)
  static Uint8List _buildReceiptEscPos(
    Ticket ticket, {
    int copyIndex = 1,
    int totalCopies = 1,
  }) {
    final b = EscPosBuilder();
    b.init();
    b.align(1); // Center

    // Header
    b.charSize(2, 2);
    b.bold(true);
    b.textLn('العطار استور');
    b.charSize(1, 1);
    b.bold(false);
    b.textLn('نظام صيانة الموبايلات');
    b.hr();

    // Ticket info
    b.align(0); // Left
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(ticket.receivedDate);
    b.textLn('التاريخ: $dateStr');
    b.textLn('رقم التذكرة: ${ticket.id ?? "---"}');
    b.textLn('');

    // Customer
    b.bold(true);
    b.textLn('بيانات العميل:');
    b.bold(false);
    b.textLn('الاسم: ${ticket.customerName ?? "---"}');
    if (ticket.customerPhone != null && ticket.customerPhone!.isNotEmpty) {
      b.textLn('الهاتف: ${ticket.customerPhone}');
    }
    b.textLn('');

    // Device
    b.bold(true);
    b.textLn('بيانات الجهاز:');
    b.bold(false);
    b.textLn('الموديل: ${ticket.deviceModel ?? "---"}');
    if (ticket.deviceCondition.isNotEmpty) {
      b.textLn('الحالة: ${ticket.deviceCondition}');
    }
    b.textLn('');

    // Problem
    b.bold(true);
    b.textLn('العطل:');
    b.bold(false);
    b.textLn(ticket.problem.isEmpty ? '---' : ticket.problem);
    b.textLn('');

    // Cost
    b.hr();
    b.bold(true);
    b.charSize(2, 2);
    b.textLn('الإجمالي: ${ticket.cost.toStringAsFixed(2)} ج.م');
    b.charSize(1, 1);
    b.bold(false);

    // Payment info
    b.hr();
    if (ticket.paymentMethod != null && ticket.paymentMethod!.isNotEmpty) {
      b.textLn('طريقة الدفع: ${ticket.paymentMethod}');
    }
    if (ticket.technicianName != null && ticket.technicianName!.isNotEmpty) {
      b.textLn('الفني: ${ticket.technicianName}');
    }

    // Footer
    b.align(1);
    b.hr();
    b.textLn('');
    b.textLn('شكراً لثقتكم في العطار استور');

    // QR code
    final qrData = 'ELATTAR:${ticket.id}:${ticket.cost.toStringAsFixed(2)}';
    b.align(1);
    b.qrCode(qrData);

    // Copy indicator
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
