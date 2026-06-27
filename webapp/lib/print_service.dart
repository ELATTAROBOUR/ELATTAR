// lib/print_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Dual-Printer Service with Full Arabic Layout & Typography Support
//  • printLabel   → Printer selected in Settings (طابعة الملصقات)
//  • printReceipt → Printer selected in Settings (طابعة الفواتير)
//
//  Printer names are resolved via PrinterSettingsService — no hardcoding.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:arabic_reshaper/arabic_reshaper.dart';

import 'models.dart';
import 'printer_settings_service.dart';
import 'platform_stub.dart' if (dart.library.io) 'dart:io';

class PrintService {
  static pw.ThemeData? _cachedTheme;

  // ───────────────────────────────────────────────────────────────────────────
  // LABEL PDF
  // ───────────────────────────────────────────────────────────────────────────

  /// Generates the label PDF: Name / Phone / Problem on a 62×29 mm label.
  static Future<Uint8List> generateLabelPdf(Ticket ticket) async {
    final pdfTheme = await _getArabicTheme();
    final pdf = pw.Document();

    const pageFormat = PdfPageFormat(
      62 * PdfPageFormat.mm,
      29 * PdfPageFormat.mm,
      marginAll: 1 * PdfPageFormat.mm,
    );

    const double labelOffsetX = -6;
    const double labelOffsetY = 0;

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pdfTheme,
        build: (pw.Context ctx) {
          return pw.Directionality(
            textDirection: pw.TextDirection.ltr, // Structural LTR columns
            child: pw.Padding(
              padding: pw.EdgeInsets.only(
                right: -labelOffsetX * PdfPageFormat.mm,
                top: labelOffsetY * PdfPageFormat.mm,
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // Left Side: Rotated Ticket Number
                  pw.Container(
                    alignment: pw.Alignment.center,
                    width: 10 * PdfPageFormat.mm,
                    child: pw.Transform.rotate(
                      angle:
                          -1.57079632679, // -90 degrees counter-clockwise (reads bottom-to-top)
                      child: pw.Text(
                        '${ticket.id}',
                        style: pw.TextStyle(
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        maxLines: 1,
                      ),
                    ),
                  ),

                  // Vertical divider
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      vertical: 2 * PdfPageFormat.mm,
                    ),
                    child: pw.VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: PdfColors.black,
                    ),
                  ),

                  // Center/Right: Customer Details (Arabic RTL)
                  pw.Expanded(
                    child: pw.Directionality(
                      textDirection: pw.TextDirection.rtl,
                      child: pw.Center(
                        child: pw.FittedBox(
                          fit: pw.BoxFit.contain,
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              _buildBidiText(
                                ticket.customerName,
                                pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                              pw.SizedBox(height: 2),
                              _buildBidiText(
                                ticket.customerPhone,
                                pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                              pw.SizedBox(height: 2),
                              _buildBidiText(
                                ticket.problem,
                                pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // RECEIPT PDF
  // ───────────────────────────────────────────────────────────────────────────

  /// Generates the full repair receipt PDF with QR code.
  static Future<Uint8List> generateReceiptPdf(
    Ticket ticket, {
    bool isDelivery = false,
    double? overrideCost,
    String? overridePaymentMethod,
    String? overridePaymentDetails,
  }) async {
    final pdfTheme = await _getArabicTheme();
    final pdf = pw.Document();

    // ignore: no_leading_underscores_for_local_identifiers
    pw.Widget receiptRow(String label, String value) {
      return _receiptRowHelper(label, value, fontSize: 10);
    }

    const pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginLeft: 11 * PdfPageFormat.mm - 10,
      marginRight: 13 * PdfPageFormat.mm + 10,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 4 * PdfPageFormat.mm,
    );

    // ── QR Data & Image Generation ──────────────────────────────────────────
    debugPrint('QR Generation Started');

    // رقم الواتساب: رقم الفني إن وجد، وإلا رقم المحل
    final rawPhone =
        (ticket.technicianPhone != null &&
            ticket.technicianPhone!.trim().isNotEmpty)
        ? ticket.technicianPhone!.trim()
        : '201030003636';

    // تنسيق: أزل كل غير الأرقام، وتأكد من بدء الرقم بـ 20
    String waPhone = rawPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (waPhone.startsWith('0')) waPhone = '2$waPhone'; // 01x → 201x
    if (!waPhone.startsWith('20')) waPhone = '20$waPhone';

    // List of payload strategies (sending ticket number only)
    final List<String> payloadOptions = [
      'إيصال رقم: ${ticket.id}',
      'r-${ticket.id}',
      '${ticket.id}',
    ];

    pw.MemoryImage? qrImage;
    String finalPayloadUsed = '';

    for (int i = 0; i < payloadOptions.length; i++) {
      final text = payloadOptions[i];
      final String qrData = text.isEmpty
          ? 'https://wa.me/$waPhone'
          : 'https://wa.me/$waPhone?text=${Uri.encodeComponent(text)}';

      debugPrint('QR Payload: $qrData');
      debugPrint('QR Payload Length: ${qrData.length}');

      try {
        final qrValidation = QrValidator.validate(
          data: qrData,
          version: QrVersions.auto,
          errorCorrectionLevel: QrErrorCorrectLevel.H,
        );

        if (qrValidation.status == QrValidationStatus.valid) {
          final qrPainter = QrPainter.withQr(
            qr: qrValidation.qrCode!,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: ui.Color(0xFF000000),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: ui.Color(0xFF000000),
            ),
            gapless: false,
          );

          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          const qrSize = 200.0;
          qrPainter.paint(canvas, const ui.Size(qrSize, qrSize));
          final img = await recorder.endRecording().toImage(
            qrSize.toInt(),
            qrSize.toInt(),
          );
          final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            qrImage = pw.MemoryImage(byteData.buffer.asUint8List());
            finalPayloadUsed = qrData;
            debugPrint('QR Generation Success');
            break;
          } else {
            throw Exception('Byte data from image was null');
          }
        } else {
          throw Exception(
            'QR validation status is ${qrValidation.status} (Error: ${qrValidation.error})',
          );
        }
      } catch (e) {
        debugPrint('QR Generation Failed: $e');
        // Let the loop continue to try the next, shorter option.
      }
    }

    if (qrImage != null) {
      debugPrint('QR Added To PDF: YES');
    } else {
      debugPrint(
        'QR Generation Failed completely. Falling back to vector BarcodeWidget.',
      );
      debugPrint('QR Added To PDF: YES (vector fallback)');
      finalPayloadUsed = 'https://wa.me/$waPhone';
    }

    // ── Build PDF ───────────────────────────────────────────────────────────
    final receivedDateStr = DateFormat(
      'yyyy-MM-dd',
    ).format(ticket.receivedDate);
    final receivedTimeStr = DateFormat('hh:mm a').format(ticket.receivedDate);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pdfTheme,
        build: (pw.Context ctx) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // ── Payment Method Header (Vodafone Cash / InstaPay / Visa) ──
                if (isDelivery) ...[
                  if ((overridePaymentMethod ?? ticket.paymentMethod) ==
                      'vodafone_cash')
                    pw.Align(
                      alignment: pw.Alignment.center,
                      child: _buildBidiText(
                        'Vodafone Cash',
                        pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    )
                  else if ((overridePaymentMethod ?? ticket.paymentMethod) ==
                      'instapay')
                    pw.Align(
                      alignment: pw.Alignment.center,
                      child: _buildBidiText(
                        'InstaPay',
                        pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    )
                  else if ((overridePaymentMethod ?? ticket.paymentMethod) ==
                      'visa')
                    pw.Align(
                      alignment: pw.Alignment.center,
                      child: _buildBidiText(
                        'Visa',
                        pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  if ((overridePaymentMethod ?? ticket.paymentMethod) != null &&
                      (overridePaymentMethod ?? ticket.paymentMethod) != 'cash')
                    pw.SizedBox(height: 6),
                ],
                // ── Header ─────────────────────────────────────────────────
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: _buildBidiText(
                    'EL ATTAR STORE',
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    _cleanAndShapeText('محلات العطار استور'),
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    _cleanAndShapeText(
                      isDelivery
                          ? 'إيصال تسليم صيانة جهاز'
                          : 'إيصال استلام جهاز صيانة',
                    ),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 4),

                // ── Ticket Info ─────────────────────────────────────────────
                receiptRow('رقم الايصال', '#${ticket.id}'),
                if (ticket.complaintNumber != null &&
                    ticket.complaintNumber!.isNotEmpty) ...[
                  receiptRow('تاريخ الاستلام', receivedDateStr),
                  receiptRow('وقت الاستلام', receivedTimeStr),
                ],
                if (isDelivery) ...[
                  receiptRow(
                    'تاريخ التسليم',
                    DateFormat(
                      'yyyy-MM-dd',
                    ).format(ticket.deliveryDate ?? DateTime.now()),
                  ),
                  receiptRow(
                    'وقت التسليم',
                    DateFormat(
                      'hh:mm a',
                    ).format(ticket.deliveryDate ?? DateTime.now()),
                  ),
                ],
                // ── Customer ────────────────────────────────────────────────
                receiptRow('اسم العميل', ticket.customerName),
                receiptRow('رقم العميل', ticket.customerPhone),

                // ── Device & Problem ────────────────────────────────────────
                receiptRow('الجهاز', ticket.deviceModel),
                receiptRow('العطل', ticket.problem),

                // ── Status & Cost ───────────────────────────────────────────
                receiptRow(
                  isDelivery ? 'التكلفة النهائية' : 'التكلفة المبدئية',
                  '${(overrideCost ?? ticket.cost).toStringAsFixed(2)} ج.م',
                ),
                if (isDelivery &&
                    (overridePaymentMethod ?? ticket.paymentMethod) !=
                        null) ...[
                  receiptRow(
                    'طريقة الدفع',
                    _getPaymentMethodArabicName(
                      overridePaymentMethod ?? ticket.paymentMethod,
                    ),
                  ),
                  if ((overridePaymentMethod ?? ticket.paymentMethod) ==
                          'vodafone_cash' &&
                      (overridePaymentDetails ?? ticket.paymentDetails) !=
                          null &&
                      (overridePaymentDetails ?? ticket.paymentDetails)!
                          .isNotEmpty)
                    receiptRow(
                      'رقم فودافون كاش',
                      overridePaymentDetails ?? ticket.paymentDetails!,
                    ),
                  if ((overridePaymentMethod ?? ticket.paymentMethod) ==
                          'instapay' &&
                      (overridePaymentDetails ?? ticket.paymentDetails) !=
                          null &&
                      (overridePaymentDetails ?? ticket.paymentDetails)!
                          .isNotEmpty)
                    receiptRow(
                      'رقم انستا باي',
                      overridePaymentDetails ?? ticket.paymentDetails!,
                    ),
                ],

                // ── Device Condition ─────────────────────────────────────────
                if (ticket.deviceCondition.trim().isNotEmpty)
                  receiptRow('حالة الجهاز', ticket.deviceCondition),

                // ── Expected Delivery Time ───────────────────────────────────
                if (ticket.expectedDelivery != null &&
                    ticket.expectedDelivery!.trim().isNotEmpty)
                  receiptRow('توقيت التسليم', ticket.expectedDelivery!),

                // ── Technician ──────────────────────────────────────────────
                if (ticket.technicianName != null &&
                    ticket.technicianName!.isNotEmpty)
                  receiptRow('الفني المسؤول', ticket.technicianName!),
                if (ticket.technicianPhone != null &&
                    ticket.technicianPhone!.isNotEmpty)
                  receiptRow('هاتف الفني', ticket.technicianPhone!),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 6),

                // ── QR Code (always rendered) ──────────────────────────────
                pw.Center(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    color: PdfColors.white,
                    child: qrImage != null
                        ? pw.Image(qrImage, width: 130, height: 130)
                        : pw.BarcodeWidget(
                            data: finalPayloadUsed.isNotEmpty
                                ? finalPayloadUsed
                                : 'https://wa.me/$waPhone',
                            barcode: pw.Barcode.qrCode(
                              errorCorrectLevel:
                                  pw.BarcodeQRCorrectionLevel.high,
                            ),
                            width: 130,
                            height: 130,
                            drawText: false,
                            color: PdfColors.black,
                            backgroundColor: PdfColors.white,
                          ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: _buildBidiText(
                    'RECEIPT-${ticket.id}',
                    const pw.TextStyle(fontSize: 9),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                if (ticket.complaintNumber != null &&
                    ticket.complaintNumber!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  receiptRow(
                    'رقم الشكاوى',
                    ticket.complaintNumber?.trim().toUpperCase() == 'Y9S'
                        ? '01000361006'
                        : ticket.complaintNumber!,
                  ),
                ],
                pw.SizedBox(height: 8),

                // ── Footer ──────────────────────────────────────────────────
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    _cleanAndShapeText('شكراً لثقتكم بنا'),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: _buildBidiText(
                    'Developed By Eng:BELALZAGHL0L',
                    const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // DIRECT PRINTING API
  // ───────────────────────────────────────────────────────────────────────────

  /// Print a small customer label to the configured label printer.
  /// On web, uses the browser print dialog via [Printing.formatPdf].
  static Future<void> printLabel(Ticket ticket) async {
    debugPrint('Auto Label Print Started');
    try {
      final bytes = await generateLabelPdf(ticket);

      const pageFormat = PdfPageFormat(
        62 * PdfPageFormat.mm,
        29 * PdfPageFormat.mm,
        marginAll: 1 * PdfPageFormat.mm,
      );

      if (kIsWeb) {
        // On web: use browser print dialog
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          format: pageFormat,
          name: 'ملصق-${ticket.id}',
        );
        debugPrint('Label print completed via browser dialog');
      } else {
        final config = await PrinterSettingsService.load();
        final printer = await PrinterSettingsService.resolve(
          config.labelPrinterName,
          'طابعة الملصقات',
        );

        debugPrint('Selected Printer: ${printer.name}');
        debugPrint('Document Type: label');
        debugPrint('Ticket ID: ${ticket.id}');

        final result = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => bytes,
          format: pageFormat,
        );

        debugPrint('Label print result: ${result ? "success" : "failed"}');
        if (!result) {
          throw Exception(
            'فشلت عملية طباعة الملصق على الطابعة ${printer.name}',
          );
        }
      }
    } catch (e) {
      debugPrint('Auto label print failed: $e');
      rethrow;
    }
  }

  /// Print a full repair receipt to the configured receipt printer.
  /// On web, uses the browser print dialog via [Printing.formatPdf].
  static Future<void> printReceipt(
    Ticket ticket, {
    bool isDelivery = false,
    double? overrideCost,
    String? overridePaymentMethod,
    String? overridePaymentDetails,
    int copies = 1,
  }) async {
    debugPrint('Auto Receipt Print Started');
    try {
      final bytes = await generateReceiptPdf(
        ticket,
        isDelivery: isDelivery,
        overrideCost: overrideCost,
        overridePaymentMethod: overridePaymentMethod,
        overridePaymentDetails: overridePaymentDetails,
      );

      const pageFormat = PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginLeft: 11 * PdfPageFormat.mm - 10,
        marginRight: 13 * PdfPageFormat.mm + 10,
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
      );

      if (kIsWeb) {
        // On web: use browser print dialog
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          format: pageFormat,
          name: 'إيصال-${ticket.id}',
        );
        debugPrint('Receipt print completed via browser dialog');
      } else {
        final config = await PrinterSettingsService.load();
        final printer = await PrinterSettingsService.resolve(
          config.receiptPrinterName,
          'طابعة الفواتير',
        );

        debugPrint('Selected Printer: ${printer.name}');
        debugPrint(
          'Document Type: receipt (isDelivery: $isDelivery, copies: $copies)',
        );
        debugPrint('Ticket ID: ${ticket.id}');

        for (int i = 0; i < copies; i++) {
          debugPrint('Printing copy ${i + 1} of $copies');
          final result = await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) async => bytes,
            format: pageFormat,
          );

          debugPrint(
            'Receipt print copy ${i + 1} result: ${result ? "success" : "failed"}',
          );
          if (!result) {
            throw Exception(
              'فشلت عملية طباعة الإيصال على الطابعة ${printer.name}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Auto receipt print failed: $e');
      rethrow;
    } finally {
      debugPrint('Auto Printing Completed');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS
  // ───────────────────────────────────────────────────────────────────────────

  static Future<pw.ThemeData> _getArabicTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;

    pw.Font? regular;
    pw.Font? bold;

    if (Platform.isWindows) {
      final regFile = File('C:\\Windows\\Fonts\\tahoma.ttf');
      final boldFile = File('C:\\Windows\\Fonts\\tahomabd.ttf');
      if (regFile.existsSync() && boldFile.existsSync()) {
        try {
          regular = pw.Font.ttf(regFile.readAsBytesSync().buffer.asByteData());
          bold = pw.Font.ttf(boldFile.readAsBytesSync().buffer.asByteData());
          debugPrint('Loaded Tahoma Arabic font from Windows fonts.');
        } catch (e) {
          debugPrint('Failed reading local Tahoma fonts: $e');
        }
      }
    }

    if (regular == null || bold == null) {
      try {
        final regRes = await http
            .get(
              Uri.parse(
                'https://cdn.jsdelivr.net/fontsource/fonts/cairo@latest/arabic-400-normal.ttf',
              ),
            )
            .timeout(const Duration(seconds: 5));
        final boldRes = await http
            .get(
              Uri.parse(
                'https://cdn.jsdelivr.net/fontsource/fonts/cairo@latest/arabic-700-normal.ttf',
              ),
            )
            .timeout(const Duration(seconds: 5));
        if (regRes.statusCode == 200 && boldRes.statusCode == 200) {
          regular = pw.Font.ttf(regRes.bodyBytes.buffer.asByteData());
          bold = pw.Font.ttf(boldRes.bodyBytes.buffer.asByteData());
          debugPrint('Loaded Cairo Arabic font from GitHub.');
        }
      } catch (e) {
        debugPrint('Dynamic Cairo download failed: $e');
      }
    }

    regular ??= pw.Font.helvetica();
    bold ??= pw.Font.helveticaBold();

    _cachedTheme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      fontFallback: [pw.Font.helvetica(), pw.Font.helveticaBold()],
    );
    return _cachedTheme!;
  }

  static String _cleanAndShapeText(String text) {
    if (text.isEmpty) return '';
    final cleaned = text.replaceAll(
      RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'),
      '',
    );
    try {
      return ArabicReshaper.instance.reshape(cleaned);
    } catch (e) {
      debugPrint('ArabicReshaper error: $e');
      return cleaned;
    }
  }

  static pw.Widget _buildBidiText(
    String text,
    pw.TextStyle style, {
    pw.TextAlign textAlign = pw.TextAlign.right,
  }) {
    if (text.isEmpty) {
      return pw.Text('', style: style);
    }

    if (text.contains('\n')) {
      final lines = text.split('\n');
      return pw.Column(
        crossAxisAlignment: textAlign == pw.TextAlign.center
            ? pw.CrossAxisAlignment.center
            : (textAlign == pw.TextAlign.left
                  ? pw.CrossAxisAlignment.start
                  : pw.CrossAxisAlignment.end),
        children: lines
            .map((line) => _buildBidiText(line, style, textAlign: textAlign))
            .toList(),
      );
    }

    final cleaned = text.replaceAll(
      RegExp(r'[\u200e\u200f\u202a-\u202e\u2066-\u2069]'),
      '',
    );

    final List<pw.Widget> spans = [];
    final List<int> currentRun = [];
    bool? currentRunIsArabic;

    void commitRun() {
      if (currentRun.isEmpty) return;
      final runText = String.fromCharCodes(currentRun);
      if (currentRunIsArabic == true) {
        try {
          final reshaped = ArabicReshaper.instance.reshape(runText);
          spans.add(
            pw.Text(
              reshaped,
              style: style,
              textDirection: pw.TextDirection.rtl,
            ),
          );
        } catch (e) {
          spans.add(
            pw.Text(runText, style: style, textDirection: pw.TextDirection.rtl),
          );
        }
      } else {
        spans.add(
          pw.Text(
            runText,
            style: style.copyWith(
              font: (style.fontWeight == pw.FontWeight.bold)
                  ? pw.Font.helveticaBold()
                  : pw.Font.helvetica(),
            ),
            textDirection: pw.TextDirection.ltr,
          ),
        );
      }
      currentRun.clear();
    }

    for (int i = 0; i < cleaned.length; i++) {
      final charCode = cleaned.codeUnitAt(i);
      final char = cleaned[i];

      final isArabicChar =
          (charCode >= 0x0600 && charCode <= 0x06FF) ||
          (charCode >= 0x0750 && charCode <= 0x077F) ||
          (charCode >= 0x08A0 && charCode <= 0x08FF) ||
          (charCode >= 0xFB50 && charCode <= 0xFDFF) ||
          (charCode >= 0xFE70 && charCode <= 0xFEFF);

      bool isNeutral =
          char == ' ' ||
          char == '.' ||
          char == ',' ||
          char == ':' ||
          char == '-' ||
          char == '|' ||
          char == '(' ||
          char == ')' ||
          char == '#' ||
          char == '/' ||
          (charCode >= 0x30 && charCode <= 0x39);

      if (currentRunIsArabic == null) {
        currentRunIsArabic = isArabicChar;
        currentRun.add(charCode);
      } else {
        if (isNeutral) {
          currentRun.add(charCode);
        } else if (isArabicChar == currentRunIsArabic) {
          currentRun.add(charCode);
        } else {
          commitRun();
          currentRunIsArabic = isArabicChar;
          currentRun.add(charCode);
        }
      }
    }
    commitRun();

    if (spans.isEmpty) {
      return pw.Text('', style: style);
    }
    if (spans.length == 1) {
      return spans.first;
    }

    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Wrap(
        spacing: 0,
        runSpacing: 2,
        alignment: textAlign == pw.TextAlign.center
            ? pw.WrapAlignment.center
            : (textAlign == pw.TextAlign.left
                  ? pw.WrapAlignment.start
                  : pw.WrapAlignment.end),
        children: spans,
      ),
    );
  }

  static pw.Widget _receiptRowHelper(
    String label,
    String value, {
    double fontSize = 14,
  }) {
    final cleanLabel = _cleanAndShapeText(label);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '$cleanLabel:',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.right,
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: _buildBidiText(
                value,
                pw.TextStyle(fontSize: fontSize),
                textAlign: pw.TextAlign.left,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _getPaymentMethodArabicName(String? method) {
    switch (method) {
      case 'cash':
        return 'نقدي';
      case 'vodafone_cash':
        return 'فودافون كاش';
      case 'instapay':
        return 'InstaPay';
      case 'visa':
        return 'فيزا';
      default:
        return 'غير محدد';
    }
  }

  static Future<Uint8List> generateDailyClosurePdf(
    DateTime date,
    List<Ticket> tickets,
  ) async {
    final pdfTheme = await _getArabicTheme();
    final pdf = pw.Document();

    final Map<String, List<Ticket>> techGroups = {};
    for (var t in tickets) {
      final name = t.technicianName ?? 'غير محدد';
      techGroups.putIfAbsent(name, () => []).add(t);
    }

    // Calculate dynamic page height based on number of tickets & technicians to keep it on a single page
    final double estimatedHeightMm =
        125.0 + (tickets.length * 8.0) + (techGroups.keys.length * 9.0);

    final pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      estimatedHeightMm * PdfPageFormat.mm,
      marginLeft: 11 * PdfPageFormat.mm - 10,
      marginRight: 13 * PdfPageFormat.mm + 10,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 4 * PdfPageFormat.mm,
    );

    final dateStr = DateFormat('yyyy-MM-dd').format(date);

    double cashSum = 0;
    double vfCashSum = 0;
    double instapaySum = 0;
    double visaSum = 0;
    for (var t in tickets) {
      if (t.paymentMethod == 'vodafone_cash') {
        vfCashSum += t.cost;
      } else if (t.paymentMethod == 'instapay') {
        instapaySum += t.cost;
      } else if (t.paymentMethod == 'visa') {
        visaSum += t.cost;
      } else {
        cashSum += t.cost;
      }
    }

    double totalRevenue = tickets.fold(0.0, (sum, t) => sum + t.cost);
    double totalPartsCost = tickets.fold(0.0, (sum, t) => sum + t.partsCost);
    double totalNetProfit = totalRevenue - totalPartsCost;
    double totalTechEarnings = 0;
    for (var t in tickets) {
      final net = t.cost - t.partsCost;
      totalTechEarnings += net * (t.commissionRate / 100);
    }
    double totalStoreEarnings = totalNetProfit - totalTechEarnings;

    final List<pw.Widget> content = [];

    void addRtl(pw.Widget child) {
      content.add(
        pw.Directionality(textDirection: pw.TextDirection.rtl, child: child),
      );
    }

    // 1. Header
    addRtl(
      pw.Align(
        alignment: pw.Alignment.center,
        child: _buildBidiText(
          'EL ATTAR STORE',
          pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
    addRtl(
      pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text(
          _cleanAndShapeText('محلات العطار استور'),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
    addRtl(
      pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text(
          _cleanAndShapeText('تقرير تقفيل اليومية'),
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
    addRtl(
      pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text(
          _cleanAndShapeText('التاريخ: $dateStr'),
          style: const pw.TextStyle(fontSize: 8),
        ),
      ),
    );
    content.add(pw.SizedBox(height: 3));
    content.add(pw.Divider(thickness: 1));
    content.add(pw.SizedBox(height: 3));

    // 2. Receipts header
    addRtl(
      pw.Text(
        _cleanAndShapeText('الإيصالات (${tickets.length}):'),
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
    content.add(pw.SizedBox(height: 2));

    // 3. Ticket items
    for (var t in tickets) {
      final net = t.cost - t.partsCost;
      final techEarn = net * (t.commissionRate / 100);
      final techName = t.technicianName ?? "بدون";
      addRtl(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: _buildBidiText(
            '(${t.id})|${t.deviceModel}|${t.problem}|$techName\n كلف:${t.cost.toStringAsFixed(0)}|قطع:${t.partsCost.toStringAsFixed(0)}|فني:${techEarn.toStringAsFixed(0)}',
            pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.right,
          ),
        ),
      );
    }

    content.add(pw.SizedBox(height: 3));
    content.add(pw.Divider(thickness: 0.5));
    content.add(pw.SizedBox(height: 3));

    // 4. Tech summaries header
    addRtl(
      pw.Text(
        _cleanAndShapeText('ملخص الفنيين:'),
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
    content.add(pw.SizedBox(height: 2));

    // 5. Tech summaries
    for (var entry in techGroups.entries) {
      final techName = entry.key;
      final list = entry.value;
      double techRevenue = list.fold(0.0, (sum, t) => sum + t.cost);
      double techParts = list.fold(0.0, (sum, t) => sum + t.partsCost);
      double techEarn = 0;
      for (var t in list) {
        final net = t.cost - t.partsCost;
        techEarn += net * (t.commissionRate / 100);
      }
      double storeShare = (techRevenue - techParts) - techEarn;

      addRtl(
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildBidiText(
                'الفني: $techName (${list.length} أجهزة)',
                pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.right,
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(right: 6),
                child: _buildBidiText(
                  'المجموع: ${techRevenue.toStringAsFixed(0)} | قطع: ${techParts.toStringAsFixed(0)} | عمولة: ${techEarn.toStringAsFixed(0)} | للمحل: ${storeShare.toStringAsFixed(0)}',
                  const pw.TextStyle(fontSize: 7),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      );
    }

    content.add(pw.SizedBox(height: 3));
    content.add(pw.Divider(thickness: 0.5));
    content.add(pw.SizedBox(height: 3));

    // 6. Payment methods
    addRtl(
      pw.Text(
        _cleanAndShapeText('طرق الدفع:'),
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
    addRtl(
      _receiptRowHelper(
        'نقدي (كاش)',
        '${cashSum.toStringAsFixed(0)} ج.م',
        fontSize: 7.5,
      ),
    );
    addRtl(
      _receiptRowHelper(
        'فودافون كاش',
        '${vfCashSum.toStringAsFixed(0)} ج.م',
        fontSize: 7.5,
      ),
    );
    addRtl(
      _receiptRowHelper(
        'InstaPay',
        '${instapaySum.toStringAsFixed(0)} ج.م',
        fontSize: 7.5,
      ),
    );
    addRtl(
      _receiptRowHelper(
        'فيزا',
        '${visaSum.toStringAsFixed(0)} ج.م',
        fontSize: 7.5,
      ),
    );

    content.add(pw.SizedBox(height: 3));
    content.add(pw.Divider(thickness: 0.5));
    content.add(pw.SizedBox(height: 3));

    // 7. Totals
    addRtl(
      pw.Text(
        _cleanAndShapeText('الحساب الإجمالي:'),
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
    addRtl(
      _receiptRowHelper(
        'إجمالي الدخل الكلي',
        '${totalRevenue.toStringAsFixed(0)} ج.م',
        fontSize: 8,
      ),
    );
    addRtl(
      _receiptRowHelper(
        'إجمالي تكلفة قطع الغيار',
        '${totalPartsCost.toStringAsFixed(0)} ج.م',
        fontSize: 8,
      ),
    );
    addRtl(
      _receiptRowHelper(
        'إجمالي مستحقات الفنيين',
        '${totalTechEarnings.toStringAsFixed(0)} ج.م',
        fontSize: 8,
      ),
    );
    addRtl(
      _receiptRowHelper(
        'إجمالي صافي المحل',
        '${totalStoreEarnings.toStringAsFixed(0)} ج.م',
        fontSize: 8.5,
      ),
    );

    content.add(pw.SizedBox(height: 6));
    addRtl(
      pw.Align(
        alignment: pw.Alignment.center,
        child: pw.Text(
          _cleanAndShapeText('تم تقفيل اليومية بنجاح'),
          style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
    addRtl(
      pw.Align(
        alignment: pw.Alignment.center,
        child: _buildBidiText(
          'Developed By Eng:BELALZAGHL0L',
          const pw.TextStyle(fontSize: 6.5),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pdfTheme,
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: content,
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<Uint8List> generateSalesReceiptPdf(Sale sale) async {
    final pdfTheme = await _getArabicTheme();
    final pdf = pw.Document();

    pw.Widget receiptRow(String label, String value) {
      return _receiptRowHelper(label, value, fontSize: 10);
    }

    const pageFormat = PdfPageFormat(
      80 * PdfPageFormat.mm,
      double.infinity,
      marginLeft: 11 * PdfPageFormat.mm - 10,
      marginRight: 13 * PdfPageFormat.mm + 10,
      marginTop: 4 * PdfPageFormat.mm,
      marginBottom: 4 * PdfPageFormat.mm,
    );

    // QR Code generation (same as ticket receipt)
    final waPhone = '201000361006';
    pw.MemoryImage? qrImage;
    final String qrData =
        'https://wa.me/$waPhone?text=${Uri.encodeComponent("فاتورة بيع رقم: ${sale.id ?? ''}")}';

    try {
      final qrValidation = QrValidator.validate(
        data: qrData,
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
      );

      if (qrValidation.status == QrValidationStatus.valid) {
        final qrPainter = QrPainter.withQr(
          qr: qrValidation.qrCode!,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: ui.Color(0xFF000000),
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: ui.Color(0xFF000000),
          ),
          gapless: false,
        );

        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        const qrSize = 200.0;
        qrPainter.paint(canvas, const ui.Size(qrSize, qrSize));
        final img = await recorder.endRecording().toImage(
          qrSize.toInt(),
          qrSize.toInt(),
        );
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          qrImage = pw.MemoryImage(byteData.buffer.asUint8List());
        }
      }
    } catch (_) {}

    final dateStr = DateFormat('yyyy-MM-dd  HH:mm').format(sale.saleDate);
    final List items = jsonDecode(sale.itemsJson);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        theme: pdfTheme,
        build: (pw.Context ctx) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: _buildBidiText(
                    'EL ATTAR STORE',
                    pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'محلات العطار استور',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'فاتورة بيع منتجات',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 4),

                receiptRow('رقم الفاتورة', '#${sale.id ?? 'جديد'}'),
                receiptRow('التاريخ والوقت', dateStr),
                if (sale.customerName != null && sale.customerName!.isNotEmpty)
                  receiptRow('اسم العميل', sale.customerName!),
                if (sale.customerPhone != null &&
                    sale.customerPhone!.isNotEmpty)
                  receiptRow('رقم العميل', sale.customerPhone!),

                pw.SizedBox(height: 6),
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 4),
                pw.Text(
                  'المنتجات المباعة:',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),

                // Table of items
                ...items.map((item) {
                  final String name = item['name'] ?? '';
                  final int qty = item['quantity'] ?? 1;
                  final double price =
                      (item['price'] as num?)?.toDouble() ?? 0.0;
                  final double total = qty * price;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          flex: 3,
                          child: _buildBidiText(
                            name,
                            const pw.TextStyle(fontSize: 8.5),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                        pw.Expanded(
                          flex: 1,
                          child: pw.Text(
                            '${qty}x',
                            style: const pw.TextStyle(fontSize: 8.5),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            price.toStringAsFixed(1),
                            style: const pw.TextStyle(fontSize: 8.5),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Align(
                            alignment: pw.Alignment.centerLeft,
                            child: _buildBidiText(
                              '${total.toStringAsFixed(1)} ج.م',
                              pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.left,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                pw.SizedBox(height: 6),
                pw.Divider(thickness: 0.5),
                pw.SizedBox(height: 4),

                receiptRow(
                  'المجموع الفرعي',
                  '${sale.totalAmount.toStringAsFixed(2)} ج.م',
                ),
                if (sale.discount > 0)
                  receiptRow(
                    'الخصم',
                    '${sale.discount.toStringAsFixed(2)} ج.م',
                  ),
                receiptRow(
                  'الإجمالي النهائي',
                  '${sale.finalAmount.toStringAsFixed(2)} ج.م',
                ),
                receiptRow(
                  'طريقة الدفع',
                  _getPaymentMethodArabicName(sale.paymentMethod),
                ),

                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 6),

                if (qrImage != null)
                  pw.Center(child: pw.Image(qrImage, width: 110, height: 110))
                else
                  pw.Center(
                    child: pw.BarcodeWidget(
                      data: qrData,
                      barcode: pw.Barcode.qrCode(),
                      width: 110,
                      height: 110,
                      drawText: false,
                    ),
                  ),
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'SALE-${sale.id ?? "NEW"}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'شكراً لثقتكم بنا',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: _buildBidiText(
                    'Developed By Eng:BELALZAGHL0L',
                    const pw.TextStyle(fontSize: 7.5),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static Future<void> printSalesReceipt(Sale sale, {int copies = 1}) async {
    debugPrint('Auto Sales Receipt Print Started');
    try {
      final config = await PrinterSettingsService.load();
      final printer = await PrinterSettingsService.resolve(
        config.receiptPrinterName,
        'طابعة الفواتير',
      );

      debugPrint('Selected Printer: ${printer.name}');
      final bytes = await generateSalesReceiptPdf(sale);

      const pageFormat = PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginLeft: 11 * PdfPageFormat.mm - 10,
        marginRight: 13 * PdfPageFormat.mm + 10,
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
      );

      for (int i = 0; i < copies; i++) {
        debugPrint('Printing sale receipt copy ${i + 1} of $copies');
        final result = await Printing.directPrintPdf(
          printer: printer,
          onLayout: (_) async => bytes,
          format: pageFormat,
        );

        if (!result) {
          throw Exception('فشلت طباعة الفاتورة على الطابعة ${printer.name}');
        }
      }
    } catch (e) {
      debugPrint('Auto sales receipt print failed: $e');
      rethrow;
    }
  }

  static Future<void> printDailyClosureReport(
    DateTime date,
    List<Ticket> tickets,
  ) async {
    debugPrint('Daily Closure Print Started');
    try {
      final config = await PrinterSettingsService.load();
      final printer = await PrinterSettingsService.resolve(
        config.receiptPrinterName,
        'طابعة الفواتير',
      );

      final bytes = await generateDailyClosurePdf(date, tickets);

      final Map<String, List<Ticket>> techGroups = {};
      for (var t in tickets) {
        final name = t.technicianName ?? 'غير محدد';
        techGroups.putIfAbsent(name, () => []).add(t);
      }
      final double estimatedHeightMm =
          125.0 + (tickets.length * 8.0) + (techGroups.keys.length * 9.0);

      final pageFormat = PdfPageFormat(
        80 * PdfPageFormat.mm,
        estimatedHeightMm * PdfPageFormat.mm,
        marginLeft: 11 * PdfPageFormat.mm - 10,
        marginRight: 13 * PdfPageFormat.mm + 10,
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
      );

      final result = await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        format: pageFormat,
      );

      if (!result) {
        throw Exception('فشلت طباعة تقرير التقفيل على الطابعة ${printer.name}');
      }
    } catch (e) {
      debugPrint('Daily Closure Print Failed: $e');
      rethrow;
    }
  }
}
