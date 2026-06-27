// lib/views/suppliers_view.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../platform_stub.dart' if (dart.library.io) 'dart:io';
import '../database_helper.dart';
import '../models.dart';
import '../main.dart';
import '../printer_settings_service.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../widgets/skeleton_loading.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/custom_toast.dart';

class SuppliersView extends StatefulWidget {
  const SuppliersView({super.key});

  @override
  State<SuppliersView> createState() => _SuppliersViewState();
}

class _SuppliersViewState extends State<SuppliersView> {
  List<Supplier> _suppliers = [];
  List<SupplierDebt> _debts = [];
  List<SupplierDebt> _filteredDebts = [];

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
      _suppliers = await DatabaseHelper.loadSuppliers();
      _debts = await DatabaseHelper.loadSupplierDebts();
      _filterItems();
    } catch (e) {
      debugPrint('Error loading supplier data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterItems() {
    setState(() {
      _filteredDebts = _debts.where((item) {
        return item.supplierName.toLowerCase().contains(
          _searchQuery.toLowerCase(),
        );
      }).toList();
    });
  }

  void _showAddSupplierDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '➕ إضافة مورد جديد بالنظام',
          style: TextStyle(
            color: Color(0xFFD4AF37),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: TextStyle(color: AppTheme.text(context)),
              decoration: const InputDecoration(
                labelText: 'اسم الشركة / المورد *',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(color: AppTheme.text(context)),
              decoration: const InputDecoration(labelText: 'رقم الهاتف'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: addressController,
              style: TextStyle(color: AppTheme.text(context)),
              decoration: const InputDecoration(labelText: 'العنوان أو الشركة'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'إلغاء',
              style: TextStyle(
                color: AppTheme.textMuted(context),
                fontSize: 16,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: const Color(0xFF1A2A3A),
            ),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                CustomToast.show(
                  context,
                  message: '⚠️ يرجى إدخال اسم المورد',
                  type: ToastType.warning,
                );
                return;
              }
              final s = Supplier(
                name: name,
                phone: phoneController.text.trim().isEmpty
                    ? null
                    : phoneController.text.trim(),
                address: addressController.text.trim().isEmpty
                    ? null
                    : addressController.text.trim(),
              );
              await DatabaseHelper.saveSupplier(s);
              if (context.mounted) Navigator.pop(context);
              _loadData();
            },
            child: const Text(
              'حفظ',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddManualDebtDialog() {
    if (_suppliers.isEmpty) {
      CustomToast.show(
        context,
        message: '⚠️ يرجى تسجيل مورد واحد على الأقل أولاً',
        type: ToastType.warning,
      );
      return;
    }

    Supplier? selectedSupplier = _suppliers.first;
    final totalController = TextEditingController();
    final paidController = TextEditingController(text: '0.0');
    final notesController = TextEditingController();
    DateTime? dueDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final textColor = AppTheme.text(context);
          final primaryGold = const Color(0xFFD4AF37);

          return AlertDialog(
            backgroundColor: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '➕ تسجيل مديونية مورد يدوياً',
              style: TextStyle(
                color: primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<Supplier>(
                      initialValue: selectedSupplier,
                      dropdownColor: AppTheme.cardBg(context),
                      style: TextStyle(color: textColor, fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'اختر المورد المستحق *',
                      ),
                      items: _suppliers
                          .map(
                            (s) =>
                                DropdownMenuItem(value: s, child: Text(s.name)),
                          )
                          .toList(),
                      onChanged: (val) {
                        setDialogState(() {
                          selectedSupplier = val!;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: totalController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                              labelText: 'قيمة مديونية الفاتورة *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: paidController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                              labelText: 'الدفعة المسددة للمورد',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dueDate == null
                                ? 'تاريخ استحقاق الدين'
                                : DateFormat('yyyy/MM/dd').format(dueDate!),
                            style: TextStyle(color: textColor, fontSize: 15),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.calendar_month, color: primaryGold),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(
                                const Duration(days: 30),
                              ),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
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
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      style: TextStyle(color: textColor),
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات وتفاصيل الفاتورة',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'إلغاء',
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 16,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGold,
                  foregroundColor: const Color(0xFF1A2A3A),
                ),
                onPressed: () async {
                  final total =
                      double.tryParse(totalController.text.trim()) ?? 0.0;
                  final paid =
                      double.tryParse(paidController.text.trim()) ?? 0.0;

                  if (total <= 0) {
                    CustomToast.show(
                      context,
                      message: '⚠️ يرجى إدخال قيمة صحيحة للفتورة',
                      type: ToastType.warning,
                    );
                    return;
                  }

                  final remaining = total - paid;

                  final sd = SupplierDebt(
                    supplierId: selectedSupplier!.id!,
                    supplierName: selectedSupplier!.name,
                    totalAmount: total,
                    paidAmount: paid,
                    remainingAmount: remaining,
                    dueDate: dueDate != null
                        ? DateFormat('yyyy-MM-dd').format(dueDate!)
                        : null,
                    notes: notesController.text.trim().isEmpty
                        ? 'فاتورة يدوية'
                        : notesController.text.trim(),
                    createdDate: DateFormat(
                      'yyyy-MM-dd HH:mm',
                    ).format(DateTime.now()),
                  );

                  final id = await DatabaseHelper.saveSupplierDebt(sd);

                  if (paid > 0.0) {
                    final h = SupplierPaymentHistory(
                      debtId: id,
                      amountPaid: paid,
                      paymentDate: DateFormat(
                        'yyyy-MM-dd HH:mm',
                      ).format(DateTime.now()),
                      notes: 'دفعة مسددة عند التسجيل اليدوي',
                    );
                    await DatabaseHelper.addSupplierPaymentHistory(h);
                  }

                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                },
                child: const Text(
                  'حفظ',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRepaymentHistoryDialog(SupplierDebt sd) async {
    List<SupplierPaymentHistory> history = [];
    bool isHistLoading = true;
    final paymentController = TextEditingController();
    final noteController = TextEditingController();

    Future<void> reloadHistory(Function setDialogState) async {
      try {
        final data = await DatabaseHelper.loadSupplierPaymentHistory(sd.id!);
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '💸 سداد دفعات للمورد: ${sd.supplierName}',
              style: TextStyle(
                color: primaryGold,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Debt summary
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryGold.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'الفاتورة: ${sd.totalAmount} ج.م',
                          style: TextStyle(color: textColor, fontSize: 14),
                        ),
                        Text(
                          'المسدد: ${sd.paidAmount} ج.م',
                          style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'المتبقي للمورد: ${sd.remainingAmount} ج.م',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Pay supplier form
                  if (sd.remainingAmount > 0.0) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: paymentController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                              labelText: 'قيمة المبلغ المسدد للمورد *',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: noteController,
                            style: TextStyle(color: textColor),
                            decoration: const InputDecoration(
                              labelText: 'ملاحظة سداد للمورد',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGold,
                            foregroundColor: const Color(0xFF1A2A3A),
                          ),
                          onPressed: () async {
                            final val =
                                double.tryParse(
                                  paymentController.text.trim(),
                                ) ??
                                0.0;
                            if (val <= 0.0 || val > sd.remainingAmount) {
                              CustomToast.show(
                                context,
                                message: '⚠️ يرجى إدخال مبلغ صحيح',
                                type: ToastType.warning,
                              );
                              return;
                            }
                            final h = SupplierPaymentHistory(
                              debtId: sd.id!,
                              amountPaid: val,
                              paymentDate: DateFormat(
                                'yyyy-MM-dd HH:mm',
                              ).format(DateTime.now()),
                              notes: noteController.text.trim().isEmpty
                                  ? null
                                  : noteController.text.trim(),
                            );
                            await DatabaseHelper.addSupplierPaymentHistory(h);

                            // reload fresh
                            final list =
                                await DatabaseHelper.loadSupplierDebts();
                            final fresh = list.firstWhere((p) => p.id == sd.id);

                            paymentController.clear();
                            noteController.clear();

                            setDialogState(() {
                              sd.paidAmount = fresh.paidAmount;
                              sd.remainingAmount = fresh.remainingAmount;
                              isHistLoading = true; // refresh list
                            });

                            _loadData();
                          },
                          child: const Text('تسجيل دفعة'),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                  ],

                  // History list
                  Text(
                    'سجل سداد المدفوعات للمورد:',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: isHistLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFD4AF37),
                              ),
                            ),
                          )
                        : history.isEmpty
                        ? Center(
                            child: Text(
                              'لا توجد دفعات مسددة مسبقاً لهذا الدين',
                              style: TextStyle(color: textMuted),
                            ),
                          )
                        : ListView.separated(
                            itemCount: history.length,
                            separatorBuilder: (context, index) =>
                                const Divider(),
                            itemBuilder: (context, index) {
                              final h = history[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '- ${h.amountPaid.toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  h.notes ?? 'سداد دفعة للمورد',
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 13,
                                  ),
                                ),
                                trailing: Text(
                                  h.paymentDate.split(' ')[0],
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 12,
                                  ),
                                ),
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
                child: Text(
                  'إغلاق',
                  style: TextStyle(
                    color: AppTheme.textMuted(context),
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printSupplierStatement(SupplierDebt sd) async {
    try {
      final config = await PrinterSettingsService.load();
      final printer = await PrinterSettingsService.resolve(
        config.receiptPrinterName,
        'طابعة الفواتير',
      );

      final pdfTheme = await printServiceGetArabicTheme();
      final pdf = pw.Document();

      final history = await DatabaseHelper.loadSupplierPaymentHistory(sd.id!);

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
                  pw.Text(
                    'محلات العطار استور',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'كشف حساب مستحقات المورد',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'التاريخ: $dateStr',
                    style: const pw.TextStyle(fontSize: 8),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 4),
                  _receiptRowHelper('المورد', sd.supplierName),
                  _receiptRowHelper(
                    'حالة الفاتورة',
                    sd.remainingAmount == 0 ? 'مسددة بالكامل' : 'قيد السداد',
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 4),
                  _receiptRowHelper(
                    'إجمالي الفاتورة',
                    '${sd.totalAmount.toStringAsFixed(2)} ج.م',
                  ),
                  _receiptRowHelper(
                    'المسدد للمورد',
                    '${sd.paidAmount.toStringAsFixed(2)} ج.م',
                  ),
                  _receiptRowHelper(
                    'المتبقي للمورد',
                    '${sd.remainingAmount.toStringAsFixed(2)} ج.م',
                  ),
                  if (sd.dueDate != null)
                    _receiptRowHelper('تاريخ الاستحقاق', sd.dueDate!),
                  pw.SizedBox(height: 4),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'تفاصيل التحصيل والسداد للمورد:',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  ...history.map(
                    (h) => pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '- ${h.amountPaid.toStringAsFixed(0)} ج.م',
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          h.notes ?? 'سداد قسط',
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                        pw.Text(
                          h.paymentDate.split(' ')[0],
                          style: const pw.TextStyle(fontSize: 7.5),
                        ),
                      ],
                    ),
                  ),
                  pw.Divider(thickness: 1),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'العطار استور - تقرير مستحقات الموردين المالي',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.Text(
                    'Developed By Eng:BELALZAGHL0L',
                    style: const pw.TextStyle(fontSize: 6),
                    textAlign: pw.TextAlign.center,
                  ),
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
      debugPrint('Failed to print supplier statement: $e');
    }
  }

  pw.Widget _receiptRowHelper(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '$label:',
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          ),
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
                    '🤝 التعامل مع الموردين والدائنين',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'إضافة وعرض الموردين وتتبع المبالغ والديون المستحقة لهم، وتسجيل دفعات السداد وطباعة كشوف الحسابات المتبادلة',
                    style: TextStyle(fontSize: 15, color: textMuted),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[800],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _showAddSupplierDialog,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                    label: const Text(
                      'إضافة مورد جديد',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryGold,
                      foregroundColor: const Color(0xFF1A2A3A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    onPressed: _showAddManualDebtDialog,
                    icon: const Icon(Icons.add_card_rounded, size: 20),
                    label: const Text(
                      'تسجيل دين مورد يدوياً',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Filters Card
          Card(
            color: AppTheme.cardBg(context),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                style: TextStyle(color: textColor, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'البحث باسم المورد أو الجهة الدائنة...',
                  prefixIcon: Icon(Icons.search, color: primaryGold),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                ? SkeletonLoading.dashboardPage(context)
                : _filteredDebts.isEmpty
                ? AppEmptyState.noData(
                    message: 'لا توجد مديونيات مستحقة للموردين حالياً',
                  )
                : Card(
                    color: AppTheme.cardBg(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: DataTable(
                        headingTextStyle: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: primaryGold,
                          fontSize: 16,
                        ),
                        dataTextStyle: TextStyle(
                          fontFamily: 'Cairo',
                          color: textColor,
                          fontSize: 15,
                        ),
                        columns: const [
                          DataColumn(label: Text('المورد')),
                          DataColumn(label: Text('إجمالي قيمة الفاتورة')),
                          DataColumn(label: Text('المسدد للمورد')),
                          DataColumn(label: Text('الصافي المتبقي للمورد')),
                          DataColumn(label: Text('تاريخ الاستحقاق')),
                          DataColumn(label: Text('الحالة')),
                          DataColumn(label: Text('خيارات')),
                        ],
                        rows: _filteredDebts.map((item) {
                          final isOverdue =
                              item.dueDate != null &&
                              DateTime.parse(
                                item.dueDate!,
                              ).isBefore(DateTime.now()) &&
                              item.remainingAmount > 0;

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  item.supplierName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${item.totalAmount.toStringAsFixed(2)} ج.م',
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${item.paidAmount.toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(color: Colors.green),
                                ),
                              ),
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
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: item.remainingAmount == 0
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : (isOverdue
                                              ? Colors.red.withValues(
                                                  alpha: 0.15,
                                                )
                                              : Colors.orange.withValues(
                                                  alpha: 0.15,
                                                )),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item.remainingAmount == 0
                                        ? 'سداد كامل'
                                        : (isOverdue
                                              ? 'تجاوز الاستحقاق'
                                              : 'جاري السداد'),
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
                                      icon: Icon(
                                        Icons.monetization_on_rounded,
                                        color: primaryGold,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _showRepaymentHistoryDialog(item),
                                      tooltip: 'سداد دفعة / كشف',
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.print,
                                        color: Colors.tealAccent,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _printSupplierStatement(item),
                                      tooltip: 'طباعة كشف حساب المورد',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
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
