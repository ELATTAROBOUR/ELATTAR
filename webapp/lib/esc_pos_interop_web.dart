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

@JS('__printerSetSavedDeviceIds')
external void _jsSetSavedDeviceIds(
  JSString type,
  JSNumber? usbVendorId,
  JSNumber? usbProductId,
);

@JS('__printerGetSavedDeviceIds')
external String _jsGetSavedDeviceIds();

@JS('__printerScanAllPorts')
external JSPromise _jsScanAllPorts();

// ─── WebUSB JS Function Bindings ────────────────────────────────────────────

@JS('__printerUsbConnect')
external JSPromise _jsUsbConnect(JSString type);

@JS('__printerUsbPrint')
external JSPromise _jsUsbPrint(JSString type, JSArray<JSNumber> data);

@JS('__printerUsbAutoReconnect')
external JSPromise _jsUsbAutoReconnect(
  JSString type,
  JSNumber usbVendorId,
  JSNumber? usbProductId,
);

@JS('__printerUsbIsAvailable')
external String _jsUsbIsAvailable();

@JS('__printerUsbGetAuthorized')
external JSPromise _jsUsbGetAuthorized();

@JS('__printerUsbDisconnect')
external JSPromise _jsUsbDisconnect(JSString type);

@JS('__printerUsbIsConnected')
external String _jsUsbIsConnected(JSString type);

@JS('navigator.serial')
external JSObject? get _jsSerial;

@JS('navigator.usb')
external JSObject? get _jsUsb;

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

/// Set saved USB vendor/product IDs in the JS bridge for auto-detection.
void jsPrintSetSavedDeviceIds(String type, int? vendorId, int? productId) {
  _jsSetSavedDeviceIds(type.toJS, vendorId?.toJS, productId?.toJS);
}

/// Get all saved device IDs from the JS bridge.
String jsPrintGetSavedDeviceIds() {
  return _jsGetSavedDeviceIds();
}

/// Scan all previously authorized serial ports without showing a dialog.
Future<String> jsPrintScanAllPorts() async {
  try {
    final result = await _jsScanAllPorts().toDart;
    return result.toString();
  } catch (e) {
    return '{"ports": [], "error": "$e"}';
  }
}

// ─── WebUSB Public API ─────────────────────────────────────────────────────

/// Check if WebUSB API is available in this browser.
bool jsCheckWebUsbAvailable() {
  return _jsUsb != null;
}

/// Request a USB printer via WebUSB API (shows browser chooser filtered by printer class).
Future<String> jsPrintUsbConnect(String type) async {
  try {
    final result = await _jsUsbConnect(type.toJS).toDart;
    return result.toString();
  } catch (e) {
    return '{"success": false, "error": "$e"}';
  }
}

/// Send raw bytes to a WebUSB-connected printer.
Future<String> jsPrintUsbPrint(String type, Uint8List data) async {
  try {
    final jsArray = data.toList().map((e) => e.toJS).toList().toJS;
    final result = await _jsUsbPrint(type.toJS, jsArray).toDart;
    return result.toString();
  } catch (e) {
    return '{"success": false, "error": "$e"}';
  }
}

/// Auto-reconnect to a previously authorized WebUSB device.
Future<String> jsPrintUsbAutoReconnect(
  String type, {
  required int vendorId,
  int? productId,
}) async {
  try {
    final result = await _jsUsbAutoReconnect(
      type.toJS,
      vendorId.toJS,
      productId?.toJS,
    ).toDart;
    return result.toString();
  } catch (e) {
    return '{"success": false, "error": "$e"}';
  }
}

/// Check if WebUSB API is available (sync).
String jsPrintUsbIsAvailable() {
  return _jsUsbIsAvailable();
}

/// Get all previously authorized WebUSB devices (no dialog).
Future<String> jsPrintUsbGetAuthorized() async {
  try {
    final result = await _jsUsbGetAuthorized().toDart;
    return result.toString();
  } catch (e) {
    return '{"devices": [], "error": "$e"}';
  }
}

/// Disconnect a WebUSB-connected printer.
Future<String> jsPrintUsbDisconnect(String type) async {
  try {
    final result = await _jsUsbDisconnect(type.toJS).toDart;
    return result.toString();
  } catch (e) {
    return '{"success": false, "error": "$e"}';
  }
}

/// Check if a WebUSB printer is connected (sync).
String jsPrintUsbIsConnected(String type) {
  return _jsUsbIsConnected(type.toJS);
}
