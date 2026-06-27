// lib/views/deferred_payments_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../printer_settings_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class DeferredPaymentsView extends StatefulWidget {
  const DeferredPaymentsView({super.key});

  @override
  State<DeferredPaymentsView> createState() => _DeferredPaymentsViewState();
}

class _DeferredPaymentsViewState extends State<DeferredPaymentsView> {
  List<DeferredPayment> _payments = [];
  List<DeferredPayment> _filteredPayments = [];
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      _payments = await DatabaseHelper.loadDeferredPayments();
      _filterItems();
    } catch (e) {
      debugPrint('Error loading deferred payments: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterItems() {
    setState(() {
      _filteredPayments = _payments.where((item) {
        return item.customerName
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            item.customerPhone.contains(_searchQuery);
      }).toList();
    });
  }

  void _showAddDebtDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final totalController = TextEditingController();
    final paidController = TextEditingController(text: '0.0');
    final notesController = TextEditingController();

    String selectedType = 'device'; // 'device', 'accessory', 'repair', 'other'
    DateTime? dueDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final textColor = AppTheme.text(context);
          final primaryGold = const Color(0xFFD4AF37);

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('➕ تسجيل مديونية عميل جديدة',
                style: TextStyle(
                    color: primaryGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: textColor),
                      decoration:
                          const InputDecoration(labelText: 'اسم العميل *'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: textColor),
                      decoration:
                          const InputDecoration(labelText: 'رقم الهاتف *'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: totalController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                                labelText: 'إجمالي المديونية (ج.م) *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: paidController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                                labelText: 'المقدم المدفوع حالياً (ج.م)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedType,
                            dropdownColor: AppTheme.cardBg(context),
                            style: TextStyle(color: textColor, fontSize: 16),
                            decoration: const InputDecoration(
                                labelText: 'سبب المديونية *'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'device', child: Text('جهاز موبايل')),
                              DropdownMenuItem(
                                  value: 'accessory', child: Text('إكسسوارات')),
                              DropdownMenuItem(
                                  value: 'repair', child: Text('صيانة')),
                              DropdownMenuItem(
                                  value: 'other', child: Text('أخرى')),
                            ],
                            onChanged: (val) {
                              setDialogState(() {
                                selectedType = val!;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dueDate == null
                                      ? 'تاريخ الاستحقاق'
                                      : DateFormat('yyyy/MM/dd')
                                          .format(dueDate!),
                                  style:
                                      TextStyle(color: textColor, fontSize: 14),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.calendar_month,
                                    color: primaryGold),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime.now()
                                        .add(const Duration(days: 30)),
                                    firstDate: DateTime.now(),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 365)),
                                    locale: const Locale('ar', 'EG'),
                                  );
                                  if (picked != null) {
                                    setDialogState(() {
                                      dueDate = picked;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(
                          labelText: 'ملاحظات وتفاصيل الديون'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إلغاء',
                    style: TextStyle(
                        color: AppTheme.textMuted(context), fontSize: 16)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGold,
                    foregroundColor: const Color(0xFF1A2A3A)),
                onPressed: () async {
                  final name = nameController.text.trim();
                  final phone = phoneController.text.trim();
                  final total =
                      double.tryParse(totalController.text.trim()) ?? 0.0;
                  final paid =
                      double.tryParse(paidController.text.trim()) ?? 0.0;

                  if (name.isEmpty || phone.isEmpty || total <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content:
                            Text('⚠️ يرجى تعبئة الحقول الأساسية المطلوبة')));
                    return;
                  }

                  final remaining = total - paid;

                  final newDp = DeferredPayment(
                    customerName: name,
                    customerPhone: phone,
                    totalAmount: total,
                    paidAmount: paid,
                    remainingAmount: remaining,
                    dueDate: dueDate != null
                        ? DateFormat('yyyy-MM-dd').format(dueDate!)
                        : null,
                    notes: notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                    transactionType: selectedType,
                    createdDate:
                        DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                  );

                  final id = await DatabaseHelper.saveDeferredPayment(newDp);

                  if (paid > 0.0) {
                    final history = DeferredPaymentHistory(
                      deferredId: id,
                      amountPaid: paid,
                      paymentDate:
                          DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
                      notes: 'دفعة مقدمة عند تسجيل المديونية',
                    );
                    await DatabaseHelper.addDeferredPaymentHistory(history);
                  }

                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                },
                child: const Text('حفظ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPaymentHistoryDialog(DeferredPayment dp) async {
    List<DeferredPaymentHistory> history = [];
    bool isHistLoading = true;
    final paymentController = TextEditingController();
    final noteController = TextEditingController();

    Future<void> reloadHistory(Function setDialogState) async {
      try {
        final data = await DatabaseHelper.loadDeferredPaymentHistory(dp.id!);
        setDialogState(() {
          history = data;
          isHistLoading = false;
        });
      } catch (e) {
        debugPrint('Error: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final textColor = AppTheme.text(context);
          final primaryGold = const Color(0xFFD4AF37);
          final textMuted = AppTheme.textMuted(context);

          if (isHistLoading) {
            reloadHistory(setDialogState);
          }

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('💰 كشف سداد الحساب: ${dp.customerName}',
                style: TextStyle(
                    color: primaryGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Debt Summary
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: primaryGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المطلوب: ${dp.totalAmount} ج.م',
                            style: TextStyle(color: textColor, fontSize: 14)),
                        Text('المدفوع: ${dp.paidAmount} ج.م',
                            style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        Text('المتبقي: ${dp.remainingAmount} ج.م',
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Repay form
                  if (dp.remainingAmount > 0.0) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: paymentController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                                labelText: 'قيمة الدفعة المسددة حالياً *'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: noteController,
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                                labelText: 'ملاحظة/تأكيد سداد الدفعة'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: primaryGold,
                              foregroundColor: const Color(0xFF1A2A3A)),
                          onPressed: () async {
                            final val = double.tryParse(
                                    paymentController.text.trim()) ??
                                0.0;
                            if (val <= 0.0 || val > dp.remainingAmount) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          '⚠️ يرجى إدخال مبلغ صحيح لا يتجاوز الدين')));
                              return;
                            }
                            final h = DeferredPaymentHistory(
                              deferredId: dp.id!,
                              amountPaid: val,
                              paymentDate: DateFormat('yyyy-MM-dd HH:mm')
                                  .format(DateTime.now()),
                              notes: noteController.text.trim().isEmpty
                                  ? null
                                  : noteController.text.trim(),
                            );
                            await DatabaseHelper.addDeferredPaymentHistory(h);

                            // reload local copy of dp
                            final list =
                                await DatabaseHelper.loadDeferredPayments();
                            final fresh = list.firstWhere((p) => p.id == dp.id);

                            paymentController.clear();
                            noteController.clear();

                            setDialogState(() {
                              dp.paidAmount = fresh.paidAmount;
                              dp.remainingAmount = fresh.remainingAmount;
                              isHistLoading = true; // force refresh
                            });

                            _loadData();
                          },
                          child: const Text('سداد'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                  ],

                  // History list
                  Text('سجل الدفعات المسددة:',
                      style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
                  const SizedBox(height: 6),
                  Expanded(
                    child: isHistLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFFD4AF37))))
                        : history.isEmpty
                            ? Center(
                                child: Text('لا توجد سحوبات/دفعات مسجلة مسبقاً',
                                    style: TextStyle(color: textMuted)))
                            : ListView.separated(
                                itemCount: history.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(),
                                itemBuilder: (context, index) {
                                  final h = history[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                        '+ ${h.amountPaid.toStringAsFixed(2)} ج.م',
                                        style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        h.notes ?? 'دفع قسط مديونية عميل',
                                        style: TextStyle(
                                            color: textMuted, fontSize: 13)),
                                    trailing: Text(h.paymentDate.split(' ')[0],
                                        style: TextStyle(
                                            color: textMuted, fontSize: 12)),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('إغلاق',
                    style: TextStyle(
                        color: AppTheme.textMuted(context), fontSize: 16)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printCustomerStatement(DeferredPayment dp) async {
    try {
      final config = await PrinterSettingsService.load();
      final printer = await PrinterSettingsService.resolve(
          config.receiptPrinterName, 'طابعة الفواتير');

      final pdfTheme = await printServiceGetArabicTheme();
      final pdf = pw.Document();

      final history = await DatabaseHelper.loadDeferredPaymentHistory(dp.id!);

      final double estimatedHeightMm = 110.0 + (history.length * 8.0);
      final pageFormat = PdfPageFormat(
        80 * PdfPageFormat.mm,
        estimatedHeightMm * PdfPageFormat.mm,
        marginLeft: 4 * PdfPageFormat.mm,
        marginRight: 4 * PdfPageFormat.mm,
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 4 * PdfPageFormat.mm,
      );

      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

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
                  pw.Text('محلات العطار استور',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center),
                  pw.Text('كشف حساب مديونيات العميل الآجل',
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center),
                  pw.Text('التاريخ: $dateStr',
                      style: const pw.TextStyle(fontSize: 8),
                      textAlign: pw.TextAlign.center),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 4),
                  _receiptRowHelper('العميل', dp.customerName),
                  _receiptRowHelper('الهاتف', dp.customerPhone),
                  _receiptRowHelper('حالة الحساب',
                      dp.remainingAmount == 0 ? 'مغلق (خالص)' : 'نشط (متبقي)'),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 4),
                  _receiptRowHelper('إجمالي الديون',
                      '${dp.totalAmount.toStringAsFixed(2)} ج.م'),
                  _receiptRowHelper('إجمالي السداد',
                      '${dp.paidAmount.toStringAsFixed(2)} ج.م'),
                  _receiptRowHelper('الصافي المتبقي للتحصيل',
                      '${dp.remainingAmount.toStringAsFixed(2)} ج.م'),
                  if (dp.dueDate != null)
                    _receiptRowHelper('تاريخ الاستحقاق', dp.dueDate!),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 4),
                  pw.Text('سجل التحصيل والدفعات:',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                  ...history.map((h) => pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('+ ${h.amountPaid.toStringAsFixed(0)} ج.م',
                              style: pw.TextStyle(
                                  fontSize: 7.5,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text(h.notes ?? 'سداد قسط',
                              style: const pw.TextStyle(fontSize: 7.5)),
                          pw.Text(h.paymentDate.split(' ')[0],
                              style: const pw.TextStyle(fontSize: 7.5)),
                        ],
                      )),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 6),
                  pw.Text('العطار استور - تقرير حسابات الديون الموثق',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center),
                  pw.Text('Developed By Eng:BELALZAGHL0L',
                      style: const pw.TextStyle(fontSize: 6),
                      textAlign: pw.TextAlign.center),
                ],
              ),
            );
          },
        ),
      );

      final bytes = await pdf.save();
      await Printing.directPrintPdf(
        printer: printer,
        onLayout: (_) async => bytes,
        format: pageFormat,
      );
    } catch (e) {
      debugPrint('Failed to print customer statement: $e');
    }
  }

  pw.Widget _receiptRowHelper(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('$label:',
              style:
                  pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8.5)),
        ],
      ),
    );
  }

  static pw.ThemeData? _cachedTheme;
  Future<pw.ThemeData> printServiceGetArabicTheme() async {
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
        } catch (_) {}
      }
    }
    regular ??= pw.Font.helvetica();
    bold ??= pw.Font.helveticaBold();
    _cachedTheme = pw.ThemeData.withFont(base: regular, bold: bold);
    return _cachedTheme!;
  }

  @override
  Widget build(BuildContext context) {
    final textColor = AppTheme.text(context);
    final textMuted = AppTheme.textMuted(context);
    final primaryGold = const Color(0xFFD4AF37);

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💰 التعامل الآجل ومتابعة ديون العملاء',
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'تسجيل حسابات البيع الآجل للعملاء (أقساط، صيانة آجلة، مبيعات هواتف بالتقسيط) وتتبع التواريخ وطباعة كشوفات الحساب',
                    style: TextStyle(fontSize: 15, color: textMuted),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
                onPressed: _showAddDebtDialog,
                icon: const Icon(Icons.add_card_rounded, size: 22),
                label: const Text('تسجيل مديونية عميل',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Card
          Card(
            color: AppTheme.cardBg(context),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                style: TextStyle(color: textColor, fontSize: 16),
                decoration: InputDecoration(
                  hintText:
                      'البحث باسم العميل أو رقم الهاتف المسجل للدائنين...',
                  prefixIcon: Icon(Icons.search, color: primaryGold),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _filterItems();
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Debts Table
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFFD4AF37))))
                : _filteredPayments.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.monetization_on_outlined,
                                size: 64, color: textMuted),
                            const SizedBox(height: 16),
                            Text('لا توجد مديونيات آجلة مسجلة للعملاء حالياً',
                                style:
                                    TextStyle(fontSize: 18, color: textMuted)),
                          ],
                        ),
                      )
                    : Card(
                        color: AppTheme.cardBg(context),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: DataTable(
                            headingTextStyle: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: primaryGold,
                                fontSize: 16),
                            dataTextStyle: TextStyle(
                                fontFamily: 'Cairo',
                                color: textColor,
                                fontSize: 15),
                            columns: const [
                              DataColumn(label: Text('العميل')),
                              DataColumn(label: Text('رقم الهاتف')),
                              DataColumn(label: Text('إجمالي المديونية')),
                              DataColumn(label: Text('المسدد حتى الآن')),
                              DataColumn(label: Text('الصافي المتبقي')),
                              DataColumn(label: Text('تاريخ الاستحقاق')),
                              DataColumn(label: Text('الحالة')),
                              DataColumn(label: Text('خيارات')),
                            ],
                            rows: _filteredPayments.map((item) {
                              final isOverdue = item.dueDate != null &&
                                  DateTime.parse(item.dueDate!)
                                      .isBefore(DateTime.now()) &&
                                  item.remainingAmount > 0;

                              return DataRow(cells: [
                                DataCell(Text(item.customerName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold))),
                                DataCell(Text(item.customerPhone)),
                                DataCell(Text(
                                    '${item.totalAmount.toStringAsFixed(2)} ج.م')),
                                DataCell(Text(
                                    '${item.paidAmount.toStringAsFixed(2)} ج.م',
                                    style:
                                        const TextStyle(color: Colors.green))),
                                DataCell(
                                  Text(
                                    '${item.remainingAmount.toStringAsFixed(2)} ج.م',
                                    style: TextStyle(
                                      color: item.remainingAmount > 0
                                          ? Colors.redAccent
                                          : Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                DataCell(Text(item.dueDate ?? 'مفتوح')),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: item.remainingAmount == 0
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : (isOverdue
                                              ? Colors.red
                                                  .withValues(alpha: 0.15)
                                              : Colors.orange
                                                  .withValues(alpha: 0.15)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      item.remainingAmount == 0
                                          ? 'سداد كامل'
                                          : (isOverdue
                                              ? 'متأخر سداد'
                                              : 'قيد الانتظار'),
                                      style: TextStyle(
                                        color: item.remainingAmount == 0
                                            ? Colors.green
                                            : (isOverdue
                                                ? Colors.red
                                                : Colors.orange),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.payment,
                                            color: primaryGold, size: 20),
                                        onPressed: () =>
                                            _showPaymentHistoryDialog(item),
                                        tooltip: 'سداد دفعات / كشف',
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.print,
                                            color: Colors.tealAccent, size: 20),
                                        onPressed: () =>
                                            _printCustomerStatement(item),
                                        tooltip: 'طباعة كشف حساب',
                                      ),
                                    ],
                                  ),
                                ),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
