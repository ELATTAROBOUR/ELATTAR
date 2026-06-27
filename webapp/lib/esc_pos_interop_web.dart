// lib/esc_pos_interop_web.dart
// Web implementation using dart:js_interop to access the Web Serial API
// via the JavaScript bridge (web/js/printer_bridge.js).
// Supports multiple printer connections keyed by type ('label', 'receipt').

// ignore_for_file: unused_import
import 'dart:js_interop';
import 'dart:typed_data';

// ─── JS Function Bindings ───────────────────────────────────────────────────

@JS('__printerConnect')
external JSPromise _jsConnect(
  JSString type,
  JSNumber? usbVendorId,
  JSNumber? usbProductId,
);

@JS('__printerPrint')
external JSPromise _jsPrint(JSString type, JSArray<JSNumber> data);

@JS('__printerDisconnect')
external JSPromise _jsDisconnect(JSString type);

@JS('__printerIsConnected')
external String _jsIsConnected(JSString type);

@JS('__printerAutoReconnect')
external JSPromise _jsAutoReconnect(
  JSString type,
  JSNumber? usbVendorId,
  JSNumber? usbProductId,
);

@JS('navigator.serial')
external JSObject? get _jsSerial;

// ─── Public API ─────────────────────────────────────────────────────────────

/// Check if Web Serial API is available in this browser.
bool jsCheckWebSerialAvailable() {
  return _jsSerial != null;
}

/// Request a serial port from user and connect for a specific printer type.
Future<String> jsPrintConnect(
  String type,
  int? vendorId,
  int? productId,
) async {
  final result = await _jsConnect(
    type.toJS,
    vendorId?.toJS,
    productId?.toJS,
  ).toDart;
  return result.toString();
}

/// Send raw bytes to a specific printer type.
Future<String> jsPrintPrint(String type, Uint8List data) async {
  // Convert Uint8List to JSArray<JSNumber>
  final jsArray = data.toList().map((e) => e.toJS).toList().toJS;
  final result = await _jsPrint(type.toJS, jsArray).toDart;
  return result.toString();
}

/// Disconnect a specific printer type.
Future<String> jsPrintDisconnect(String type) async {
  final result = await _jsDisconnect(type.toJS).toDart;
  return result.toString();
}

/// Check if a specific printer type is connected (sync).
String jsPrintIsConnected(String type) {
  return _jsIsConnected(type.toJS);
}

/// Auto-reconnect to previously authorized USB printers without showing a dialog.
/// Uses saved vendor/product IDs to find the matching port.
Future<String> jsPrintAutoReconnect(
  String type, {
  int? vendorId,
  int? productId,
}) async {
  try {
    final result = await _jsAutoReconnect(
      type.toJS,
      vendorId?.toJS,
      productId?.toJS,
    ).toDart;
    return result.toString();
  } catch (e) {
    return '{"success": false, "error": "$e"}';
  }
}
