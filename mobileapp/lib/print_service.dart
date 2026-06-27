import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:arabic_reshaper/arabic_reshaper.dart';

import 'models.dart';
import 'database_helper.dart';
import 'printer_settings_service.dart';


class PrintService {
  static pw.ThemeData? _cachedTheme;

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
            textDirection: pw.TextDirection.ltr,
            child: pw.Padding(
              padding: pw.EdgeInsets.only(
                right: -labelOffsetX * PdfPageFormat.mm,
                top: labelOffsetY * PdfPageFormat.mm,
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Container(
                    alignment: pw.Alignment.center,
                    width: 10 * PdfPageFormat.mm,
                    child: pw.Transform.rotate(
                      angle: -1.57079632679,
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

  static Future<Uint8List> generateReceiptPdf(
    Ticket ticket, {
    bool isDelivery = false,
    double? overrideCost,
    String? overridePaymentMethod,
    String? overridePaymentDetails,
  }) async {
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

    debugPrint('QR Generation Started');

    final rawPhone =
        (ticket.technicianPhone != null &&
            ticket.technicianPhone!.trim().isNotEmpty)
        ? ticket.technicianPhone!.trim()
        : '201030003636';

    String waPhone = rawPhone.replaceAll(RegExp(r'[^\d]'), '');
    if (waPhone.startsWith('0')) waPhone = '2$waPhone';
    if (!waPhone.startsWith('20')) waPhone = '20$waPhone';

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
            break;
          }
        }
      } catch (_) {}
    }

    final dateStr = DateFormat('yyyy-MM-dd  HH:mm').format(ticket.receivedDate);

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
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: _buildBidiText(
                    'EL ATTAR STORE',
                    pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
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
                  ),
                ),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    _cleanAndShapeText(isDelivery
                        ? 'إيصال تسليم صيانة جهاز'
                        : 'إيصال استلام جهاز صيانة'),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 4),

                receiptRow('رقم الايصال', '#${ticket.id}'),
                if (ticket.complaintNumber != null &&
                    ticket.complaintNumber!.isNotEmpty)
                  receiptRow('تاريخ الاستلام', dateStr),
                if (isDelivery)
                  receiptRow(
                    'تاريخ التسليم',
                    DateFormat(
                      'yyyy-MM-dd  HH:mm',
                    ).format(ticket.deliveryDate ?? DateTime.now()),
                  ),
                receiptRow('اسم العميل', ticket.customerName),
                receiptRow('رقم العميل', ticket.customerPhone),
                receiptRow('الجهاز', ticket.deviceModel),
                receiptRow('العطل', ticket.problem),
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
                ],
                if (ticket.deviceCondition.trim().isNotEmpty)
                  receiptRow('حالة الجهاز', ticket.deviceCondition),
                if (ticket.expectedDelivery != null &&
                    ticket.expectedDelivery!.trim().isNotEmpty)
                  receiptRow('توقيت التسليم', ticket.expectedDelivery!),
                if (ticket.technicianName != null &&
                    ticket.technicianName!.isNotEmpty)
                  receiptRow('الفني المسؤول', ticket.technicianName!),
                if (ticket.technicianPhone != null &&
                    ticket.technicianPhone!.isNotEmpty)
                  receiptRow('هاتف الفني', ticket.technicianPhone!),
                pw.SizedBox(height: 6),
                pw.Divider(thickness: 1),
                pw.SizedBox(height: 6),

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
                            barcode: pw.Barcode.qrCode(),
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
                  child: pw.Text(
                    'RECEIPT-${ticket.id}',
                    style: const pw.TextStyle(fontSize: 9),
                    textDirection: pw.TextDirection.ltr,
                  ),
                ),
                if (ticket.complaintNumber != null &&
                    ticket.complaintNumber!.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  receiptRow(
                    'رقم الشكاوى',
                    ticket.complaintNumber?.trim().toUpperCase() == 'Y9S'
                        ? DatabaseHelper.complaintNumber
                        : ticket.complaintNumber!,
                  ),
                ],
                pw.SizedBox(height: 8),
                pw.Align(
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    _cleanAndShapeText('شكراً لثقتكم بنا'),
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
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

  static Future<void> printLabel(Ticket ticket) async {
    try {
      // Try direct print to configured printer
      final config = await PrinterSettingsService.load();
      if (config.labelPrinterName != null &&
          config.labelPrinterName!.trim().isNotEmpty) {
        try {
          final printer = await PrinterSettingsService.resolve(
            config.labelPrinterName,
            'طابعة الملصقات',
          );
          final bytes = await generateLabelPdf(ticket);
          const pageFormat = PdfPageFormat(
            62 * PdfPageFormat.mm,
            29 * PdfPageFormat.mm,
            marginAll: 1 * PdfPageFormat.mm,
          );
          final result = await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) async => bytes,
            format: pageFormat,
          );
          debugPrint(
            'Label direct print result: ${result ? "success" : "failed"}',
          );
          if (result) return; // success, done
        } catch (resolveError) {
          debugPrint(
            'Configured printer not available, falling back to system dialog: $resolveError',
          );
        }
      }

      // Fallback: show system print dialog (works on Android & desktop)
      final bytes = await generateLabelPdf(ticket);
      const pageFormat = PdfPageFormat(
        62 * PdfPageFormat.mm,
        29 * PdfPageFormat.mm,
        marginAll: 1 * PdfPageFormat.mm,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: pageFormat,
      );
    } catch (e) {
      debugPrint('Auto label print failed: $e');
      rethrow;
    }
  }

  static Future<void> printReceipt(
    Ticket ticket, {
    bool isDelivery = false,
    double? overrideCost,
    String? overridePaymentMethod,
    String? overridePaymentDetails,
    int copies = 1,
  }) async {
    try {
      // Try direct print to configured printer
      final config = await PrinterSettingsService.load();
      Printer? printer;
      bool useDirectPrint = false;

      if (config.receiptPrinterName != null &&
          config.receiptPrinterName!.trim().isNotEmpty) {
        try {
          printer = await PrinterSettingsService.resolve(
            config.receiptPrinterName,
            'طابعة الفواتير',
          );
          useDirectPrint = true;
        } catch (resolveError) {
          debugPrint(
            'Configured receipt printer not available, falling back to system dialog: $resolveError',
          );
        }
      }

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

      for (int i = 0; i < copies; i++) {
        if (useDirectPrint && printer != null) {
          final result = await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) async => bytes,
            format: pageFormat,
          );
          debugPrint(
            'Receipt direct print copy ${i + 1} result: ${result ? "success" : "failed"}',
          );
          if (!result) {
            // If direct print failed, fall back to system dialog for remaining copies
            debugPrint('Direct print failed, falling back to system dialog');
            await Printing.layoutPdf(
              onLayout: (_) async => bytes,
              format: pageFormat,
            );
          }
        } else {
          await Printing.layoutPdf(
            onLayout: (_) async => bytes,
            format: pageFormat,
          );
        }
      }
    } catch (e) {
      debugPrint('Auto receipt print failed: $e');
      rethrow;
    }
  }

  static Future<pw.ThemeData> _getArabicTheme() async {
    if (_cachedTheme != null) return _cachedTheme!;

    pw.Font? regular;
    pw.Font? bold;

    // 1) Try bundled assets first (works on mobile & desktop)
    try {
      final regData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');
      regular = pw.Font.ttf(regData);
      bold = pw.Font.ttf(boldData);
      debugPrint('✅ Loaded Cairo Arabic font from assets.');
    } catch (e) {
      debugPrint('⚠️ Failed to load Cairo font from assets: $e');
    }

    // 2) Fallback: download Cairo from GitHub (like desktop does)
    if (regular == null || bold == null) {
      try {
        final client = HttpClient();
        try {
          final regReq = await client.getUrl(
            Uri.parse(
              'https://cdn.jsdelivr.net/fontsource/fonts/cairo@latest/arabic-400-normal.ttf',
            ),
          );
          final regRes = await regReq.close();
          final boldReq = await client.getUrl(
            Uri.parse(
              'https://cdn.jsdelivr.net/fontsource/fonts/cairo@latest/arabic-700-normal.ttf',
            ),
          );
          final boldRes = await boldReq.close();
          if (regRes.statusCode == 200 && boldRes.statusCode == 200) {
            final regBytes = await regRes.fold<List<int>>(
              [],
              (prev, chunk) => prev..addAll(chunk),
            );
            final boldBytes = await boldRes.fold<List<int>>(
              [],
              (prev, chunk) => prev..addAll(chunk),
            );
            regular = pw.Font.ttf(
              Uint8List.fromList(regBytes).buffer.asByteData(),
            );
            bold = pw.Font.ttf(
              Uint8List.fromList(boldBytes).buffer.asByteData(),
            );
            debugPrint('✅ Loaded Cairo Arabic font from GitHub (fallback).');
          }
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('⚠️ Dynamic Cairo download failed: $e');
      }
    }

    // 3) Ultimate fallback – Helvetica (no Arabic support, but won't crash)
    regular ??= pw.Font.helvetica();
    bold ??= pw.Font.helveticaBold();
    if (regular == pw.Font.helvetica()) {
      debugPrint(
        '⚠️ Using Helvetica fallback — Arabic text may show as squares!',
      );
    }

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

  static pw.Widget _buildBidiText(String text, pw.TextStyle style, {pw.TextAlign textAlign = pw.TextAlign.right}) {
    if (text.isEmpty) {
      return pw.Text('', style: style);
    }

    if (text.contains('\n')) {
      final lines = text.split('\n');
      return pw.Column(
        crossAxisAlignment: textAlign == pw.TextAlign.center
            ? pw.CrossAxisAlignment.center
            : (textAlign == pw.TextAlign.left ? pw.CrossAxisAlignment.start : pw.CrossAxisAlignment.end),
        children: lines.map((line) => _buildBidiText(line, style, textAlign: textAlign)).toList(),
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
            pw.Text(
              runText,
              style: style,
              textDirection: pw.TextDirection.rtl,
            ),
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
      
      final isArabicChar = (charCode >= 0x0600 && charCode <= 0x06FF) ||
                           (charCode >= 0x0750 && charCode <= 0x077F) ||
                           (charCode >= 0x08A0 && charCode <= 0x08FF) ||
                           (charCode >= 0xFB50 && charCode <= 0xFDFF) ||
                           (charCode >= 0xFE70 && charCode <= 0xFEFF);
                           
      bool isNeutral = char == ' ' || 
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
            : (textAlign == pw.TextAlign.left ? pw.WrapAlignment.start : pw.WrapAlignment.end),
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

    addRtl(
      pw.Text(
        _cleanAndShapeText('الإيصالات (${tickets.length}):'),
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
    content.add(pw.SizedBox(height: 2));

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

    addRtl(
      pw.Text(
        _cleanAndShapeText('ملخص الفنيين:'),
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      ),
    );
    content.add(pw.SizedBox(height: 2));

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
                pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                ),
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

  static Future<void> printDailyClosureReport(
    DateTime date,
    List<Ticket> tickets,
  ) async {
    try {
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

      // Try direct print to configured printer, fallback to system dialog
      final config = await PrinterSettingsService.load();
      if (config.receiptPrinterName != null &&
          config.receiptPrinterName!.trim().isNotEmpty) {
        try {
          final printer = await PrinterSettingsService.resolve(
            config.receiptPrinterName,
            'طابعة الفواتير',
          );
          final result = await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) async => bytes,
            format: pageFormat,
          );
          debugPrint(
            'Daily closure direct print result: ${result ? "success" : "failed"}',
          );
          if (result) return;
        } catch (resolveError) {
          debugPrint(
            'Configured printer not available, falling back to system dialog: $resolveError',
          );
        }
      }

      // Fallback: system print dialog
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        format: pageFormat,
      );
    } catch (e) {
      debugPrint('Daily Closure Print Failed: $e');
      rethrow;
    }
  }
}
