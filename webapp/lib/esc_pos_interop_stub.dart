// lib/esc_pos_interop_stub.dart
// Stub implementation for native (non-web) platforms.
// The Web Serial API is only available in browsers.

import 'dart:typed_data';

Future<String> jsPrintConnect(
  String type,
  int? vendorId,
  int? productId,
) async {
  throw UnsupportedError('Web Serial API requires web platform');
}

Future<String> jsPrintPrint(String type, Uint8List data) async {
  throw UnsupportedError('Web Serial API requires web platform');
}

Future<String> jsPrintDisconnect(String type) async {
  throw UnsupportedError('Web Serial API requires web platform');
}

String jsPrintIsConnected(String type) {
  return '{"connected":false}';
}

Future<String> jsPrintAutoReconnect(
  String type, {
  int? vendorId,
  int? productId,
}) async {
  return '{"success": false}';
}

bool jsCheckWebSerialAvailable() {
  return false;
}

void jsPrintSetSavedDeviceIds(String type, int? vendorId, int? productId) {
  // Stub: no-op on native platforms
}

String jsPrintGetSavedDeviceIds() {
  return '{}';
}

Future<String> jsPrintScanAllPorts() async {
  return '{"ports": []}';
}

// ─── WebUSB Stubs (always unsupported on native) ────────────────────────────

bool jsCheckWebUsbAvailable() => false;

Future<String> jsPrintUsbConnect(String type) async {
  throw UnsupportedError('WebUSB API requires web platform');
}

Future<String> jsPrintUsbPrint(String type, Uint8List data) async {
  throw UnsupportedError('WebUSB API requires web platform');
}

Future<String> jsPrintUsbAutoReconnect(
  String type, {
  required int vendorId,
  int? productId,
}) async {
  return '{"success": false}';
}

String jsPrintUsbIsAvailable() => '{"available": false}';

Future<String> jsPrintUsbGetAuthorized() async => '{"devices": []}';

Future<String> jsPrintUsbDisconnect(String type) async {
  return '{"success": true}';
}

String jsPrintUsbIsConnected(String type) => '{"connected": false}';
