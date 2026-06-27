// lib/esc_pos_print_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// ESC/POS Command Builder (EscPosBuilder) — pure Dart ESC/POS byte sequences.
// Printing uses Printing.directPrintPdf() via print_service.dart.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';

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
// ESC/POS Print Service
// NOTE: The EscPosPrintService class has been removed.
// Printing now uses Printing.directPrintPdf() for both web and desktop.
// ═════════════════════════════════════════════════════════════════════════════

// -- EscPosPrintService removed --
// The EscPosPrintService was using a local HTTP server (print_server.ps1).
// We now use Printing.directPrintPdf() via the browser's print dialog (web)
// or the Windows print system (desktop). Much simpler and more reliable.
class EscPosPrintService {
  // This class is intentionally empty.
  // Printing now uses Printing.directPrintPdf() for both web and desktop.
  // The old HTTP server approach (print_server.ps1) has been removed.
  //
  // Static members:
  //   EscPosBuilder  — pure Dart ESC/POS command builder (still available)
}
